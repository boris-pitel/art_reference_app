import assert from 'node:assert/strict';
import test from 'node:test';

import { placeName } from './place_name.ts';

test('includes the address alongside the locality', () => {
  assert.equal(
    placeName({
      address_line1: '350 5th Avenue',
      city: 'New York',
      state: 'New York',
      country: 'United States',
    }),
    '350 5th Avenue, New York, United States',
  );
});

test('falls back to county and omits repeated components', () => {
  assert.equal(
    placeName({ county: 'Coconino County', state: 'Arizona', country: 'United States' }),
    'Coconino County, Arizona, United States',
  );
  assert.equal(placeName({ state: 'Berlin', country: 'Germany' }), 'Berlin, Germany');
  assert.equal(placeName({}), null);
});


test('preserves locally formatted street addresses', () => {
  assert.equal(placeName({street: 'Hauptstraße', housenumber: '12',
    formatted: 'Hauptstraße 12, 10115 Berlin, Germany'}),
    'Hauptstraße 12, 10115 Berlin, Germany');
});

test('falls back to street components without a formatted address', () => {
  assert.equal(placeName({street: '5th Avenue', housenumber: '350',
    city: 'New York', country: 'United States'}),
    '350 5th Avenue, New York, United States');
  assert.equal(placeName({street: '5th Avenue', city: 'New York'}),
    '5th Avenue, New York');
});

test('ignores missing fields and bounds address length', () => {
  assert.equal(placeName({address_line1: ' ', city: ' Paris ', state: null,
    country: 'France'}), 'Paris, France');
  assert.equal(placeName({street: 'Main', formatted: 'x'.repeat(250)}).length, 200);
});
