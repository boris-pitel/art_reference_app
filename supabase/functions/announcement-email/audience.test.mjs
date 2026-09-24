import assert from 'node:assert/strict';
import test from 'node:test';
import { selectAudience } from './audience.ts';

test('includes confirmed account users by default, excludes explicit opt-outs', () => {
  const users = [
    { id: 'a', email: 'a@example.com' },
    { id: 'b', email: 'b@example.com' },
  ];
  const audience = selectAudience(users, [{ user_id: 'b', updates_enabled: false }], []);
  assert.deepEqual(audience.eligible.map((user) => user.id), ['a']);
  assert.deepEqual(audience.pending.map((user) => user.id), ['a']);
});

test('never retries accepted or in-progress delivery; retries failures last', () => {
  const users = ['a', 'b', 'c', 'd'].map((id) => ({ id, email: `${id}@example.com` }));
  const deliveries = [
    { user_id: 'a', status: 'sent' },
    { user_id: 'b', status: 'sending' },
    { user_id: 'c', status: 'failed' },
  ];
  const audience = selectAudience(users, [], deliveries);
  assert.deepEqual(audience.pending.map((user) => user.id), ['d', 'c']);
});
