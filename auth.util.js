// auth.util.js
const crypto = require('crypto');
const jwt = require('jsonwebtoken');

function sha256(s) {
  return crypto.createHash('sha256').update(s).digest('hex');
}

function randomTokenRaw() {
  return crypto.randomBytes(32).toString('base64url');
}

function signAccessToken(userId) {
  // ACCESS_TOKEN_TTL in seconds, e.g., 900 (15m)
  const ttl = parseInt(process.env.ACCESS_TOKEN_TTL || '900', 10);
  return jwt.sign({ sub: userId }, process.env.JWT_SECRET, { expiresIn: ttl });
}

function verifyAccessToken(token) {
  return jwt.verify(token, process.env.JWT_SECRET); // throws if invalid/expired
}

function addDaysISO(days) {
  return new Date(Date.now() + days * 24 * 60 * 60 * 1000).toISOString();
}

module.exports = {
  sha256,
  randomTokenRaw,
  signAccessToken,
  verifyAccessToken,
  addDaysISO,
};
