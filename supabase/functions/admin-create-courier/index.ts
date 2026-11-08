import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return Response.json({ error: 'Method not allowed' }, { status: 405, headers: cors });

  const url = Deno.env.get('SUPABASE_URL');
  const anon = Deno.env.get('SUPABASE_ANON_KEY');
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anon || !service) return Response.json({ error: 'Server is not configured' }, { status: 500, headers: cors });

  const authHeader = req.headers.get('Authorization') ?? '';
  const caller = createClient(url, anon, { global: { headers: { Authorization: authHeader } } });
  const { data: { user }, error: authError } = await caller.auth.getUser();
  if (authError || !user || user.app_metadata?.role !== 'admin') {
    return Response.json({ error: 'Admin authorization required' }, { status: 403, headers: cors });
  }

  let body: { name?: string; phone?: string; username?: string; password?: string };
  try { body = await req.json(); } catch { return Response.json({ error: 'Invalid JSON' }, { status: 400, headers: cors }); }
  const name = (body.name ?? '').trim();
  const phone = (body.phone ?? '').trim();
  const username = (body.username ?? '').trim().toLowerCase();
  const password = body.password ?? '';
  if (!name || !phone || !/^[a-z0-9_.-]{3,32}$/.test(username) || password.length < 10) {
    return Response.json({ error: 'Name, phone, valid username and password (10+ chars) are required' }, { status: 400, headers: cors });
  }

  const admin = createClient(url, service, { auth: { autoRefreshToken: false, persistSession: false } });
  const email = `${username}@courier.fast.local`;
  const { data: created, error: createError } = await admin.auth.admin.createUser({
    email, password, email_confirm: true,
    app_metadata: { role: 'courier' },
    user_metadata: { name, phone, username },
  });
  if (createError || !created.user) return Response.json({ error: createError?.message ?? 'Could not create courier auth user' }, { status: 400, headers: cors });

  const courierId = crypto.randomUUID();
  const { error: insertError } = await admin.from('couriers').insert({
    id: courierId, auth_user_id: created.user.id, delivery_man_id: courierId,
    username, name, phone, status: 'available', is_logged_in: false, completed_orders: 0,
  });
  if (insertError) {
    await admin.auth.admin.deleteUser(created.user.id);
    return Response.json({ error: insertError.message }, { status: 400, headers: cors });
  }
  return Response.json({ id: courierId, username }, { status: 201, headers: cors });
});
