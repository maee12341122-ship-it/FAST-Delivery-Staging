import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const cors={ 'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS' };
Deno.serve(async(req)=>{
 if(req.method==='OPTIONS') return new Response('ok',{headers:cors});
 if(req.method!=='POST') return Response.json({error:'Method not allowed'},{status:405,headers:cors});
 const url=Deno.env.get('SUPABASE_URL'); const anon=Deno.env.get('SUPABASE_ANON_KEY'); const service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
 if(!url||!anon||!service) return Response.json({error:'Server configuration missing'},{status:500,headers:cors});
 const auth=createClient(url,anon,{global:{headers:{Authorization:req.headers.get('Authorization')??''}}});
 const {data:{user},error:authErr}=await auth.auth.getUser();
 if(authErr||!user||user.app_metadata?.role!=='courier') return Response.json({error:'Courier authorization required'},{status:403,headers:cors});
 let b:Record<string,unknown>; try{b=await req.json();}catch{return Response.json({error:'Invalid JSON'},{status:400,headers:cors});}
 const orderId=String(b.orderId??''); const action=String(b.action??'');
 const transitions:Record<string,{status:string,message:string}>={
  accept:{status:'onTheWay',message:'المندوب قبل الطلب وهو في الطريق'},
  reject:{status:'rejectedByCourier',message:'المندوب رفض الطلب'},
  arrived:{status:'arrived',message:'وصل المندوب إلى موقع العميل'},
  delivered:{status:'delivered',message:'تم التسليم وتأكيد استلام المبلغ النقدي'},
 };
 if(!orderId||!transitions[action]) return Response.json({error:'Invalid order/action'},{status:400,headers:cors});
 const db=createClient(url,service,{auth:{autoRefreshToken:false,persistSession:false}});
 const {data:courier,error:cErr}=await db.from('couriers').select('name').eq('auth_user_id',user.id).maybeSingle();
 if(cErr||!courier) return Response.json({error:'Courier profile not found'},{status:404,headers:cors});
 const {data:order,error:oErr}=await db.from('orders').select('id,status,assigned_courier,payment_status').eq('id',orderId).maybeSingle();
 if(oErr||!order||order.assigned_courier!==courier.name) return Response.json({error:'Order is not assigned to this courier'},{status:403,headers:cors});
 const allowed:Record<string,string[]>={accept:['waitingCourierApproval'],reject:['waitingCourierApproval'],arrived:['onTheWay'],delivered:['arrived']};
 if(!allowed[action].includes(order.status)) return Response.json({error:'Invalid order state transition'},{status:409,headers:cors});
 if(action==='delivered' && order.payment_status==='collected') return Response.json({error:'Payment already collected'},{status:409,headers:cors});
 const update:Record<string,unknown>={status:transitions[action].status,admin_message:transitions[action].message,updated_at:new Date().toISOString()};
 if(action==='reject'){ update.assigned_courier='لم يتم التعيين'; update.is_fee_sent=false; }
 if(action==='delivered'){ update.payment_status='collected'; update.cash_collected_by=user.id; update.cash_collected_at=new Date().toISOString(); }
 const {data,error}=await db.from('orders').update(update).eq('id',orderId).select().single();
 if(error) return Response.json({error:error.message},{status:400,headers:cors});
 const {tracking_code_hash:_hash,...safeOrder}=data;
 return Response.json({order:safeOrder},{status:200,headers:cors});
});
