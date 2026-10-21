export function validateSend(body: Record<string, unknown>) {
  if (typeof body.requestId !== 'string' || !/^[0-9a-f-]{36}$/i.test(body.requestId)) {
    throw new Error('A valid request ID is required.');
  }
  if (typeof body.text !== 'string' || !body.text.trim() || body.text.length > 8000) {
    throw new Error('Enter a message of up to 8,000 characters.');
  }
  if (!Array.isArray(body.imageIds) || body.imageIds.length > 4 ||
      body.imageIds.some((id) => typeof id !== 'string')) {
    throw new Error('Select up to four reference images.');
  }
  return { requestId: body.requestId, text: body.text.trim(), imageIds: [...new Set(body.imageIds)] as string[] };
}

export function responseText(output: Array<Record<string, any>>): string {
  return output.filter((item) => item.type === 'message')
    .flatMap((item) => item.content ?? [])
    .filter((part) => part.type === 'output_text' || part.type === 'refusal')
    .map((part) => part.text ?? part.refusal ?? '').join('\n');
}
// Only call this with the user returned by auth.getUser(token), never with
// request data or user-editable profile metadata.
export function adminEmail(user: { email?: string; app_metadata?: Record<string, unknown> } | null): string | null {
  if (user?.app_metadata?.is_admin !== true || !user.email?.trim()) return null;
  return user.email.trim().toLowerCase();
}

