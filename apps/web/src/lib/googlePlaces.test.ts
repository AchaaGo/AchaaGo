// Exercises the two pure, DOM-free helpers in googlePlaces.ts. Requires no
// npm dependencies — run directly with Node's built-in test runner:
//   cd apps/web && node --experimental-strip-types --test src/lib/googlePlaces.test.ts

import assert from 'node:assert/strict';
import {test} from 'node:test';
import {createStaleGuard, cycleHighlight, mapPrediction, shouldFallbackToDemo} from './googlePlaces.ts';

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

test('createStaleGuard: a later start() invalidates an earlier in-flight token', () => {
  const guard = createStaleGuard();
  const first = guard.start();
  assert.equal(guard.isCurrent(first), true, 'the only token so far should be current');
  const second = guard.start();
  assert.equal(guard.isCurrent(first), false, 'typing again should invalidate the older request');
  assert.equal(guard.isCurrent(second), true);
});

test('createStaleGuard: resolving in order keeps every token current until superseded', () => {
  const guard = createStaleGuard();
  const a = guard.start();
  assert.equal(guard.isCurrent(a), true);
  const b = guard.start();
  const c = guard.start();
  assert.equal(guard.isCurrent(a), false);
  assert.equal(guard.isCurrent(b), false);
  assert.equal(guard.isCurrent(c), true);
});

test('cycleHighlight: an empty list always has nothing highlighted', () => {
  assert.equal(cycleHighlight(-1, 0, 1), -1);
  assert.equal(cycleHighlight(-1, 0, -1), -1);
});

test('cycleHighlight: ArrowDown from none highlighted starts at the first item', () => {
  assert.equal(cycleHighlight(-1, 3, 1), 0);
});

test('cycleHighlight: ArrowUp from none highlighted starts at the last item', () => {
  assert.equal(cycleHighlight(-1, 3, -1), 2);
});

test('cycleHighlight: ArrowDown wraps from the last item back to the first', () => {
  assert.equal(cycleHighlight(2, 3, 1), 0);
});

test('cycleHighlight: ArrowUp wraps from the first item back to the last', () => {
  assert.equal(cycleHighlight(0, 3, -1), 2);
});

test('cycleHighlight: normal moves within bounds just step by one', () => {
  assert.equal(cycleHighlight(1, 5, 1), 2);
  assert.equal(cycleHighlight(1, 5, -1), 0);
});
