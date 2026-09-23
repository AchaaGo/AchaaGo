// Exercises the two pure, DOM-free helpers in googlePlaces.ts. Requires no
// npm dependencies — run directly with Node's built-in test runner:
//   cd apps/web && node --experimental-strip-types --test src/lib/googlePlaces.test.ts

import assert from 'node:assert/strict';
import {test} from 'node:test';
import {mapPrediction, shouldFallbackToDemo} from './googlePlaces.ts';

test('mapPrediction converts a Places prediction into {id,address}', () => {
  const result = mapPrediction({place_id: 'abc123', description: 'Сүхбаатарын талбай, Улаанбаатар'});
  assert.deepEqual(result, {id: 'abc123', address: 'Сүхбаатарын талбай, Улаанбаатар'});
});

test('shouldFallbackToDemo is false for OK', () => {
  assert.equal(shouldFallbackToDemo('OK'), false);
});

test('shouldFallbackToDemo is false for ZERO_RESULTS (a real search with no matches)', () => {
  assert.equal(shouldFallbackToDemo('ZERO_RESULTS'), false);
});

test('shouldFallbackToDemo is true for key/quota/availability problems', () => {
  for (const status of ['REQUEST_DENIED', 'INVALID_REQUEST', 'OVER_QUERY_LIMIT', 'UNKNOWN_ERROR', 'NOT_FOUND']) {
    assert.equal(shouldFallbackToDemo(status), true, `expected fallback for status ${status}`);
  }
});
