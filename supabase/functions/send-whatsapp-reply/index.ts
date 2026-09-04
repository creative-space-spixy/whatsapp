// Sends an outbound WhatsApp message via the Meta Cloud API and records it
// in host_conversations. Runs server-side so the Meta access token never
// reaches the Flutter web client.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...corsHeaders },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const { sender, message, rowId, threadId } = await req.json();

    if (!sender || typeof sender !== 'string' || !message || typeof message !== 'string') {
      return json({ error: 'sender and message are required' }, 400);
    }

    const PHONE_NUMBER_ID = Deno.env.get('WHATSAPP_PHONE_NUMBER_ID');
    const META_TOKEN = Deno.env.get('WHATSAPP_META_TOKEN');
    if (!PHONE_NUMBER_ID || !META_TOKEN) {
      return json({ error: 'WhatsApp credentials are not configured' }, 500);
    }

    const waRes = await fetch(`https://graph.facebook.com/v18.0/${PHONE_NUMBER_ID}/messages`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${META_TOKEN}`,
      },
      body: JSON.stringify({
        messaging_product: 'whatsapp',
        to: sender,
        type: 'text',
        text: { body: message },
      }),
    });

    const waJson = await waRes.json().catch(() => ({}));
    if (!waRes.ok) {
      console.error('WhatsApp API error:', waRes.status, waJson);
      return json({ error: 'WhatsApp send failed', detail: waJson }, 502);
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // Fill in the response on the specific unanswered row (matched by id,
    // i.e. the row the incoming message_id belongs to) if one was given.
    let recordedRow: Record<string, unknown> | null = null;
    if (rowId) {
      const { data, error } = await supabase
        .from('host_conversations')
        .update({ response: message })
        .eq('id', rowId)
        .is('response', null)
        .select()
        .maybeSingle();
      if (error) return json({ error: error.message }, 500);
      recordedRow = data;
    }

    // No target row (fresh outbound message, or the target got answered by
    // someone else in the meantime) -- log it as its own row instead.
    if (!recordedRow) {
      const { data, error } = await supabase
        .from('host_conversations')
        .insert({
          sender,
          message: null,
          response: message,
          thread_id: threadId ?? null,
        })
        .select()
        .single();
      if (error) return json({ error: error.message }, 500);
      recordedRow = data;
    }

    // The client applies `row` immediately instead of waiting on a Realtime
    // event, since this write happens with the service-role key and the
    // caller has no other way to know it landed.
    return json({
      success: true,
      whatsappMessageId: waJson.messages?.[0]?.id ?? null,
      row: recordedRow,
    });
  } catch (e) {
    console.error('send-whatsapp-reply error:', e);
    return json({ error: String(e) }, 500);
  }
});
