const express = require('express');
const pool = require('../db');
const scopeToOrg = require('../middleware/scopeToOrg');
const requireRole = require('../middleware/requireRole');

const router = express.Router();

function buildTree(rows) {
  const map = {};
  rows.forEach(r => { map[r.id] = { ...r, children: [] }; });
  const roots = [];
  rows.forEach(r => {
    if (r.parent_id && map[r.parent_id]) {
      map[r.parent_id].children.push(map[r.id]);
    } else {
      roots.push(map[r.id]);
    }
  });
  return roots;
}

// GET /api/directories
router.get('/', scopeToOrg, async (req, res) => {
  try {
    const { rows } = await pool.query(
      'SELECT id, name, parent_id, created_at FROM directories WHERE org_id = $1 ORDER BY parent_id NULLS FIRST',
      [req.orgId]
    );
    res.json(buildTree(rows));
  } catch (err) {
    res.status(500).json({ error: 'internal_error' });
  }
});

// POST /api/directories
router.post('/', scopeToOrg, async (req, res) => {
  const { name, parent_id = null } = req.body;
  if (!name) return res.status(400).json({ error: 'name_required' });
  try {
    if (parent_id) {
      const { rows } = await pool.query(
        'SELECT id FROM directories WHERE id = $1 AND org_id = $2',
        [parent_id, req.orgId]
      );
      if (!rows.length) return res.status(404).json({ error: 'not_found' });
    }
    const { rows } = await pool.query(
      `INSERT INTO directories (org_id, parent_id, name, created_by)
       VALUES ($1, $2, $3, $4)
       RETURNING id, name, parent_id, org_id, created_at`,
      [req.orgId, parent_id, name, req.userId]
    );
    res.status(201).json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'internal_error' });
  }
});

// PATCH /api/directories/:id
router.patch('/:id', scopeToOrg, requireRole('owner', 'admin'), async (req, res) => {
  const { name, parent_id } = req.body;
  try {
    const { rows: existing } = await pool.query(
      'SELECT id FROM directories WHERE id = $1 AND org_id = $2',
      [req.params.id, req.orgId]
    );
    if (!existing.length) return res.status(404).json({ error: 'not_found' });

    if (parent_id !== undefined && parent_id !== null) {
      const { rows: parent } = await pool.query(
        'SELECT id FROM directories WHERE id = $1 AND org_id = $2',
        [parent_id, req.orgId]
      );
      if (!parent.length) return res.status(404).json({ error: 'not_found' });
    }

    const { rows } = await pool.query(
      `UPDATE directories
       SET name = COALESCE($1, name),
           parent_id = CASE WHEN $2::boolean THEN $3::uuid ELSE parent_id END,
           updated_at = now()
       WHERE id = $4 AND org_id = $5
       RETURNING id, name, parent_id, updated_at`,
      [name || null, parent_id !== undefined, parent_id || null, req.params.id, req.orgId]
    );
    res.json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'internal_error' });
  }
});

// DELETE /api/directories/:id
router.delete('/:id', scopeToOrg, requireRole('owner', 'admin'), async (req, res) => {
  try {
    const { rows: existing } = await pool.query(
      'SELECT id FROM directories WHERE id = $1 AND org_id = $2',
      [req.params.id, req.orgId]
    );
    if (!existing.length) return res.status(404).json({ error: 'not_found' });

    const { rows: devCount } = await pool.query(
      'SELECT COUNT(*) FROM devices WHERE directory_id = $1',
      [req.params.id]
    );
    if (parseInt(devCount[0].count) > 0) {
      return res.status(409).json({ error: 'directory_has_devices' });
    }

    const { rows: childCount } = await pool.query(
      'SELECT COUNT(*) FROM directories WHERE parent_id = $1',
      [req.params.id]
    );
    if (parseInt(childCount[0].count) > 0) {
      return res.status(409).json({ error: 'directory_has_children' });
    }

    await pool.query('DELETE FROM directories WHERE id = $1 AND org_id = $2', [req.params.id, req.orgId]);
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: 'internal_error' });
  }
});

module.exports = router;
