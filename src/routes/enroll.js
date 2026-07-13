const express = require('express');
const crypto = require('crypto');
const pool = require('../db');

const router = express.Router();

router.post('/', async (req, res) => {
  const { token, hostname, os_type, os_version } = req.body;
  if (!token || !hostname) {
    return res.status(400).json({ error: 'token_and_hostname_required' });
  }
  if (typeof hostname !== 'string' || hostname.length > 255) {
    return res.status(400).json({ error: 'invalid_hostname' });
  }
  if (os_type != null && (typeof os_type !== 'string' || os_type.length > 50)) {
    return res.status(400).json({ error: 'invalid_os_type' });
  }
  if (os_version != null && (typeof os_version !== 'string' || os_version.length > 100)) {
    return res.status(400).json({ error: 'invalid_os_version' });
  }

  const token_hash = crypto.createHash('sha256').update(token).digest('hex');
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // SELECT FOR UPDATE closes the TOCTOU race — concurrent requests block until first commits
    const { rows } = await client.query(
      `SELECT id, org_id, expires_at, used_at
       FROM enrollment_tokens WHERE token_hash = $1 FOR UPDATE`,
      [token_hash]
    );

    if (!rows.length) {
      await client.query('ROLLBACK');
      return res.status(401).json({ error: 'invalid_token' });
    }
    const record = rows[0];
    if (record.used_at !== null) {
      await client.query('ROLLBACK');
      return res.status(401).json({ error: 'invalid_token' });
    }
    if (new Date(record.expires_at) <= new Date()) {
      await client.query('ROLLBACK');
      return res.status(401).json({ error: 'invalid_token' });
    }

    const { rows: deviceRows } = await client.query(
      `INSERT INTO devices (org_id, device_uid, public_key, hostname, os_type, os_version, status)
       VALUES ($1, gen_random_uuid(), '', $2, $3, $4, 'offline')
       RETURNING id, device_uid, org_id`,
      [record.org_id, hostname, os_type || null, os_version || null]
    );

    await client.query(
      'UPDATE enrollment_tokens SET used_at = now() WHERE id = $1',
      [record.id]
    );

    await client.query('COMMIT');
    res.status(201).json({
      device_id: deviceRows[0].id,
      device_uid: deviceRows[0].device_uid,
      org_id: deviceRows[0].org_id,
    });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Enrollment error:', err.message);
    res.status(500).json({ error: 'internal_error' });
  } finally {
    client.release();
  }
});

module.exports = router;
