require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const express = require('express');
const scopeToOrg = require('./middleware/scopeToOrg');
const authRouter = require('./routes/auth');
const directoriesRouter = require('./routes/directories');
const pool = require('./db');

const app = express();
app.use(express.json());

app.use('/api/auth', authRouter);
app.use('/api/directories', directoriesRouter);

app.get('/api/ping', scopeToOrg, (req, res) => {
  res.json({ ok: true, userId: req.userId, orgId: req.orgId });
});

// Stub device route — will be replaced by real devices router in Task 3
app.get('/api/devices/:id', scopeToOrg, async (req, res) => {
  const { rows } = await pool.query(
    'SELECT id, hostname, status FROM devices WHERE id = $1 AND org_id = $2',
    [req.params.id, req.orgId]
  );
  if (!rows.length) return res.status(404).json({ error: 'not_found' });
  res.json(rows[0]);
});

module.exports = app;
