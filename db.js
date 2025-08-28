// db.js
const Database = require('better-sqlite3');
const path = require('path');

const db = new Database(path.resolve(__dirname, 'app.db')); // change if needed
db.pragma('journal_mode = WAL');

// --- schema ---
db.exec(`
CREATE TABLE IF NOT EXISTS chat_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_uuid TEXT NOT NULL,
  date TEXT NOT NULL,
  compressed_history TEXT NOT NULL,
  summary TEXT NOT NULL,
  UNIQUE(user_uuid, date)
);

CREATE TABLE IF NOT EXISTS bug_reports (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  description TEXT NOT NULL,
  status TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS refresh_tokens (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  token_hash TEXT NOT NULL,
  expires_at DATETIME NOT NULL,
  revoked_at DATETIME,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_refresh_token_hash ON refresh_tokens(token_hash);
CREATE INDEX IF NOT EXISTS idx_refresh_user ON refresh_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_chatlogs_user_date ON chat_logs(user_uuid, date);
`);

// ---------- prepared statements (users) ----------
const stmtInsertUser = db.prepare(`
  INSERT INTO users (id, email, password_hash) VALUES (?, ?, ?)
`);
const stmtGetUserByEmail = db.prepare(`
  SELECT id, email, password_hash FROM users WHERE email = ?
`);
const stmtGetUserById = db.prepare(`
  SELECT id, email FROM users WHERE id = ?
`);

// ---------- prepared statements (refresh tokens) ----------
const stmtInsertRefresh = db.prepare(`
  INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at) VALUES (?, ?, ?, ?)
`);
const stmtGetRefreshByHash = db.prepare(`
  SELECT id, user_id, token_hash, expires_at, revoked_at
  FROM refresh_tokens WHERE token_hash = ?
`);
const stmtRevokeByHash = db.prepare(`
  UPDATE refresh_tokens SET revoked_at = CURRENT_TIMESTAMP
  WHERE token_hash = ? AND revoked_at IS NULL
`);
const stmtRevokeAllForUser = db.prepare(`
  UPDATE refresh_tokens SET revoked_at = CURRENT_TIMESTAMP
  WHERE user_id = ? AND revoked_at IS NULL
`);

// ---------- prepared statements (chat logs) ----------
const stmtUpsertChatLog = db.prepare(`
  INSERT INTO chat_logs (user_uuid, date, compressed_history, summary)
  VALUES (?, ?, ?, ?)
  ON CONFLICT(user_uuid, date) DO UPDATE SET
    compressed_history = excluded.compressed_history,
    summary = excluded.summary
`);
const stmtGetChatLogIdByUserDate = db.prepare(`
  SELECT id FROM chat_logs WHERE user_uuid = ? AND date = ?
`);
const stmtGetChatLogById = db.prepare(`
  SELECT id, user_uuid, date, compressed_history, summary
  FROM chat_logs WHERE id = ?
`);
const stmtGetSummariesByDate = db.prepare(`
  SELECT summary FROM chat_logs WHERE user_uuid = ? AND date = ?
`);
const stmtGetHistoryByDate = db.prepare(`
  SELECT compressed_history FROM chat_logs WHERE user_uuid = ? AND date = ?
`);

// ---------- prepared statements (bug reports) ---------
const stmtInsertBugReport = db.prepare(`
  INSERT INTO bug_reports (date, description, status)
  VALUES (?, ?, ?)
`);
const stmtGetBugReportById = db.prepare(`
  SELECT id, date, description, status
  FROM bug_reports WHERE id = ?
`);
const stmtUpdateBugReportStatus = db.prepare(`
  UPDATE bug_reports SET status = ?
  WHERE id = ?
`);

// ---------- exports ----------
module.exports = {
  // users
  createUser({ id, email, passwordHash }) {
    stmtInsertUser.run(id, email, passwordHash);
  },
  getUserByEmail(email) { return stmtGetUserByEmail.get(email) || null; },
  getUserById(id) { return stmtGetUserById.get(id) || null; },

  // refresh tokens
  createRefreshToken({ id, userId, tokenHash, expiresAtISO }) {
    stmtInsertRefresh.run(id, userId, tokenHash, expiresAtISO);
  },
  getRefreshByHash(tokenHash) { return stmtGetRefreshByHash.get(tokenHash) || null; },
  revokeByHash(tokenHash) {
    const revokeTime = new Date().toISOString();
    console.log(`[db.revokeByHash] Revoking token ${tokenHash} at ${revokeTime}`);
    stmtRevokeByHash.run(tokenHash);
  },
  revokeAllForUser(userId) { stmtRevokeAllForUser.run(userId); },

  // chat logs
  upsertChatLog({ userUuid, date, compressedHistory, summary }) {
    stmtUpsertChatLog.run(userUuid, date, compressedHistory, summary);
    // ensure we return the id even on UPDATE
    const row = stmtGetChatLogIdByUserDate.get(userUuid, date);
    return row?.id ?? null;
  },
  getChatLogById(id) { return stmtGetChatLogById.get(id) || null; },
  getSummariesByDate({ userUuid, date }) {
    return stmtGetSummariesByDate.all(userUuid, date).map(r => r.summary);
  },
  getHistoryByDate({ userUuid, date }) {
    const row = stmtGetHistoryByDate.get(userUuid, date);
    return row ? row.compressed_history : null;
  },

  // bug reports
  createBugReport({date, description, status }) {
    stmtInsertBugReport.run(date, description, status);
  },
  getBugReportById(id) { return stmtGetBugReportById.get(id) || null; },
  getBugReportsByUser(userUuid) {
    return stmtGetBugReportsByUser.all(userUuid);
  },
  updateBugReportStatus(id, status) {
    stmtUpdateBugReportStatus.run(status, id);
  },

  _db: db,
};