import express from 'express';
import { z } from 'zod';
import { pool, withTransaction } from './db.js';
import { authenticate, allowRoles, loadUser, createToken, hashPassword, verifyPassword } from './auth.js';
import { calculateDeliveryFee, canTransition, haversineKm } from './domain.js';
import { config } from './config.js';

export const router = express.Router();
const api = express.Router();
router.use('/api', api);

const phoneSchema = z.string().trim().min(7).max(20);
const passwordSchema = z.string().min(8).max(128);
const authGuard = [authenticate, loadUser];
const adminGuard = [...authGuard, allowRoles('admin')];
const courierGuard = [...authGuard, allowRoles('courier')];
const customerGuard = [...authGuard, allowRoles('customer')];

function fail(status, message) {
  const error = new Error(message);
  error.status = status;
  throw error;
}

function publicUser(user) {
  return { id: user.id, role: user.role, name: user.name, phone: user.phone, username: user.username };
}

api.get('/health', async (_req, res) => {
  await pool.query('SELECT 1');
  res.json({ status: 'ok', service: 'taiz-express-api' });
});

// Customer registration. Admins and couriers are created by the admin only.
api.post('/auth/register', async (req, res) => {
  const body = z.object({ name: z.string().trim().min(2).max(100), phone: phoneSchema, password: passwordSchema }).parse(req.body);
  const passwordHash = await hashPassword(body.password);
  try {
    const { rows } = await pool.query(
      `INSERT INTO users(role, name, phone, password_hash)
       VALUES ('customer', $1, $2, $3)
       RETURNING id, role, name, phone, username`,
      [body.name, body.phone, passwordHash],
    );
    const user = rows[0];
    res.status(201).json({ token: createToken(user), user: publicUser(user) });
  } catch (error) {
    if (error.code === '23505') return res.status(409).json({ error: 'رقم الهاتف مسجل مسبقاً.' });
    throw error;
  }
});

api.post('/auth/login', async (req, res) => {
  const body = z.object({ identifier: z.string().trim().min(3).max(120), password: passwordSchema }).parse(req.body);
  const { rows } = await pool.query(
    `SELECT id, role, name, phone, username, password_hash, is_active
     FROM users WHERE (phone = $1 OR username = $1) LIMIT 1`,
    [body.identifier],
  );
  const user = rows[0];
  if (!user || !user.is_active || !(await verifyPassword(body.password, user.password_hash))) {
    return res.status(401).json({ error: 'بيانات الدخول غير صحيحة.' });
  }
  res.json({ token: createToken(user), user: publicUser(user) });
});

api.get('/me', ...authGuard, (req, res) => res.json({ user: publicUser(req.user) }));

// Public catalogue: no restaurant login accounts are created.
api.get('/catalog', async (_req, res) => {
  const restaurants = await pool.query(
    `SELECT id, name, description, address, image_url, latitude, longitude, opening_hour, closing_hour
     FROM restaurants WHERE is_active = TRUE ORDER BY name`,
  );
  const products = await pool.query(
    `SELECT p.id, p.restaurant_id, p.name, p.description, p.category, p.price_yer, p.unit, p.image_url, p.is_available
     FROM products p JOIN restaurants r ON r.id = p.restaurant_id
     WHERE r.is_active = TRUE AND p.is_available = TRUE ORDER BY p.name`,
  );
  res.json({ restaurants: restaurants.rows, products: products.rows });
});

api.post('/orders', ...customerGuard, async (req, res) => {
  const body = z.object({
    items: z.array(z.object({ productId: z.string().uuid(), quantity: z.number().int().min(1).max(99) })).min(1).max(50),
    address: z.string().trim().min(4).max(500),
    latitude: z.number().min(-90).max(90).optional(),
    longitude: z.number().min(-180).max(180).optional(),
    notes: z.string().max(1000).optional().default(''),
  }).refine((value) => (value.latitude === undefined) === (value.longitude === undefined), {
    message: 'يجب إرسال خط العرض وخط الطول معاً.',
  }).parse(req.body);

  const quantities = new Map();
  for (const item of body.items) quantities.set(item.productId, (quantities.get(item.productId) || 0) + item.quantity);
  const productIds = [...quantities.keys()];

  const order = await withTransaction(async (client) => {
    const { rows: products } = await client.query(
      `SELECT p.id, p.restaurant_id, p.name, p.unit, p.price_yer, p.is_available,
              r.name AS restaurant_name, r.latitude AS restaurant_latitude, r.longitude AS restaurant_longitude, r.is_active AS restaurant_active
       FROM products p JOIN restaurants r ON r.id = p.restaurant_id
       WHERE p.id = ANY($1::uuid[]) FOR SHARE OF p, r`,
      [productIds],
    );
    if (products.length !== productIds.length) fail(400, 'بعض المنتجات لم تعد موجودة. حدّث السلة.');
    const restaurantIds = new Set(products.map((product) => product.restaurant_id));
    if (restaurantIds.size !== 1) fail(400, 'كل طلب يجب أن يكون من متجر أو مطعم واحد. أنشئ طلباً مستقلاً لكل متجر.');
    if (products.some((product) => !product.is_available || !product.restaurant_active)) fail(409, 'يوجد منتج أو متجر غير متاح حالياً.');

    const productById = new Map(products.map((product) => [product.id, product]));
    let subtotal = 0;
    const lines = body.items.map((item) => {
      const product = productById.get(item.productId);
      const lineTotal = Number(product.price_yer) * item.quantity;
      subtotal += lineTotal;
      return { ...item, product, lineTotal };
    });
    if (!Number.isSafeInteger(subtotal)) fail(400, 'إجمالي الطلب أكبر من الحد المسموح.');

    const restaurant = products[0];
    let distanceKm = null;
    if (body.latitude !== undefined && restaurant.restaurant_latitude !== null && restaurant.restaurant_longitude !== null) {
      distanceKm = haversineKm(restaurant.restaurant_latitude, restaurant.restaurant_longitude, body.latitude, body.longitude);
    }
    const deliveryFee = calculateDeliveryFee(distanceKm, config.deliveryBaseFee, config.deliveryPerKmFee);
    const total = subtotal + deliveryFee;
    const { rows: created } = await client.query(
      `INSERT INTO orders(customer_id, restaurant_id, customer_name, customer_phone, address_text,
       customer_latitude, customer_longitude, delivery_distance_km, notes, subtotal_yer, delivery_fee_yer,
       total_yer, payment_method, payment_status, status)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,'cash_on_delivery','unpaid','pending')
       RETURNING *`,
      [req.user.id, restaurant.restaurant_id, req.user.name, req.user.phone, body.address,
       body.latitude ?? null, body.longitude ?? null, distanceKm, body.notes, subtotal, deliveryFee, total],
    );
    for (const line of lines) {
      await client.query(
        `INSERT INTO order_items(order_id, product_id, product_name, unit, quantity, unit_price_yer, line_total_yer)
         VALUES ($1,$2,$3,$4,$5,$6,$7)`,
        [created[0].id, line.product.id, line.product.name, line.product.unit, line.quantity, line.product.price_yer, line.lineTotal],
      );
    }
    return { ...created[0], items: lines.map((line) => ({ product_id: line.product.id, product_name: line.product.name, quantity: line.quantity, unit_price_yer: line.product.price_yer, line_total_yer: line.lineTotal })) };
  });
  res.status(201).json({ order });
});

api.get('/orders/mine', ...customerGuard, async (req, res) => {
  const { rows } = await pool.query(
    `SELECT o.*, r.name AS restaurant_name,
       COALESCE(json_agg(json_build_object('product_name', oi.product_name, 'quantity', oi.quantity,
          'unit_price_yer', oi.unit_price_yer, 'line_total_yer', oi.line_total_yer)) FILTER (WHERE oi.id IS NOT NULL), '[]') AS items
     FROM orders o JOIN restaurants r ON r.id = o.restaurant_id
     LEFT JOIN order_items oi ON oi.order_id = o.id
     WHERE o.customer_id = $1 GROUP BY o.id, r.name ORDER BY o.created_at DESC`,
    [req.user.id],
  );
  res.json({ orders: rows });
});

api.get('/orders/:id/location', ...customerGuard, async (req, res) => {
  const { rows } = await pool.query(
    `SELECT o.id, o.status, cl.latitude, cl.longitude, cl.recorded_at
     FROM orders o LEFT JOIN LATERAL (
       SELECT latitude, longitude, recorded_at FROM courier_locations
       WHERE order_id = o.id ORDER BY recorded_at DESC LIMIT 1
     ) cl ON TRUE
     WHERE o.id = $1 AND o.customer_id = $2`,
    [req.params.id, req.user.id],
  );
  if (!rows[0]) return res.status(404).json({ error: 'الطلب غير موجود.' });
  res.json({ location: rows[0] });
});

// Admin overview and manual dispatch.
api.get('/admin/orders', ...adminGuard, async (req, res) => {
  const status = req.query.status;
  const values = [];
  let where = '';
  if (typeof status === 'string' && status.length > 0) { values.push(status); where = `WHERE o.status = $${values.length}`; }
  const { rows } = await pool.query(
    `SELECT o.*, r.name AS restaurant_name, c.name AS courier_name,
      COALESCE(json_agg(json_build_object('product_name', oi.product_name, 'quantity', oi.quantity,
        'unit_price_yer', oi.unit_price_yer, 'line_total_yer', oi.line_total_yer)) FILTER (WHERE oi.id IS NOT NULL), '[]') AS items
     FROM orders o JOIN restaurants r ON r.id = o.restaurant_id
     LEFT JOIN users c ON c.id = o.courier_id LEFT JOIN order_items oi ON oi.order_id = o.id
     ${where} GROUP BY o.id, r.name, c.name ORDER BY o.created_at DESC LIMIT 300`, values,
  );
  res.json({ orders: rows });
});

api.get('/admin/couriers', ...adminGuard, async (_req, res) => {
  const { rows } = await pool.query(
    `SELECT u.id, u.name, u.phone, u.username, u.is_active,
      NOT EXISTS (SELECT 1 FROM orders o WHERE o.courier_id = u.id AND o.status IN ('assigned','picked_up','on_the_way')) AS is_available
     FROM users u WHERE u.role = 'courier' ORDER BY u.name`,
  );
  res.json({ couriers: rows });
});

api.post('/admin/couriers', ...adminGuard, async (req, res) => {
  const body = z.object({ name: z.string().trim().min(2).max(100), username: z.string().trim().min(3).max(50).regex(/^[a-zA-Z0-9._-]+$/), phone: phoneSchema, password: passwordSchema }).parse(req.body);
  const passwordHash = await hashPassword(body.password);
  try {
    const { rows } = await pool.query(
      `INSERT INTO users(role, name, username, phone, password_hash) VALUES ('courier',$1,$2,$3,$4)
       RETURNING id, role, name, username, phone, is_active`,
      [body.name, body.username, body.phone, passwordHash],
    );
    res.status(201).json({ courier: rows[0] });
  } catch (error) {
    if (error.code === '23505') return res.status(409).json({ error: 'اسم المستخدم أو رقم الهاتف مستخدم.' });
    throw error;
  }
});

api.patch('/admin/couriers/:id/active', ...adminGuard, async (req, res) => {
  const body = z.object({ isActive: z.boolean() }).parse(req.body);
  if (!body.isActive) {
    const active = await pool.query("SELECT 1 FROM orders WHERE courier_id = $1 AND status IN ('assigned','picked_up','on_the_way') LIMIT 1", [req.params.id]);
    if (active.rowCount) fail(409, 'لا يمكن إيقاف مندوب لديه طلب نشط.');
  }
  const { rows } = await pool.query("UPDATE users SET is_active=$1, updated_at=NOW() WHERE id=$2 AND role='courier' RETURNING id, name, is_active", [body.isActive, req.params.id]);
  if (!rows[0]) fail(404, 'المندوب غير موجود.');
  res.json({ courier: rows[0] });
});

api.patch('/admin/orders/:id/assign', ...adminGuard, async (req, res) => {
  const body = z.object({ courierId: z.string().uuid() }).parse(req.body);
  const result = await withTransaction(async (client) => {
    const { rows: orders } = await client.query('SELECT * FROM orders WHERE id=$1 FOR UPDATE', [req.params.id]);
    const order = orders[0];
    if (!order) fail(404, 'الطلب غير موجود.');
    if (order.status !== 'ready') fail(409, 'يمكن تعيين المندوب بعد أن يصبح الطلب جاهزاً للاستلام.');
    const { rows: couriers } = await client.query("SELECT id FROM users WHERE id=$1 AND role='courier' AND is_active=TRUE FOR UPDATE", [body.courierId]);
    if (!couriers[0]) fail(404, 'حساب المندوب غير موجود أو موقوف.');
    const busy = await client.query("SELECT 1 FROM orders WHERE courier_id=$1 AND status IN ('assigned','picked_up','on_the_way') LIMIT 1", [body.courierId]);
    if (busy.rowCount) fail(409, 'المندوب مرتبط بطلب نشط آخر.');
    const { rows } = await client.query("UPDATE orders SET courier_id=$1, status='assigned', updated_at=NOW() WHERE id=$2 RETURNING *", [body.courierId, req.params.id]);
    return rows[0];
  });
  res.json({ order: result });
});

api.patch('/admin/orders/:id/status', ...adminGuard, async (req, res) => {
  const body = z.object({ status: z.enum(['accepted','preparing','ready','cancelled']) }).parse(req.body);
  const updatedOrder = await withTransaction(async (client) => {
    const { rows } = await client.query('SELECT status,payment_status FROM orders WHERE id=$1 FOR UPDATE', [req.params.id]);
    if (!rows[0]) fail(404, 'الطلب غير موجود.');
    if (!canTransition(rows[0].status, body.status)) fail(409, 'انتقال حالة الطلب غير مسموح.');
    if (body.status === 'cancelled' && rows[0].payment_status === 'collected') {
      fail(409, 'لا يمكن إلغاء طلب تم تحصيل قيمته؛ يلزم إجراء تسوية مالية منفصل.');
    }
    const { rows: updated } = await client.query('UPDATE orders SET status=$1, updated_at=NOW() WHERE id=$2 RETURNING *', [body.status, req.params.id]);
    return updated[0];
  });
  res.json({ order: updatedOrder });
});

// Admin-managed restaurant catalogue; there are deliberately no restaurant accounts.
api.get('/admin/restaurants', ...adminGuard, async (_req, res) => {
  const { rows } = await pool.query('SELECT * FROM restaurants ORDER BY name');
  res.json({ restaurants: rows });
});

api.post('/admin/restaurants', ...adminGuard, async (req, res) => {
  const body = z.object({ name: z.string().trim().min(2).max(120), description: z.string().max(1000).optional(), address: z.string().max(500).optional(), imageUrl: z.string().url().or(z.literal('')).optional(), latitude: z.number().min(-90).max(90).optional(), longitude: z.number().min(-180).max(180).optional(), isActive: z.boolean().optional() }).refine((v) => (v.latitude === undefined) === (v.longitude === undefined)).parse(req.body);
  const { rows } = await pool.query(
    `INSERT INTO restaurants(name,description,address,image_url,latitude,longitude,is_active)
     VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING *`,
    [body.name, body.description ?? '', body.address ?? '', body.imageUrl ?? '', body.latitude ?? null, body.longitude ?? null, body.isActive ?? true],
  );
  res.status(201).json({ restaurant: rows[0] });
});

api.patch('/admin/restaurants/:id', ...adminGuard, async (req, res) => {
  const body = z.object({ name: z.string().trim().min(2).max(120).optional(), description: z.string().max(1000).optional(), address: z.string().max(500).optional(), imageUrl: z.string().url().or(z.literal('')).optional(), latitude: z.number().min(-90).max(90).nullable().optional(), longitude: z.number().min(-180).max(180).nullable().optional(), isActive: z.boolean().optional() }).refine((v) => (v.latitude === undefined) === (v.longitude === undefined) || (v.latitude === null && v.longitude === null)).parse(req.body);
  const { rows } = await pool.query(
    `UPDATE restaurants SET name=COALESCE($1,name), description=COALESCE($2,description), address=COALESCE($3,address),
      image_url=COALESCE($4,image_url), latitude=CASE WHEN $5::boolean THEN $6 ELSE latitude END,
      longitude=CASE WHEN $7::boolean THEN $8 ELSE longitude END, is_active=COALESCE($9,is_active), updated_at=NOW()
     WHERE id=$10 RETURNING *`,
    [body.name ?? null, body.description ?? null, body.address ?? null, body.imageUrl ?? null,
     body.latitude !== undefined, body.latitude ?? null, body.longitude !== undefined, body.longitude ?? null, body.isActive ?? null, req.params.id],
  );
  if (!rows[0]) fail(404, 'المطعم غير موجود.');
  res.json({ restaurant: rows[0] });
});

api.get('/admin/products', ...adminGuard, async (_req, res) => {
  const { rows } = await pool.query(
    `SELECT p.*, r.name AS restaurant_name FROM products p JOIN restaurants r ON r.id=p.restaurant_id ORDER BY r.name,p.name`,
  );
  res.json({ products: rows });
});

api.post('/admin/products', ...adminGuard, async (req, res) => {
  const body = z.object({ restaurantId: z.string().uuid(), name: z.string().trim().min(2).max(150), description: z.string().max(1000).optional(), category: z.string().trim().min(1).max(60), priceYer: z.number().int().min(0).max(Number.MAX_SAFE_INTEGER), unit: z.string().max(40).optional(), imageUrl: z.string().url().or(z.literal('')).optional(), isAvailable: z.boolean().optional() }).parse(req.body);
  const { rows } = await pool.query(
    `INSERT INTO products(restaurant_id,name,description,category,price_yer,unit,image_url,is_available)
     SELECT id,$2,$3,$4,$5,$6,$7,$8 FROM restaurants WHERE id=$1 AND is_active=TRUE RETURNING *`,
    [body.restaurantId, body.name, body.description ?? '', body.category, body.priceYer, body.unit ?? 'حبة', body.imageUrl ?? '', body.isAvailable ?? true],
  );
  if (!rows[0]) fail(404, 'المطعم غير موجود أو غير مفعل.');
  res.status(201).json({ product: rows[0] });
});

api.patch('/admin/products/:id', ...adminGuard, async (req, res) => {
  const body = z.object({ name: z.string().trim().min(2).max(150).optional(), description: z.string().max(1000).optional(), category: z.string().trim().min(1).max(60).optional(), priceYer: z.number().int().min(0).max(Number.MAX_SAFE_INTEGER).optional(), unit: z.string().max(40).optional(), imageUrl: z.string().url().or(z.literal('')).optional(), isAvailable: z.boolean().optional() }).parse(req.body);
  const { rows } = await pool.query(
    `UPDATE products SET name=COALESCE($1,name),description=COALESCE($2,description),category=COALESCE($3,category),
      price_yer=COALESCE($4,price_yer),unit=COALESCE($5,unit),image_url=COALESCE($6,image_url),
      is_available=COALESCE($7,is_available),updated_at=NOW() WHERE id=$8 RETURNING *`,
    [body.name ?? null, body.description ?? null, body.category ?? null, body.priceYer ?? null, body.unit ?? null, body.imageUrl ?? null, body.isAvailable ?? null, req.params.id],
  );
  if (!rows[0]) fail(404, 'المنتج غير موجود.');
  res.json({ product: rows[0] });
});

// Courier can see only their own assigned orders.
api.get('/courier/orders', ...courierGuard, async (req, res) => {
  const { rows } = await pool.query(
    `SELECT o.*, r.name AS restaurant_name, r.address AS restaurant_address,
      COALESCE(json_agg(json_build_object('product_name', oi.product_name, 'quantity', oi.quantity,
        'unit_price_yer', oi.unit_price_yer, 'line_total_yer', oi.line_total_yer)) FILTER (WHERE oi.id IS NOT NULL), '[]') AS items
     FROM orders o JOIN restaurants r ON r.id=o.restaurant_id
     LEFT JOIN order_items oi ON oi.order_id=o.id WHERE o.courier_id=$1
     GROUP BY o.id,r.name,r.address ORDER BY o.created_at DESC`, [req.user.id],
  );
  res.json({ orders: rows });
});

api.patch('/courier/orders/:id/status', ...courierGuard, async (req, res) => {
  const body = z.object({ status: z.enum(['picked_up','on_the_way','delivered']) }).parse(req.body);
  const result = await withTransaction(async (client) => {
    const { rows } = await client.query('SELECT * FROM orders WHERE id=$1 AND courier_id=$2 FOR UPDATE', [req.params.id, req.user.id]);
    const order = rows[0];
    if (!order) fail(404, 'الطلب غير مسند إلى حسابك.');
    if (!canTransition(order.status, body.status)) fail(409, 'تحديث حالة الطلب غير مسموح.');
    if (body.status === 'delivered' && order.payment_status !== 'collected') fail(409, 'يجب تأكيد تحصيل المبلغ نقداً قبل إنهاء الطلب.');
    const updated = await client.query('UPDATE orders SET status=$1,updated_at=NOW() WHERE id=$2 RETURNING *', [body.status, req.params.id]);
    return updated.rows[0];
  });
  res.json({ order: result });
});

api.post('/courier/orders/:id/collect-cash', ...courierGuard, async (req, res) => {
  const body = z.object({ amountYer: z.number().int().min(0) }).parse(req.body);
  const result = await withTransaction(async (client) => {
    const { rows } = await client.query('SELECT * FROM orders WHERE id=$1 AND courier_id=$2 FOR UPDATE', [req.params.id, req.user.id]);
    const order = rows[0];
    if (!order) fail(404, 'الطلب غير مسند إلى حسابك.');
    if (order.status !== 'on_the_way') fail(409, 'لا يمكن تسجيل التحصيل إلا أثناء توصيل الطلب.');
    if (order.payment_status === 'collected') fail(409, 'تم تسجيل تحصيل هذا الطلب مسبقاً.');
    if (Number(order.total_yer) !== body.amountYer) fail(400, 'المبلغ المحصل لا يطابق إجمالي الطلب.');
    const { rows: updated } = await client.query(
      "UPDATE orders SET payment_status='collected',cash_collected_by=$1,cash_collected_at=NOW(),updated_at=NOW() WHERE id=$2 RETURNING *",
      [req.user.id, req.params.id],
    );
    return updated[0];
  });
  res.json({ order: result, message: 'تم تسجيل تحصيل المبلغ النقدي.' });
});

api.post('/courier/location', ...courierGuard, async (req, res) => {
  const body = z.object({ orderId: z.string().uuid(), latitude: z.number().min(-90).max(90), longitude: z.number().min(-180).max(180) }).parse(req.body);
  const { rows } = await pool.query(
    `INSERT INTO courier_locations(courier_id,order_id,latitude,longitude)
     SELECT $1,o.id,$3,$4 FROM orders o
     WHERE o.id=$2 AND o.courier_id=$1 AND o.status IN ('assigned','picked_up','on_the_way') RETURNING *`,
    [req.user.id, body.orderId, body.latitude, body.longitude],
  );
  if (!rows[0]) fail(404, 'لا يوجد طلب نشط بهذا الرقم مسند إلى حسابك.');
  res.status(201).json({ location: rows[0] });
});

export const errorHandler = (error, _req, res, _next) => {
  if (error instanceof z.ZodError) return res.status(400).json({ error: 'البيانات المرسلة غير مكتملة أو غير صحيحة.', details: error.issues.map((issue) => ({ field: issue.path.join('.'), message: issue.message })) });
  if (error.code === '23505') return res.status(409).json({ error: 'القيمة مسجلة مسبقاً.' });
  if (error.code === '23503') return res.status(400).json({ error: 'هناك ارتباط ببيانات غير موجودة.' });
  const status = Number.isInteger(error.status) ? error.status : 500;
  if (status >= 500) console.error(error);
  return res.status(status).json({ error: status >= 500 ? 'حدث خطأ داخلي في الخادم.' : error.message });
};
