require('dotenv').config();
const express = require('express');
const cors = require('cors');
const app = express();

app.use(cors(), express.json());
app.get(process.env.API_HEALTH_ROUTE || '/health', (req, res) => res.send('OK'));

app.listen(process.env.PORT || 3000, () => console.log('API rodando.'));
