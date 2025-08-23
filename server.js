const express = require('express');
const sqlite3 = require('sqlite3').verbose();
const path = require('path');
require('dotenv').config();

const app = express();
app.use(express.json());
const PORT = process.env.PORT || 3000;
const HOST = '0.0.0.0';

// Connect to SQLite database (creates file if it doesn't exist)
const dbPath = path.join(__dirname, 'database.sqlite');
const db = new sqlite3.Database(dbPath, (err) => {
  if (err) {
    console.error('Could not connect to database', err);
  } else {
    console.log('Connected to SQLite database');
    // Create table if it doesn't exist
    db.run(`CREATE TABLE IF NOT EXISTS chat_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT NOT NULL UNIQUE,
      compressed_history BLOB NOT NULL,
      summary TEXT NOT NULL
    )`, (err) => {
      if (err) {
        console.error('Error creating table', err);
      } else {
        console.log('Table chat_logs is ready');
      }
    });
  }
});

// Basic route
app.get('/', (req, res) => {
  res.send('Node.js + SQLite server is running!');
});

// Route to store a new chat log
app.post('/chatlog', (req, res) => {
  const { date, compressed_history, summary } = req.body;
  console.log('Attempting to upsert chat log:', { date, compressed_history, summary });
  if (!date || !compressed_history || !summary) {
    return res.status(400).json({ error: 'Missing required fields' });
  }
  const sql = `INSERT INTO chat_logs (date, compressed_history, summary)
    VALUES (?, ?, ?)
    ON CONFLICT(date) DO UPDATE SET
      compressed_history = excluded.compressed_history,
      summary = excluded.summary`;
  db.run(sql, [date, compressed_history, summary], function(err) {
    if (err) {
      return res.status(500).json({ error: 'Failed to upsert chat log' });
    }
    res.json({ id: this.lastID });
  });
});

// Route to retrieve a chat log by ID
app.get('/chatlog/:id', (req, res) => {
  const id = req.params.id;
  const sql = 'SELECT * FROM chat_logs WHERE id = ?';
  db.get(sql, [id], (err, row) => {
    if (err) {
      return res.status(500).json({ error: 'Failed to retrieve chat log' });
    }
    if (!row) {
      return res.status(404).json({ error: 'Chat log not found' });
    }
    res.json(row);
  });
});

// Route to retrieve summaries by date
app.get('/summaries/:date', (req, res) => {
  const date = req.params.date;
  const sql = 'SELECT summary FROM chat_logs WHERE date = ?';
  db.all(sql, [date], (err, rows) => {
    if (err) {
      return res.status(500).json({ error: 'Failed to retrieve summaries' });
    }
    if (!rows || rows.length === 0) {
      return res.status(404).json({ error: 'No summaries found for this date' });
    }
    res.json({ summaries: rows.map(r => r.summary) });
  });
});

// Start server
app.listen(PORT, HOST, () => {
  console.log(`Server running at http://${HOST}:${PORT}/`);
});
