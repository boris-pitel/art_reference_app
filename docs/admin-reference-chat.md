# Admin reference chat

One ongoing database conversation belongs to each reference. The Chat button
on Image Details opens it; Discuss in chat on an attachment opens its parent's
same conversation and selects the attachment. The image button selects up to
four of the original reference and existing attachments. Selection thumbnails
appear above the composer and alongside the submitted message.

Messages and generated PNG images are persisted server-side. Original inputs
are copied to private chat snapshots so deleting a library attachment does not
break older messages. Context is rebuilt from saved turns with fresh image URLs;
it does not rely on an expiring OpenAI response chain. Generated images use
Save to reference to enter the existing attachment upload/deduplication flow.
Saved attachment IDs are remembered in the chat to disable duplicate saves.

The client hides chat unless auth app_metadata.is_admin is the boolean true.
The edge function independently validates the bearer token with auth.getUser,
checks the same server-controlled flag, derives the established library owner
UUID from the verified email, and verifies reference and attachment ownership.
The chat table has RLS enabled and no client access grants. The OpenAI key stays
in Supabase secrets; no key is included in the Flutter app.

Account/reference-scoped device drafts preserve unsent text and selected images.
Requests have stable retry IDs. A database advisory transaction lock serializes
changes across devices; an already committed request is returned without another
model call. Failed requests retain their drafts. Reopening after a lost reply
reconciles the draft with server history. Signing out hides the conversation.

## Backend setup

Apply `20261021000000_reference_ai_chat.sql` and deploy `reference-ai-chat`.
Existing secret `OPENAI_API_KEY` is reused. Optional `REFERENCE_CHAT_MODEL`
defaults to `gpt-5`; it must support vision and the Responses image generation
tool. The image tool uses `gpt-image-2`, matching the existing AI editor.
Responses are requested with `store: false`; the application database is the
durable history. The request includes all saved turns; very long histories can
eventually reach the model context limit. No silent message deletion or reset
is performed.

Source: [OpenAI image generation documentation](https://developers.openai.com/api/docs/guides/image-generation).

## Verification

- `flutter test --no-pub test/reference_chat_test.dart`
- `node --experimental-strip-types --test supabase/functions/reference-ai-chat/protocol.test.mjs`
- `npx deno check supabase/functions/reference-ai-chat/index.ts`
- Flutter analysis of the new screen, service, tests and Image Details.

Live image understanding/generation needs a signed-in admin and a configured
OpenAI project. Fixture tests do not verify provider billing, model access, or
device image rendering. No automatic mobile distribution is part of this change.
