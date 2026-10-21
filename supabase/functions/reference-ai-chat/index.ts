import { Pool } from 'jsr:@db/postgres@^0.19.3';
import { createClient } from 'npm:@supabase/supabase-js@2';
import { v5 } from 'npm:uuid@11';
import { adminEmail, responseText, validateSend } from './protocol.ts';

const cors = { 'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, x-client-info, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const reply = (data: unknown, status = 200) => new Response(JSON.stringify(data), {
  status, headers: { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
});
const pool = new Pool(Deno.env.get('SUPABASE_DB_URL')!, 3, true);

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (request.method !== 'POST') return reply({ error: 'POST required.' }, 405);
  const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const token = (request.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '');
  const { data: auth, error: authError } = await supabase.auth.getUser(token);
  if (authError || !auth.user) return reply({ error: 'Sign in required.' }, 401);
  const email = adminEmail(auth.user);
  if (!email) {
    return reply({ error: 'Administrator access required.' }, 403);
  }
  const owner = v5(`art-reference-user:${email}`, v5.URL);
  let body: Record<string, any>;
  try { body = await request.json(); } catch { return reply({ error: 'Invalid request.' }, 400); }
  const referenceId = body.referenceId;
  if (typeof referenceId !== 'string' || !/^[0-9a-f-]{36}$/i.test(referenceId)) {
    return reply({ error: 'Invalid reference.' }, 400);
  }
  const connection = await pool.connect();
  try {
    await connection.queryArray`begin`;
    // Serializes sends and saves across devices. Never queue duplicate paid calls.
    const lock = await connection.queryObject<{ locked: boolean }>`
      select pg_try_advisory_xact_lock(hashtextextended(${referenceId}, 0)) as locked`;
    if (!lock.rows[0].locked) {
      await connection.queryArray`rollback`;
      return reply({ error: 'This chat is responding on another screen. Try again shortly.' }, 409);
    }
    const owned = await connection.queryObject`select id from public.image_assets
      where id = ${referenceId} and user_id = ${owner}`;
    if (!owned.rows.length) { await connection.queryArray`rollback`; return reply({ error: 'Reference not found.' }, 404); }
    await connection.queryArray`insert into public.reference_ai_chats(reference_id, user_id)
      values (${referenceId}, ${owner}) on conflict do nothing`;
    const state = await connection.queryObject<{ turns: any[]; response_id: string | null }>`
      select turns, response_id from public.reference_ai_chats where reference_id = ${referenceId} and user_id = ${owner}`;
    const chat = state.rows[0];
    const sign = async (path: string) => {
      const { data, error } = await supabase.storage.from('reference-images').createSignedUrl(path, 3600);
      if (error || !data) throw new Error('Unable to open chat image.');
      return data.signedUrl;
    };
    const present = async () => {
      const turns = await Promise.all(chat.turns.map(async (turn) => ({ ...turn,
        images: await Promise.all((turn.images ?? []).map(async (image: any) => ({ ...image, url: await sign(image.path) }))),
        generated: await Promise.all((turn.generated ?? []).map(async (image: any) => ({ ...image, url: await sign(image.path) }))),
      })));
      const available = await connection.queryObject<{ id: string; storage_path: string }>`
        select a.id, a.storage_path from public.image_assets a where a.user_id = ${owner}
        and (a.id = ${referenceId} or exists(select 1 from public.image_relationships r
          where r.parent_image_id = ${referenceId} and r.child_image_id = a.id)) order by a.date_added`;
      return { turns, images: await Promise.all(available.rows.map(async (image) => ({
        id: image.id, url: await sign(image.storage_path), label: image.id === referenceId ? 'Original reference' : 'Attachment',
      }))) };
    };
    if (body.action === 'send') {
      let send;
      try { send = validateSend(body); } catch (error) {
        await connection.queryArray`rollback`; return reply({ error: String(error) }, 400);
      }
      if (!chat.turns.some((turn) => turn.id === send.requestId)) {
        const key = Deno.env.get('OPENAI_API_KEY');
        if (!key) throw new Error('Reference chat is not configured.');
        const images: any[] = [];
        for (const id of send.imageIds) {
          const record = await connection.queryObject<{ storage_path: string }>`
            select coalesce(a.display_storage_path, a.storage_path) as storage_path
            from public.image_assets a where a.id = ${id} and a.user_id = ${owner}
            and (a.id = ${referenceId} or exists(select 1 from public.image_relationships r
              where r.parent_image_id = ${referenceId} and r.child_image_id = a.id))`;
          if (!record.rows[0]) throw new Error('Selected image does not belong to this reference.');
          // Keep a private chat snapshot: deleting an attachment later must
          // not break the image embedded in the saved conversation.
          const snapshot = `${owner}/reference-chat/${referenceId}/${send.requestId}-input-${id}`;
          const { error: copyError } = await supabase.storage.from('reference-images')
            .copy(record.rows[0].storage_path, snapshot);
          if (copyError && !/already exists|duplicate/i.test(copyError.message)) {
            throw new Error('Unable to attach this image to the conversation.');
          }
          images.push({ id, path: snapshot });
        }
        // Rebuild context from our durable history rather than relying on an
        // expiring provider-side conversation or old signed image URLs.
        const input: any[] = [];
        for (const turn of chat.turns) {
          input.push({ role: 'user', content: [
            { type: 'input_text', text: turn.text },
            ...await Promise.all((turn.images ?? []).map(async (image: any) => ({
              type: 'input_image', image_url: await sign(image.path), detail: 'auto',
            }))),
          ] });
          if (turn.answer) input.push({ role: 'assistant', content: turn.answer });
          if (turn.generated?.length) input.push({ role: 'user', content: [
            { type: 'input_text', text: 'Conversation context: the following images were generated by the assistant in the preceding turn.' },
            ...await Promise.all(turn.generated.map(async (image: any) => ({
              type: 'input_image', image_url: await sign(image.path), detail: 'auto',
            }))),
          ] });
        }
        input.push({ role: 'user', content: [
          { type: 'input_text', text: send.text },
          ...await Promise.all(images.map(async (image) => ({ type: 'input_image', image_url: await sign(image.path), detail: 'auto' }))),
        ] });
        const result = await fetch('https://api.openai.com/v1/responses', {
          method: 'POST', headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
          signal: AbortSignal.timeout(150000),
          body: JSON.stringify({ model: Deno.env.get('REFERENCE_CHAT_MODEL') ?? 'gpt-5',
            instructions: 'You are an art assistant inside Painter Reference. Discuss the reference and selected attachments. Clearly distinguish observations from suggestions. Generate or edit an image only when the user requests it. Never claim an image was saved as a reference attachment; the user controls Save to reference.',
            store: false, input,
            tools: [{ type: 'image_generation', model: 'gpt-image-2', quality: 'medium', output_format: 'png' }], max_output_tokens: 4000,
          }),
        });
        if (!result.ok) {
          console.error('Reference chat provider status', result.status);
          throw new Error('The AI service could not complete this message. Please try again.');
        }
        const response = await result.json();
        if (response.status !== 'completed') throw new Error('The AI response was incomplete. Please try again.');
        const generated: any[] = [];
        for (const item of response.output ?? []) {
          if (item.type !== 'image_generation_call' || !item.result) continue;
          const bytes = Uint8Array.from(atob(item.result), (char) => char.charCodeAt(0));
          const path = `${owner}/reference-chat/${referenceId}/${send.requestId}-${generated.length}.png`;
          const { error } = await supabase.storage.from('reference-images').upload(path, bytes, { contentType: 'image/png', upsert: true });
          if (error) throw new Error('Unable to store the generated image.');
          generated.push({ id: `${send.requestId}-${generated.length}`, path });
        }
        chat.turns.push({ id: send.requestId, text: send.text, images,
          answer: responseText(response.output ?? []), generated, createdAt: new Date().toISOString() });
        chat.response_id = response.id;
      }
    } else if (body.action === 'markSaved') {
      const image = chat.turns.flatMap((turn) => turn.generated ?? []).find((image) => image.id === body.generatedId);
      if (!image) throw new Error('Generated image not found.');
      const linked = await connection.queryObject`select r.child_image_id from public.image_relationships r
        join public.image_assets a on a.id = r.child_image_id
        where r.parent_image_id = ${referenceId} and r.child_image_id = ${body.savedImageId} and a.user_id = ${owner}`;
      if (!linked.rows.length) throw new Error('Saved attachment not found.');
      image.savedImageId = body.savedImageId;
    } else if (body.action !== 'load') {
      throw new Error('Unknown chat action.');
    }
    await connection.queryArray`update public.reference_ai_chats set turns = ${JSON.stringify(chat.turns)}::jsonb,
      response_id = ${chat.response_id}, updated_at = now() where reference_id = ${referenceId}`;
    await connection.queryArray`commit`;
    return reply(await present());
  } catch (error) {
    try { await connection.queryArray`rollback`; } catch { /* connection may already be closed */ }
    console.error('Reference chat failed', error instanceof Error ? error.message : 'Unknown error');
    return reply({ error: error instanceof Error ? error.message : 'Unable to load reference chat.' }, 500);
  } finally { connection.release(); }
});
