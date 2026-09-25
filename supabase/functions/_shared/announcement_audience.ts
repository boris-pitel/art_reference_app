export type AnnouncementAudience = {
  audience_kind: string;
  target_user_ids: string[];
  target_platforms: string[];
};

export function isAnnouncementVisible(
  audience: AnnouncementAudience | null,
  userId: string | null,
  platform: string,
  isAdmin = false,
): boolean {
  if (!audience) return false;
  if (isAdmin) return true;
  if (audience.audience_kind === 'all') return true;
  if (audience.audience_kind === 'users') {
    return userId !== null && audience.target_user_ids.includes(userId);
  }
  if (audience.audience_kind === 'platforms') {
    return audience.target_platforms.includes(platform);
  }
  return false;
}