const mysql = require('mysql2/promise');
module.exports = mysql.createPool({
  host: 'localhost',
  user: 'griply',
  password: process.env.DB_PASS,
  database: 'griply'
});
