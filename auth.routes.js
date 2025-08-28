// auth.routes.js
const express = require('express');
const bcrypt = require('bcrypt');
const { v4: uuidv4 } = require('uuid');

const db = require('./db');
const {
  sha256, randomTokenRaw, signAccessToken, verifyAccessToken, addDaysISO
} = require('./auth.util');

const router = express.Router();

/**
 * POST /auth/register
 * body: { email, password }
 */
router.post('/register', async (req, res) => {
  console.log('[POST /auth/register] Incoming:', req.body);
  try {
    const { email, password } = req.body || {};
    if (!email || !password || typeof email !== 'string' || typeof password !== 'string') {
      return res.status(400).json({ error: 'Invalid inputs' });
    }

    const existing = db.getUserByEmail(email);
    if (existing) return res.status(409).json({ error: 'Email already in use' });

    const passwordHash = await bcrypt.hash(password, 12);
    const userId = uuidv4();

    db.createUser({ id: userId, email, passwordHash });

    // issue tokens
    const accessToken = signAccessToken(userId);
    const refreshRaw = randomTokenRaw();
    const refreshHash = sha256(refreshRaw);
    const expiresAtISO = addDaysISO(parseInt(process.env.REFRESH_TOKEN_TTL_DAYS || '30', 10));

    db.createRefreshToken({
      id: uuidv4(),
      userId,
      tokenHash: refreshHash,
      expiresAtISO,
    });

    console.log('[POST /auth/register] Success:', { user: { id: userId, email } });
    return res.status(201).json({
      user: { id: userId, email },
      tokens: { accessToken, refreshToken: refreshRaw, refreshExpiresAt: expiresAtISO },
    });
  } catch (e) {
    console.error('[POST /auth/register] Error:', e);
    return res.status(500).json({ error: 'Server error' });
  }
});

/**
 * POST /auth/login
 * body: { email, password }
 */
router.post('/login', async (req, res) => {
  console.log('[POST /auth/login] Incoming:', req.body);
  try {
    const { email, password } = req.body || {};
    if (!email || !password) return res.status(400).json({ error: 'Invalid inputs' });

    const user = db.getUserByEmail(email);
    if (!user) return res.status(401).json({ error: 'Invalid credentials' });

    const ok = await bcrypt.compare(password, user.password_hash);
    if (!ok) return res.status(401).json({ error: 'Invalid credentials' });

    const accessToken = signAccessToken(user.id);
    const refreshRaw = randomTokenRaw();
    const refreshHash = sha256(refreshRaw);
    const expiresAtISO = addDaysISO(parseInt(process.env.REFRESH_TOKEN_TTL_DAYS || '30', 10));

    db.createRefreshToken({
      id: uuidv4(),
      userId: user.id,
      tokenHash: refreshHash,
      expiresAtISO,
    });

    console.log('[POST /auth/login] Success:', { user: { id: user.id, email: user.email } });
    return res.json({
      user: { id: user.id, email: user.email },
      tokens: { accessToken, refreshToken: refreshRaw, refreshExpiresAt: expiresAtISO },
    });
  } catch (e) {
    console.error('[POST /auth/login] Error:', e);
    return res.status(500).json({ error: 'Server error' });
  }
});

/**
 * POST /auth/refresh
 * body: { userId, refreshToken }
 * - rotate refresh token
 */
router.post('/refresh', (req, res) => {
  console.log('[POST /auth/refresh] Incoming:', req.body);
  try {
    const { userId, refreshToken } = req.body || {};
    if (!userId || !refreshToken) {
      console.error('[POST /auth/refresh] Error: Missing fields', { userId, refreshToken });
      return res.status(400).json({ error: 'Missing fields' });
    }

    const hash = sha256(refreshToken);
    const record = db.getRefreshByHash(hash);

    const now = Date.now();
    const isExpired = !record ? true : new Date(record.expires_at).getTime() <= now;
    const isRevoked = record && record.revoked_at != null;
    const userMismatch = record && record.user_id !== userId;

    if (!record || isExpired || isRevoked || userMismatch) {
      // defensive: revoke all for user if we can identify (reuse detection scenario)
      if (record && record.user_id) {
        console.error('[POST /auth/refresh] Error: Invalid refresh token', {
          record, isExpired, isRevoked, userMismatch
        });
        console.log('[POST /auth/refresh] Calling revokeAllForUser');
        db.revokeAllForUser(record.user_id);
      }
      return res.status(401).json({ error: 'Invalid refresh token' });
    }

    // rotate: revoke old, issue new
    console.log('[POST /auth/refresh] Calling revokeByHash');
    db.revokeByHash(hash);

    const newRaw = randomTokenRaw();
    const newHash = sha256(newRaw);
    const expiresAtISO = addDaysISO(parseInt(process.env.REFRESH_TOKEN_TTL_DAYS || '30', 10));

    db.createRefreshToken({
      id: uuidv4(),
      userId,
      tokenHash: newHash,
      expiresAtISO,
    });

    const accessToken = signAccessToken(userId);
    console.log('[POST /auth/refresh] Success:', { userId });
    return res.json({
      tokens: { accessToken, refreshToken: newRaw, refreshExpiresAt: expiresAtISO },
    });
  } catch (e) {
    console.error('[POST /auth/refresh] Error:', e);
    return res.status(500).json({ error: 'Server error' });
  }
});

/**
 * POST /auth/logout
 * body: { refreshToken }
 */
router.post('/logout', (req, res) => {
  console.log('[POST /auth/logout] Incoming:', req.body);
  try {
    const { refreshToken } = req.body || {};
    if (!refreshToken) return res.status(400).json({ error: 'Missing refreshToken' });
    const hash = sha256(refreshToken);
    console.log('[POST /auth/logout] Calling revokeByHash');
    db.revokeByHash(hash);
    console.log('[POST /auth/logout] Success');
    return res.json({ ok: true });
  } catch (e) {
    console.error('[POST /auth/logout] Error:', e);
    return res.status(500).json({ error: 'Server error' });
  }
});

/**
 * GET /auth/me (protected)
 */
router.get('/me', requireAuth, (req, res) => {
  console.log('[GET /auth/me] Incoming:', { userId: req.userId });
  const user = db.getUserById(req.userId);
  if (!user) {
    console.log('[GET /auth/me] Not found');
    return res.status(404).json({ error: 'Not found' });
  }
  console.log('[GET /auth/me] Success:', { id: user.id, email: user.email });
  return res.json({ id: user.id, email: user.email });
});

// --- middleware to protect routes ---
function requireAuth(req, res, next) {
  const header = req.headers['authorization'] || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'Missing token' });
  try {
    const payload = verifyAccessToken(token);
    req.userId = payload.sub;
    next();
  } catch {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
}

module.exports = router;
