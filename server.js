// app.js
require('dotenv').config();
const express = require('express');
const cors = require('cors');

const authRoutes = require('./auth.routes');
const chatRoutes = require('./chat.routes'); 
const bugRoutes = require('./bug.routes');

const app = express();
app.use(express.json());
app.use(cors({ origin: true, credentials: true }));

app.get('/health', (_, res) => res.json({ ok: true }));

app.use('/auth', authRoutes);
app.use('/', chatRoutes); // exposes /chatlog, /summaries/:date, /history/:date
app.use('/bugs', bugRoutes); // exposes /bugs/report, /bugs/reports/:id, /bugs/:id/status

const port = process.env.PORT || 3001;
app.listen(port, () => console.log(`Server on :${port}`));
