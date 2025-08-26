// chat.routes.js
const express = require('express');
const db = require('./db');
const { verifyAccessToken } = require('./auth.util');

const router = express.Router();

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

/**
 * POST /chatlog
 * body: { date: "YYYY-MM-DD", compressedHistory: string, summary: string }
 * - Upserts per (user_uuid, date)
 */
router.post('/history', requireAuth, (req, res) => {
  const { date, compressedHistory, summary } = req.body || {};
  console.log('[POST /chatlog] Incoming:', { userUuid: req.userId, date, compressedHistory, summary });
  if (!date || typeof compressedHistory !== 'string' || !summary) {
    console.log('[POST /chatlog] Error: Missing required fields or invalid types');
    return res.status(400).json({ error: 'Missing required fields or invalid types' });
  }
  try {
    const id = db.upsertChatLog({
      userUuid: req.userId,
      date,
      compressedHistory: compressedHistory,
      summary,
    });
    console.log('[POST /chatlog] Success: Inserted/Updated ID', id);
    return res.json({ id });
  } catch (e) {
    console.error('[POST /chatlog] chatlog upsert error', e);
    return res.status(500).json({ error: 'Failed to upsert chat log' });
  }
});

/**
 * GET /chatlog/:id
 * - Returns the row only if it belongs to the current user
 */
router.get('/chatlog/:id', requireAuth, (req, res) => {
  console.log('[GET /chatlog/:id] Incoming:', { userUuid: req.userId, id: req.params.id });
  try {
    const row = db.getChatLogById(Number(req.params.id));
    if (!row || row.user_uuid !== req.userId) {
      console.log('[GET /chatlog/:id] Not found or unauthorized');
      return res.status(404).json({ error: 'Chat log not found' });
    }
    console.log('[GET /chatlog/:id] Success:', row);
    return res.json(row);
  } catch (e) {
    console.error('[GET /chatlog/:id] chatlog get error', e);
    return res.status(500).json({ error: 'Failed to retrieve chat log' });
  }
});

/**
 * GET /summaries/:date
 * - Returns summaries for this user & date
 */
router.get('/summaries/:date', requireAuth, (req, res) => {
  console.log('[GET /summaries/:date] Incoming:', { userUuid: req.userId, date: req.params.date });
  try {
    const summaries = db.getSummariesByDate({ userUuid: req.userId, date: req.params.date });
    if (!summaries.length) {
      console.log('[GET /summaries/:date] No summaries found');
      return res.status(404).json({ error: 'No summaries found for this date' });
    }
    console.log('[GET /summaries/:date] Success:', summaries);
    return res.json({ summaries });
  } catch (e) {
    console.error('[GET /summaries/:date] summaries error', e);
    return res.status(500).json({ error: 'Failed to retrieve summaries' });
  }
});

/**
 * GET /history/:date
 * - Returns compressed_history for this user & date
 */
router.get('/history/:date', requireAuth, (req, res) => {
  console.log('[GET /history/:date] Incoming:', { userUuid: req.userId, date: req.params.date });
  try {
    const history = db.getHistoryByDate({ userUuid: req.userId, date: req.params.date });
    if (!history) {
      console.log('[GET /history/:date] No history found');
      return res.status(404).json({ error: 'No history found for this date' });
    }
    console.log('[GET /history/:date] Success:', history);
    return res.json({ compressed_history: history });
  } catch (e) {
    console.error('[GET /history/:date] history error', e);
    return res.status(500).json({ error: 'Failed to retrieve history' });
  }
});

module.exports = router;
