import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const sha256 = async (value: string) => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value)))).map(x => x.toString(16).padStart(2,'0')).join('');
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', {headers:cors});
  if (req.method !== 'POST') return Response.json({error:'Method not allowed'},{status:405,headers:cors});
  const url=Deno.env.get('SUPABASE_URL'); const key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if(!url||!key) return Response.json({error:'Server configuration missing'},{status:500,headers:cors});
  let b:Record<string,unknown>; try{b=await req.json();}catch{return Response.json({error:'Invalid JSON'},{status:400,headers:cors});}
  const id=String(b.orderId??'').trim(); const phone=String(b.phone??'').replace(/\s/g,''); const token=String(b.trackingCode??'').trim().toUpperCase();
  if(!id||phone.length<9||token.length!==24) return Response.json({error:'بيانات المتابعة غير صحيحة'},{status:400,headers:cors});
  const db=createClient(url,key,{auth:{autoRefreshToken:false,persistSession:false}});
  const {data,error}=await db.from('orders').select('id,customer_name,phone,address,items_description,products_total,delivery_fee,total_price,status,date,admin_message,payment_status,assigned_courier').eq('id',id).eq('phone',phone).maybeSingle();
  if(error||!data) return Response.json({error:'لم يتم العثور على الطلب'},{status:404,headers:cors});
  const {data:hashRow,error:hashError}=await db.from('orders').select('tracking_code_hash').eq('id',id).single();
  if(hashError||!hashRow?.tracking_code_hash||hashRow.tracking_code_hash!==await sha256(token)) return Response.json({error:'رمز المتابعة غير صحيح'},{status:403,headers:cors});
  return Response.json({order:data},{status:200,headers:cors});
});
