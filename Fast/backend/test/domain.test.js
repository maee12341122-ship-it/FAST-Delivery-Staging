import test from 'node:test';
import assert from 'node:assert/strict';
import { calculateDeliveryFee, canTransition, haversineKm } from '../src/domain.js';

test('distance is zero for equal coordinates', () => {
  assert.equal(haversineKm(13.5795, 44.0209, 13.5795, 44.0209), 0);
});

test('distance rejects invalid coordinates', () => {
  assert.equal(haversineKm(120, 44, 13, 44), null);
});

test('delivery fee rounds distance upward and applies configured rate', () => {
  assert.equal(calculateDeliveryFee(1.1, 500, 100), 700);
  assert.equal(calculateDeliveryFee(null, 500, 100), 500);
});

test('order flow prevents skipping dispatch and delivery before collection', () => {
  assert.equal(canTransition('ready', 'assigned'), true);
  assert.equal(canTransition('ready', 'delivered'), false);
  assert.equal(canTransition('on_the_way', 'delivered'), true); // API additionally requires cash collection.
  assert.equal(canTransition('delivered', 'pending'), false);
});
