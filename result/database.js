'use strict';

const fs = require('fs');

function loadDatabaseConfig(env = process.env) {
  if (!env.DB_SECRET_FILE) {
    throw new Error('DB_SECRET_FILE is required');
  }
  if (!env.DB_METADATA_FILE) {
    throw new Error('DB_METADATA_FILE is required');
  }

  const secret = JSON.parse(fs.readFileSync(env.DB_SECRET_FILE, 'utf8'));
  const metadata = JSON.parse(fs.readFileSync(env.DB_METADATA_FILE, 'utf8'));
  for (const field of ['username', 'password']) {
    if (!secret[field]) {
      throw new Error(`The RDS secret is missing ${field}`);
    }
  }
  if (!metadata.host) {
    throw new Error('The RDS metadata is missing host');
  }

  return {
    host: metadata.host,
    port: metadata.port || 5432,
    database: env.DB_NAME || 'voting',
    user: secret.username,
    password: secret.password,
    ssl: {
      rejectUnauthorized: false
    }
  };
}

module.exports = loadDatabaseConfig;
