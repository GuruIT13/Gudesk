require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const express = require('express');
const scopeToOrg = require('./middleware/scopeToOrg');
const authRouter = require('./routes/auth');
const directoriesRouter = require('./routes/directories');
const devicesRouter = require('./routes/devices');
const enrollmentTokensRouter = require('./routes/enrollmentTokens');
const enrollRouter = require('./routes/enroll');

const app = express();
app.use(express.json());

app.use('/api/auth', authRouter);
app.use('/api/directories', directoriesRouter);
app.use('/api/devices/enroll', enrollRouter);
app.use('/api/devices', devicesRouter);
app.use('/api/enrollment-tokens', enrollmentTokensRouter);

app.get('/api/ping', scopeToOrg, (req, res) => {
  res.json({ ok: true, userId: req.userId, orgId: req.orgId });
});

module.exports = app;
