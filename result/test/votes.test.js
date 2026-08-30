'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const collectVotesFromResult = require('../votes');

test('returns zero counts when the query has no rows', function () {
  assert.deepEqual(collectVotesFromResult({rows: []}), {a: 0, b: 0});
});

test('converts PostgreSQL count strings to numbers', function () {
  const result = {
    rows: [
      {vote: 'a', count: '4'},
      {vote: 'b', count: '7'}
    ]
  };

  assert.deepEqual(collectVotesFromResult(result), {a: 4, b: 7});
});
