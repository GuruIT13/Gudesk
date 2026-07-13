const express = require('express');
const pool = require('../db');
const scopeToOrg = require('../middleware/scopeToOrg');
const requireRole = require('../middleware/requireRole');

const router = express.Router();

// GET /api/devices?directory_id=xxx
router.get('/', scopeToOrg, async (req, res) => {
  try {
    const { directory_id } = req.query;
    let query, params;
    if (directory_id) {
      query = `SELECT id, hostname, status, os_type, directory_id, last_seen_at
               FROM devices WHERE org_id = $1 AND directory_id = $2`;
      params = [req.orgId, directory_id];
    } else {
      query = `SELECT id, hostname, status, os_type, directory_id, last_seen_at
               FROM devices WHERE org_id = $1`;
      params = [req.orgId];
    }
    const { rows } = await pool.query(query, params);
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: 'internal_error' });
  }
});

// GET /api/devices/:id
router.get('/:id', scopeToOrg, async (req, res) => {
  try {
    const { rows } = await pool.query(
      `SELECT id, hostname, status, os_type, os_version, directory_id,
              last_seen_at, last_ip, device_uid
       FROM devices WHERE id = $1 AND org_id = $2`,
      [req.params.id, req.orgId]
    );
    if (!rows.length) return res.status(404).json({ error: 'not_found' });
    res.json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'internal_error' });
  }
});

// PATCH /api/devices/:id
router.patch('/:id', scopeToOrg, requireRole('owner', 'admin'), async (req, res) => {
  const { hostname, directory_id } = req.body;
  try {
    const { rows: existing } = await pool.query(
      'SELECT id FROM devices WHERE id = $1 AND org_id = $2',
      [req.params.id, req.orgId]
    );
    if (!existing.length) return res.status(404).json({ error: 'not_found' });

    if (directory_id !== undefined && directory_id !== null) {
      const { rows: dir } = await pool.query(
        'SELECT id FROM directories WHERE id = $1 AND org_id = $2',
        [directory_id, req.orgId]
      );
      if (!dir.length) return res.status(404).json({ error: 'not_found' });
    }

    const { rows } = await pool.query(
      `UPDATE devices
       SET hostname = COALESCE($1, hostname),
           directory_id = CASE WHEN $2::boolean THEN $3::uuid ELSE directory_id END,
           updated_at = now()
       WHERE id = $4 AND org_id = $5
       RETURNING id, hostname, directory_id, updated_at`,
      [hostname || null, directory_id !== undefined, directory_id || null, req.params.id, req.orgId]
    );
    res.json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'internal_error' });
  }
});

// DELETE /api/devices/:id
router.delete('/:id', scopeToOrg, requireRole('owner', 'admin'), async (req, res) => {
  try {
    const { rows } = await pool.query(
      'DELETE FROM devices WHERE id = $1 AND org_id = $2 RETURNING id',
      [req.params.id, req.orgId]
    );
    if (!rows.length) return res.status(404).json({ error: 'not_found' });
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: 'internal_error' });
  }
});

module.exports = router;
