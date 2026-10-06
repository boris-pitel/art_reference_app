import assert from 'node:assert/strict';
import test from 'node:test';

import { placeName } from './place_name.ts';

test('uses a broad location instead of the nearest street address', () => {
  assert.equal(
    placeName({
      address_line1: '350 5th Avenue',
      city: 'New York',
      state: 'New York',
      country: 'United States',
    }),
    'New York, United States',
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
