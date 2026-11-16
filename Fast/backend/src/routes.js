import express from 'express';
import { z } from 'zod';
import { supabase } from './db.js';
import { authenticate, allowRoles, loadUser } from './auth.js';
import { config } from './config.js';

export const router = express.Router();
const api = express.Router();
router.use('/api', api);

const phoneSchema = z.string().trim().min(7).max(20);
const authGuard = [authenticate, loadUser];
const adminGuard = [...authGuard, allowRoles('admin')];
const courierGuard = [...authGuard, allowRoles('courier')];
const customerGuard = [...authGuard, allowRoles('customer')];

function fail(status, message) {
  const error = new Error(message);
  error.status = status;
  throw error;
}

api.get('/health', async (_req, res) => {
  const { error } = await supabase.from('settings').select('id').limit(1);
  if (error) throw error;
  res.json({ status: 'ok', service: 'fast-delivery-api' });
});

// 🌐 الكتالوج العام (المطاعم والمنتجات المتاحة)
api.get('/catalog', async (_req, res) => {
  const { data: restaurants, error: restError } = await supabase
    .from('restaurants')
    .select('*')
    .eq('is_active', true)
    .order('name');
  if (restError) throw restError;

  const { data: products, error: prodError } = await supabase
    .from('products')
    .select('*')
    .eq('available', true)
    .order('name');
  if (prodError) throw prodError;

  res.json({ restaurants: restaurants || [], products: products || [] });
});

// 🛒 إنشاء طلب جديد من قبل العميل
api.post('/orders', ...customerGuard, async (req, res) => {
  const body = z.object({
    items: z.array(z.object({
      name: z.string().min(1),
      price: z.number().min(0),
      quantity: z.number().int().min(1).max(99)
    })).min(1).max(50),
    address: z.string().trim().min(4).max(500),
    notes: z.string().max(1000).optional().default(''),
  }).parse(req.body);

  const customerName = req.userProfile?.name || 'عميل';
  const phone = req.userProfile?.phone || '';

  let productsTotal = 0;
  const itemsDescriptionParts = [];

  for (const item of body.items) {
    const lineTotal = item.price * item.quantity;
    productsTotal += lineTotal;
    itemsDescriptionParts.push(`${item.name} (${item.quantity}) - ${lineTotal} ر.ي`);
  }

  // جلب رسوم التوصيل الأساسية من الإعدادات
  const { data: settingsData } = await supabase.from('settings').select('delivery_fee').eq('id', 1).maybeSingle();
  const deliveryFee = settingsData ? Number(settingsData.delivery_fee) : config.deliveryBaseFee;
  const totalPrice = productsTotal + deliveryFee;
  const itemsDescription = itemsDescriptionParts.join(', ');

  // إدخال الطلب في جدول orders المتوافق مع الأعمدة الحقيقية
  const { data: orderData, error: orderError } = await supabase
    .from('orders')
    .insert({
      customer_name: customerName,
      phone: phone,
      address: body.address,
      items_description: itemsDescription,
      products_total: productsTotal,
      delivery_fee: deliveryFee,
      total_price: totalPrice,
      status: 'waitingForPricing',
      is_fee_sent: false
    })
    .select()
    .single();

  if (orderError) throw orderError;

  // إدخال أصناف الطلب المفصلة في order_items
  const itemsToInsert = body.items.map(item => ({
    order_id: orderData.id,
    product_name: item.name,
    price: item.price,
    quantity: item.quantity,
    total_price: item.price * item.quantity
  }));

  const { error: itemsError } = await supabase.from('order_items').insert(itemsToInsert);
  if (itemsError) {
    console.error('⚠️ تحذير في إدخال تفاصيل المنتجات:', itemsError.message);
  }

  res.status(201).json({ order: orderData });
});

// 📦 طلبات العميل الشخصية
api.get('/orders/mine', ...customerGuard, async (req, res) => {
  const phone = req.userProfile?.phone;
  if (!phone) return res.json({ orders: [] });

  const { data: orders, error } = await supabase
    .from('orders')
    .select('*, order_items(*)')
    .eq('phone', phone)
    .order('created_at', { ascending: false });

  if (error) throw error;
  res.json({ orders: orders || [] });
});

// 🛠️ لوحة تحكم المشرف: جلب جميع الطلبات
api.get('/admin/orders', ...adminGuard, async (req, res) => {
  const status = req.query.status;
  let query = supabase.from('orders').select('*, order_items(*)').order('created_at', { ascending: false }).limit(300);
  if (status) {
    query = query.eq('status', status);
  }
  const { data, error } = await query;
  if (error) throw error;
  res.json({ orders: data || [] });
});

// 💰 المشرف: تحديد رسوم التوصيل وتعيين المندوب للطلب (التسعير)
api.patch('/admin/orders/:id/pricing', ...adminGuard, async (req, res) => {
  const body = z.object({
    deliveryFee: z.number().min(0),
    assignedCourier: z.string().min(1)
  }).parse(req.body);

  const orderId = req.params.id;

  const { data: order, error: fetchError } = await supabase.from('orders').select('products_total').eq('id', orderId).maybeSingle();
  if (!order) fail(404, 'الطلب غير موجود.');

  const productsTotal = Number(order.products_total) || 0;
  const totalPrice = productsTotal + body.deliveryFee;

  const { data, error } = await supabase
    .from('orders')
    .update({
      delivery_fee: body.deliveryFee,
      total_price: totalPrice,
      assigned_courier: body.assignedCourier,
      status: 'pricingSentToCustomer',
      is_fee_sent: true
    })
    .eq('id', orderId)
    .select()
    .single();

  if (error) throw error;
  res.json({ order: data });
});

// 🔄 المشرف: تحديث حالة الطلب
api.patch('/admin/orders/:id/status', ...adminGuard, async (req, res) => {
  const body = z.object({ status: z.string().min(1) }).parse(req.body);
  const { data, error } = await supabase
    .from('orders')
    .update({ status: body.status })
    .eq('id', req.params.id)
    .select()
    .single();

  if (error) throw error;
  res.json({ order: data });
});

// 🛵 طلبات المندوب المسندة إليه
api.get('/courier/orders', ...courierGuard, async (req, res) => {
  const courierName = req.userProfile?.name;
  if (!courierName) return res.json({ orders: [] });

  const { data, error } = await supabase
    .from('orders')
    .select('*, order_items(*)')
    .eq('assigned_courier', courierName)
    .order('created_at', { ascending: false });

  if (error) throw error;
  res.json({ orders: data || [] });
});

// 🛵 المندوب: تحديث حالة الطلب
api.patch('/courier/orders/:id/status', ...courierGuard, async (req, res) => {
  const body = z.object({ status: z.enum(['acceptedByCourier', 'onTheWay', 'delivered', 'cancelled']) }).parse(req.body);
  const { data, error } = await supabase
    .from('orders')
    .update({ status: body.status })
    .eq('id', req.params.id)
    .select()
    .single();

  if (error) throw error;
  res.json({ order: data });
});

// 📍 المندوب: تحديث الموقع الجغرافي
api.post('/courier/location', ...courierGuard, async (req, res) => {
  const body = z.object({
    latitude: z.number().min(-90).max(90),
    longitude: z.number().min(-180).max(180)
  }).parse(req.body);

  const courierId = req.userProfile?.id;
  if (!courierId) fail(401, 'حساب المندوب غير محدد.');

  const { data, error } = await supabase
    .from('courier_locations')
    .insert({
      courier_id: courierId.toString(),
      latitude: body.latitude,
      longitude: body.longitude
    })
    .select()
    .single();

  if (error) throw error;
  res.status(201).json({ location: data });
});

export const errorHandler = (error, _req, res, _next) => {
  if (error instanceof z.ZodError) {
    return res.status(400).json({ 
      error: 'البيانات المرسلة غير مكتملة أو غير صحيحة.', 
      details: error.issues.map((issue) => ({ field: issue.path.join('.'), message: issue.message })) 
    });
  }
  const status = Number.isInteger(error.status) ? error.status : 500;
  if (status >= 500) console.error(error);
  return res.status(status).json({ error: status >= 500 ? 'حدث خطأ داخلي في الخادم.' : error.message });
};
