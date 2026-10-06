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
    '350 5th Avenue, New York, USA',
  );
});

test('falls back to county and omits repeated components', () => {
  assert.equal(
    placeName({ county: 'Coconino County', state: 'Arizona', country: 'United States' }),
    'Coconino County, Arizona, USA',
  );
  assert.equal(placeName({ state: 'Berlin', country: 'Germany' }), 'Berlin, Germany');
  assert.equal(placeName({}), null);
});


test('preserves locally formatted street addresses', () => {
  assert.equal(placeName({street: 'Hauptstraße', housenumber: '12',
    formatted: 'Hauptstraße 12, 10115 Berlin, Germany', city: 'Berlin', postcode: '10115', country: 'Germany'}),
    'Hauptstraße 12, Berlin, 10115, Germany');
});

test('falls back to street components without a formatted address', () => {
  assert.equal(placeName({street: '5th Avenue', housenumber: '350',
    city: 'New York', country: 'United States'}),
    '350 5th Avenue, New York, USA');
  assert.equal(placeName({street: '5th Avenue', city: 'New York'}),
    '5th Avenue, New York');
});

test('ignores missing fields and bounds address length', () => {
  assert.equal(placeName({address_line1: ' ', city: ' Paris ', state: null,
    country: 'France'}), 'Paris, France');
  assert.equal(placeName({street: 'x'.repeat(250)}).length, 200);
});


test('shortens US country and state without abbreviating the city or street', () => {
  assert.equal(placeName({street: 'New York Avenue', housenumber: '10',
    formatted: '10 New York Avenue, New York, New York, United States of America',
    city: 'New York', state: 'New York', state_code: 'NY',
    country: 'United States of America', country_code: 'us'}),
    '10 New York Avenue, New York, NY, USA');
  assert.equal(placeName({city: 'Los Angeles', state: 'California',
    state_code: 'US-CA', country_code: 'us'}), 'Los Angeles, CA, USA');
});

test('uses familiar country abbreviations and preserves other country names', () => {
  assert.equal(placeName({city: 'London', country_code: 'gb', country: 'United Kingdom'}), 'London, UK');
  assert.equal(placeName({city: 'Dubai', country_code: 'ae', country: 'United Arab Emirates'}), 'Dubai, UAE');
  assert.equal(placeName({city: 'Lisbon', country_code: 'pt', country: 'Portugal'}), 'Lisbon, Portugal');
});
