import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const cors={ 'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS' };
const sha256=async(v:string)=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(v)))).map(x=>x.toString(16).padStart(2,'0')).join('');
Deno.serve(async(req)=>{
 if(req.method==='OPTIONS') return new Response('ok',{headers:cors});
 if(req.method!=='POST') return Response.json({error:'Method not allowed'},{status:405,headers:cors});
 const url=Deno.env.get('SUPABASE_URL'); const key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
 if(!url||!key) return Response.json({error:'Server configuration missing'},{status:500,headers:cors});
 let b:Record<string,unknown>;try{b=await req.json();}catch{return Response.json({error:'Invalid JSON'},{status:400,headers:cors});}
 const id=String(b.orderId??'');const phone=String(b.phone??'').replace(/\s/g,'');const token=String(b.trackingCode??'').toUpperCase();const action=String(b.action??'');
 if(!id||phone.length<9||token.length!==24||!['approve','cancel'].includes(action))return Response.json({error:'Invalid request'},{status:400,headers:cors});
 const db=createClient(url,key,{auth:{autoRefreshToken:false,persistSession:false}});
 const {data:o,error}=await db.from('orders').select('id,phone,status,tracking_code_hash').eq('id',id).eq('phone',phone).maybeSingle();
 if(error||!o||o.tracking_code_hash!==await sha256(token))return Response.json({error:'Order verification failed'},{status:403,headers:cors});
 if(action==='approve'&&o.status!=='pricingSentToCustomer')return Response.json({error:'Order is not awaiting price approval'},{status:409,headers:cors});
 if(action==='cancel'&&['delivered','cancelled','cancelledByCustomer'].includes(o.status))return Response.json({error:'Order can no longer be cancelled'},{status:409,headers:cors});
 const update=action==='approve'?{status:'waitingCourierApproval',admin_message:'وافق العميل على السعر المحدد'}:{status:'cancelledByCustomer',admin_message:'ألغى العميل الطلب'};
 const {data,error:updateError}=await db.from('orders').update({...update,updated_at:new Date().toISOString()}).eq('id',id).select().single();
 if(updateError)return Response.json({error:updateError.message},{status:400,headers:cors});
 const {tracking_code_hash:_hash,...safeOrder}=data;
 return Response.json({order:safeOrder},{status:200,headers:cors});
});
