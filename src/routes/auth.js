const express = require('express');
const argon2 = require('argon2');
const jwt = require('jsonwebtoken');
const pool = require('../db');

const router = express.Router();

router.post('/login', async (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) {
    return res.status(401).json({ error: 'invalid_credentials' });
  }

  try {
    const { rows: users } = await pool.query(
      'SELECT id, email, password_hash, display_name FROM users WHERE email = $1',
      [email]
    );
    if (!users.length) {
      return res.status(401).json({ error: 'invalid_credentials' });
    }
    const user = users[0];

    const valid = await argon2.verify(user.password_hash, password);
    if (!valid) {
      return res.status(401).json({ error: 'invalid_credentials' });
    }

    const { rows: memberships } = await pool.query(
      `SELECT m.role, o.id AS org_id, o.name, o.slug
       FROM memberships m
       JOIN organizations o ON o.id = m.org_id
       WHERE m.user_id = $1
       ORDER BY m.created_at ASC
       LIMIT 1`,
      [user.id]
    );
    if (!memberships.length) {
      return res.status(401).json({ error: 'invalid_credentials' });
    }
    const membership = memberships[0];

    const token = jwt.sign(
      { sub: user.id, org_id: membership.org_id, role: membership.role },
      process.env.JWT_SECRET,
      { expiresIn: '8h' }
    );

    res.json({
      token,
      user: { id: user.id, email: user.email, display_name: user.display_name },
      org: { id: membership.org_id, name: membership.name, slug: membership.slug },
    });
  } catch (err) {
    console.error('Login error:', err.message);
    res.status(500).json({ error: 'internal_error' });
  }
});

module.exports = router;
