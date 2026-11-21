// Supabase Edge Function: JARVIS voice via ElevenLabs. The API key stays server-side.
// Secrets: ELEVENLABS_API_KEY, ELEVENLABS_VOICE_ID   (SUPABASE_URL / SUPABASE_ANON_KEY are provided automatically)
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const cors = {"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const J = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...cors, "Content-Type": "application/json" } });
const hits = new Map<string, number[]>();
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } });
    const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer /i, "");
    const { data: { user } } = await sb.auth.getUser(token);
    if (!user) return J({ error: "Sign in required" }, 401);
    const now = Date.now(), h = (hits.get(user.id) ?? []).filter((t) => now - t < 60000);
    if (h.length >= 15) return J({ error: "Too many requests" }, 429);
    hits.set(user.id, [...h, now]);
    const { text } = await req.json();
    if (typeof text !== "string" || !text.trim() || text.length > 300) return J({ error: "Invalid text" }, 400);
    const voice = Deno.env.get("ELEVENLABS_VOICE_ID"), key = Deno.env.get("ELEVENLABS_API_KEY");
    if (!voice || !key) return J({ error: "Voice not configured" }, 500);
    const r = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voice}?output_format=mp3_44100_64`, {
      method: "POST", headers: { "xi-api-key": key, "Content-Type": "application/json" },
      body: JSON.stringify({ text, model_id: "eleven_turbo_v2_5", voice_settings: { stability: 0.5, similarity_boost: 0.8 } }),
    });
    if (!r.ok) return J({ error: "Voice service error", detail: `${r.status} ${(await r.text()).slice(0, 160)}` }, 502);
    return new Response(r.body, { headers: { ...cors, "Content-Type": "audio/mpeg" } });
  } catch (_) { return J({ error: "Server error" }, 500); }
});
