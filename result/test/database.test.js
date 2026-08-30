'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const loadDatabaseConfig = require('../database');

test('loads the RDS-managed secret into pg configuration', function () {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'result-db-'));
  const secretFile = path.join(directory, 'secret.json');
  const metadataFile = path.join(directory, 'metadata.json');

  try {
    fs.writeFileSync(secretFile, JSON.stringify({
      username: 'voteapp',
      password: 'secret-value'
    }));
    fs.writeFileSync(metadataFile, JSON.stringify({
      host: 'database.example',
      port: 5432
    }));

    assert.deepEqual(loadDatabaseConfig({
      DB_SECRET_FILE: secretFile,
      DB_METADATA_FILE: metadataFile,
      DB_NAME: 'voting'
    }), {
      host: 'database.example',
      port: 5432,
      database: 'voting',
      user: 'voteapp',
      password: 'secret-value',
      ssl: {
        rejectUnauthorized: false
      }
    });
  } finally {
    fs.rmSync(directory, {recursive: true, force: true});
  }
});
