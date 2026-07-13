const express = require('express');
const crypto = require('crypto');
const pool = require('../db');
const scopeToOrg = require('../middleware/scopeToOrg');
const requireRole = require('../middleware/requireRole');

const router = express.Router();

router.post('/', scopeToOrg, requireRole('owner', 'admin'), async (req, res) => {
  try {
    const expiresInHours = Math.min(Number(req.body.expires_in_hours) || 24, 168);
    const plaintext = crypto.randomBytes(32).toString('hex');
    const token_hash = crypto.createHash('sha256').update(plaintext).digest('hex');
    const expiresAt = new Date(Date.now() + expiresInHours * 60 * 60 * 1000);

    const { rows } = await pool.query(
      `INSERT INTO enrollment_tokens (org_id, created_by, token_hash, expires_at)
       VALUES ($1, $2, $3, $4)
       RETURNING id, expires_at`,
      [req.orgId, req.userId, token_hash, expiresAt]
    );
    res.status(201).json({ id: rows[0].id, token: plaintext, expires_at: rows[0].expires_at });
  } catch (err) {
    res.status(500).json({ error: 'internal_error' });
  }
});

router.get('/', scopeToOrg, async (req, res) => {
  try {
    const { rows } = await pool.query(
      `SELECT id, created_by, expires_at, used_at
       FROM enrollment_tokens WHERE org_id = $1 ORDER BY created_at DESC`,
      [req.orgId]
    );
    const now = new Date();
    res.json(rows.map(r => ({ ...r, is_expired: new Date(r.expires_at) < now })));
  } catch (err) {
    res.status(500).json({ error: 'internal_error' });
  }
});

router.delete('/:id', scopeToOrg, requireRole('owner', 'admin'), async (req, res) => {
  try {
    const { rows } = await pool.query(
      'DELETE FROM enrollment_tokens WHERE id = $1 AND org_id = $2 RETURNING id',
      [req.params.id, req.orgId]
    );
    if (!rows.length) return res.status(404).json({ error: 'not_found' });
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: 'internal_error' });
  }
});

module.exports = router;
