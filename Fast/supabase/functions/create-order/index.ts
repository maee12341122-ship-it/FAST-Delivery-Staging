import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const sha256 = async (value: string) => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value)))).map(x => x.toString(16).padStart(2,'0')).join('');
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return Response.json({ error: 'Method not allowed' }, { status: 405, headers: cors });
  const url = Deno.env.get('SUPABASE_URL'); const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) return Response.json({ error: 'Server configuration missing' }, { status: 500, headers: cors });
  let b: Record<string, unknown>; try { b = await req.json(); } catch { return Response.json({error:'Invalid JSON'}, {status:400,headers:cors}); }
  const name = String(b.customerName ?? '').trim(); const phone = String(b.phone ?? '').replace(/\s/g,'');
  const address = String(b.address ?? '').trim(); const description = String(b.itemsDesc ?? '').trim();
  const subtotal = Number(b.productsTotal);
  if (name.length < 2 || phone.length < 9 || phone.length > 16 || address.length < 4 || description.length < 2 || !Number.isFinite(subtotal) || subtotal < 0 || subtotal > 100000000) {
    return Response.json({error:'بيانات الطلب غير مكتملة أو غير صحيحة'}, {status:400,headers:cors});
  }
  const db = createClient(url, key, {auth:{autoRefreshToken:false,persistSession:false}});
  const since = new Date(Date.now()-60*60*1000).toISOString();
  const {count, error: countError} = await db.from('order_request_limits').select('id',{count:'exact',head:true}).eq('phone',phone).gte('created_at',since);
  if (countError) return Response.json({error:'تعذر التحقق من حد الطلبات'}, {status:500,headers:cors});
  if ((count ?? 0) >= 3) return Response.json({error:'وصلت إلى الحد المؤقت للطلبات. حاول بعد ساعة.'}, {status:429,headers:cors});
  const token = Array.from(crypto.getRandomValues(new Uint8Array(12))).map(x=>x.toString(16).padStart(2,'0')).join('').toUpperCase();
  const {error: limitError} = await db.from('order_request_limits').insert({phone});
  if (limitError) return Response.json({error:'تعذر تسجيل الطلب'}, {status:500,headers:cors});
  const order = {
    customer_name:name, phone, address, items_description:description,
    products_total:Math.round(subtotal), delivery_fee:0, total_price:Math.round(subtotal),
    payment_method:'cash_on_delivery', payment_status:'unpaid', payment_account:'',
    assigned_courier:'لم يتم التعيين', status:'waitingForPricing', is_fee_sent:false,
    admin_message:'طلب جديد؛ السعر المرسل تقديري ويحتاج مراجعة المشرف وتأكيده',
    date:new Date().toISOString().slice(0,10), notes:'', tracking_code_hash:await sha256(token),
  };
  const {data,error} = await db.from('orders').insert(order).select().single();
  if (error) return Response.json({error:error.message}, {status:400,headers:cors});
  const { tracking_code_hash: _hash, ...safeOrder } = data;
  return Response.json({order:safeOrder, trackingCode:token, message:'تم استلام الطلب وهو بانتظار مراجعة المشرف'}, {status:201,headers:cors});
});
