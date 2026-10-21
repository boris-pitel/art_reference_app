import test from 'node:test';
import assert from 'node:assert/strict';
import { adminEmail, validateSend, responseText } from './protocol.ts';

test('admin access requires a verified server metadata boolean and email', () => {
  assert.equal(adminEmail(null), null);
  assert.equal(adminEmail({ email: 'user@example.test', user_metadata: { is_admin: true } }), null);
  assert.equal(adminEmail({ email: 'user@example.test', app_metadata: { is_admin: 'true' } }), null);
  assert.equal(adminEmail({ app_metadata: { is_admin: true } }), null);
  assert.equal(adminEmail({ email: ' Admin@Example.Test ', app_metadata: { is_admin: true } }), 'admin@example.test');
});

const send = { requestId: 'acb8570b-eebc-43e5-ae0b-a1a14c80c9bc', text: 'Compare these', imageIds: ['a', 'b'] };
test('keeps selected image order and removes duplicate selections', () => {
  assert.deepEqual(validateSend({ ...send, imageIds: ['b', 'a', 'b'] }).imageIds, ['b', 'a']);
});
test('rejects malformed requests before a paid model call', () => {
  for (const change of [{ text: '' }, { text: ' '.repeat(5) }, { text: 'x'.repeat(8001) },
    { requestId: 'wrong' }, { imageIds: 'a' }, { imageIds: [42] }, { imageIds: ['a', 'b', 'c', 'd', 'e'] }]) {
    assert.throws(() => validateSend({ ...send, ...change }));
  }
});
test('text-only follow-ups need not resend the original image', () => {
  assert.deepEqual(validateSend({ ...send, imageIds: [] }).imageIds, []);
});
test('collects assistant text and refusals, never image base64 or reasoning', () => {
  assert.equal(responseText([
    { type: 'reasoning', content: [{ type: 'output_text', text: 'private' }] },
    { type: 'image_generation_call', result: 'base64' },
    { type: 'message', content: [{ type: 'output_text', text: 'A composition study' }, { type: 'refusal', refusal: 'Cannot comply' }] },
  ]), 'A composition study\nCannot comply');
});
