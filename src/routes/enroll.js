const express = require('express');
const crypto = require('crypto');
const pool = require('../db');

const router = express.Router();

router.post('/', async (req, res) => {
  const { token, hostname, os_type, os_version } = req.body;
  if (!token || !hostname) {
    return res.status(400).json({ error: 'token_and_hostname_required' });
  }

  const token_hash = crypto.createHash('sha256').update(token).digest('hex');

  try {
    const { rows } = await pool.query(
      `SELECT id, org_id, expires_at, used_at
       FROM enrollment_tokens WHERE token_hash = $1`,
      [token_hash]
    );

    if (!rows.length) return res.status(401).json({ error: 'invalid_token' });
    const record = rows[0];
    if (record.used_at !== null) return res.status(401).json({ error: 'invalid_token' });
    if (new Date(record.expires_at) <= new Date()) return res.status(401).json({ error: 'invalid_token' });

    const client = await pool.connect();
    try {
      await client.query('BEGIN');

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
      throw err;
    } finally {
      client.release();
    }
  } catch (err) {
    res.status(500).json({ error: 'internal_error' });
  }
});

module.exports = router;
