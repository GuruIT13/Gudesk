require('dotenv').config({ path: require('path').join(__dirname, '..', '..', '.env') });
const jwt = require('jsonwebtoken');

function scopeToOrg(req, res, next) {
  const header = req.headers['authorization'];
  if (!header || !header.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'unauthorized' });
  }
  const token = header.slice(7);
  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET);
    req.userId = payload.sub;
    req.orgId = payload.org_id;
    req.role = payload.role;
    next();
  } catch {
    return res.status(401).json({ error: 'unauthorized' });
  }
}

module.exports = scopeToOrg;
