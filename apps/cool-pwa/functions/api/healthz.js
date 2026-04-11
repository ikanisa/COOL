import { json } from '../_shared/supabase.js';

export async function onRequestGet() {
  return json({
    success: true,
    live: true,
    service: 'cool-admin-pwa',
    status: 'ok',
    ts: new Date().toISOString(),
  });
}
