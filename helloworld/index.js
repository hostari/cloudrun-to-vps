import express from 'express';
import pg from 'pg';
import { Connector } from '@google-cloud/cloud-sql-connector';

const app = express();

// Cloud SQL connection configuration
const connector = new Connector();
const clientConfig = await connector.getOptions({
  instanceConnectionName: process.env.INSTANCE_CONNECTION_NAME,
  ipType: 'PUBLIC',
});

const pool = new pg.Pool({
  ...clientConfig,
  user: process.env.DB_USER,
  password: process.env.DB_PASS,
  database: process.env.DB_NAME,
});

app.get('/', async (req, res) => {
  const name = process.env.NAME || 'World';
  const timestamp = new Date();
  try {
    await pool.query(
      'INSERT INTO visits (visitor_name, timestamp) VALUES ($1, $2)',
      [name, timestamp]
    );
    res.send(`Hello ${name}!`);
  } catch (err) {
    console.error('Error inserting visit:', err);
    res.status(500).send('Internal Server Error');
  }
});

const port = parseInt(process.env.PORT) || 8080;
app.listen(port, () => {
  console.log(`helloworld: listening on port ${port}`);
});

// Cleanup on shutdown
process.on('SIGTERM', async () => {
  await pool.end();
  await connector.close();
  process.exit(0);
});
