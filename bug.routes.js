// bug.routes.js
const express = require('express');
const db = require('./db');

const router = express.Router();

router.post('/report', (req, res) => {
  console.log('[POST /report] Incoming:', req.body);
  try {
    const { date, description, status } = req.body;

    // Validate input
    if (!date || !description || !status) {
      console.error('[POST /report] Missing required fields:', req.body);
      return res.status(400).json({ error: 'Missing required fields' });
    }

    // Create the bug report
    db.createBugReport({date, description, status });
    console.log('[POST /report] Success: Bug report created', { date, description, status });
    res.status(201).json({ message: 'Bug report created successfully' });
  } catch (e) {
    console.error('[POST /report] Error:', e);
    res.status(500).json({ error: 'Server error' });
  }
});


router.get('/reports/:id', (req, res) => {
  console.log('[GET /reports/:id] Incoming: id', req.params.id);
  try {
    const reportId = req.params.id;
    const report = db.getBugReportById(reportId);
    if (!report) {
      console.error('[GET /reports/:id] Not found:', reportId);
      return res.status(404).json({ error: 'Bug report not found' });
    }
    console.log('[GET /reports/:id] Sending:', report);
    res.json(report);
  } catch (e) {
    console.error('[GET /reports/:id] Error:', e);
    res.status(500).json({ error: 'Server error' });
  }
});

router.patch('/bugreport/:id/status', (req, res) => {
  console.log('[PATCH /bugreport/:id/status] Incoming:', { id: req.params.id, status: req.body.status });
  try {
    const { status } = req.body;
    const { id } = req.params;
    db.updateBugReportStatus(id, status);
    console.log('[PATCH /bugreport/:id/status] Success: Updated status for bug report', id);
    res.json({ ok: true });
  } catch (e) {
    console.error('[PATCH /bugreport/:id/status] Error:', e);
    res.status(500).json({ error: 'Server error' });
  }
});

module.exports = router;