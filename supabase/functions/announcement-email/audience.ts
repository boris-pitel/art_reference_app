export type AudienceUser = { id: string; email: string };
export type Preference = { user_id: string; updates_enabled: boolean };
export type Delivery = { user_id: string; status: string };

export function selectAudience(
  users: AudienceUser[],
  preferences: Preference[],
  deliveries: Delivery[],
) {
  const optedOut = new Set(preferences.filter((row) => row.updates_enabled === false)
    .map((row) => row.user_id));
  const eligible = users.filter((user) => !optedOut.has(user.id));
  const alreadySent = new Set(deliveries.filter((row) => row.status === 'sent')
    .map((row) => row.user_id));
  const inProgress = new Set(deliveries.filter((row) => row.status === 'sending')
    .map((row) => row.user_id));
  const failedIds = new Set(deliveries.filter((row) => row.status === 'failed')
    .map((row) => row.user_id));
  const pending = eligible.filter((user) => !alreadySent.has(user.id) && !inProgress.has(user.id))
    .sort((a, b) => Number(failedIds.has(a.id)) - Number(failedIds.has(b.id)));
  return { eligible, alreadySent, pending };
}
