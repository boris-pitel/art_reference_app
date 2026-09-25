import assert from 'node:assert/strict';
import test from 'node:test';
import { isAnnouncementVisible } from './announcement_audience.ts';

const all = { audience_kind: 'all', target_user_ids: [], target_platforms: [] };
const users = { audience_kind: 'users', target_user_ids: ['selected'], target_platforms: [] };
const platforms = { audience_kind: 'platforms', target_user_ids: [], target_platforms: ['ios'] };

test('all-users notice is visible everywhere', () => {
  assert.equal(isAnnouncementVisible(all, null, 'web'), true);
});

test('specific-user notice requires that signed-in account', () => {
  assert.equal(isAnnouncementVisible(users, 'selected', 'android'), true);
  assert.equal(isAnnouncementVisible(users, 'other', 'android'), false);
  assert.equal(isAnnouncementVisible(users, null, 'android'), false);
});

test('platform notice appears only on selected platform', () => {
  assert.equal(isAnnouncementVisible(platforms, null, 'ios'), true);
  assert.equal(isAnnouncementVisible(platforms, null, 'web'), false);
});

test('admin can manage any notice and absent audience fails closed', () => {
  assert.equal(isAnnouncementVisible(users, 'admin', 'web', true), true);
  assert.equal(isAnnouncementVisible(null, 'admin', 'web', true), false);
  assert.equal(isAnnouncementVisible({ audience_kind: 'other', target_user_ids: [], target_platforms: [] }, null, 'web'), false);
});