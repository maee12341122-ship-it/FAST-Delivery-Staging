import express from 'express';
import crypto from 'crypto';
import { z } from 'zod';
import { supabase } from './db.js';
import { authenticate, allowRoles, loadUser } from './auth.js';
import { config } from './config.js';

export const router = express.Router();
const api = express.Router();
router.use('/api', api);

const authGuard = [authenticate, loadUser];
const adminGuard = [...authGuard, allowRoles('admin')];
const courierGuard = [...authGuard, allowRoles('courier')];
const customerGuard = [...authGuard, allowRoles('customer')];

const ALLOWED_STATUSES = new Set([
  'waitingForPricing',
  'pricingSentToCustomer',
  'approvedByCustomer',
  'waitingCourierApproval',
  'acceptedByCourier',
  'assigned',
  'onTheWay',
  'rejectedByCourier',
  'arrivedToCustomer',
  'delivered',
  'cancelled',
  'cancelledByCustomer',
]);

const ALLOWED_TRANSITIONS = {
  waitingForPricing: new Set(['pricingSentToCustomer', 'cancelled', 'cancelledByCustomer']),
  pricingSentToCustomer: new Set([
    'approvedByCustomer',
    'waitingCourierApproval',
    'acceptedByCourier',
    'assigned',
    'cancelled',
    'cancelledByCustomer',
  ]),
  approvedByCustomer: new Set(['waitingCourierApproval', 'acceptedByCourier', 'assigned', 'cancelled']),
  waitingCourierApproval: new Set(['acceptedByCourier', 'assigned', 'rejectedByCourier', 'cancelled']),
  acceptedByCourier: new Set(['onTheWay', 'arrivedToCustomer', 'delivered', 'cancelled']),
  assigned: new Set(['acceptedByCourier', 'onTheWay', 'arrivedToCustomer', 'delivered', 'cancelled']),
  onTheWay: new Set(['arrivedToCustomer', 'delivered', 'cancelled']),
  rejectedByCourier: new Set(['waitingCourierApproval', 'acceptedByCourier', 'assigned', 'cancelled']),
  arrivedToCustomer: new Set(['delivered', 'cancelled']),
  delivered: new Set([]),
  cancelled: new Set([]),
  cancelledByCustomer: new Set([]),
};

const recentOrderSubmissions = new Map();
const otpStore = new Map();

function fail(status, message) {
  const error = new Error(message);
  error.status = status;
  throw error;
}

function normalizePhone(phone) {
  let clean = String(phone || '').trim().replace(/\s+/g, '');
  if (clean.startsWith('+967')) clean = clean.slice(4);
  else if (clean.startsWith('967')) clean = clean.slice(3);
  if (clean.startsWith('0')) clean = clean.slice(1);
  return clean;
}

function parseOrderId(rawId) {
  const parsed = Number.parseInt(String(rawId), 10);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    fail(400, 'معرف الطلب غير صالح.');
  }
  return parsed;
}

function canTransitionStatus(currentStatus, nextStatus) {
  if (!ALLOWED_STATUSES.has(nextStatus)) {
    return false;
  }
  if (!currentStatus || currentStatus === nextStatus) {
    return true;
  }
  const allowedNext = ALLOWED_TRANSITIONS[currentStatus];
  if (!allowedNext) {
    return false;
  }
  return allowedNext.has(nextStatus);
}

async function recordStatusHistory({ orderId, oldStatus, newStatus, changedBy }) {
  const { error } = await supabase.from('order_status_history').insert({
    order_id: orderId,
    old_status: oldStatus ?? null,
    new_status: newStatus,
    changed_by: changedBy || 'system',
  });
  if (error) {
    fail(500, `تعذر تسجيل سجل حالة الطلب: ${error.message}`);
  }
}

function parseTimeToMinutes(rawTime) {
  if (!rawTime) return null;
  const match = String(rawTime).trim().match(/^(\d{1,2}):(\d{2})(?::(\d{2}))?$/);
  if (!match) return null;
  const hours = Number.parseInt(match[1], 10);
  const minutes = Number.parseInt(match[2], 10);
  if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59) return null;
  return hours * 60 + minutes;
}

function getCurrentMinutesInTimezone(timeZone) {
  const tz = timeZone || 'Asia/Aden';
  try {
    const formatter = new Intl.DateTimeFormat('en-GB', {
      timeZone: tz,
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    });
    const parts = formatter.formatToParts(new Date());
    const h = Number.parseInt(parts.find((p) => p.type === 'hour')?.value || '0', 10);
    const m = Number.parseInt(parts.find((p) => p.type === 'minute')?.value || '0', 10);
    return h * 60 + m;
  } catch (_err) {
    const now = new Date();
    return now.getUTCHours() * 60 + now.getUTCMinutes();
  }
}

async function assertStoreOpen() {
  const { data: settingsRow, error } = await supabase
    .from('store_settings')
    .select('store_name, open_time, close_time, is_open, timezone')
    .order('id', { ascending: true })
    .limit(1)
    .maybeSingle();

  if (error) throw error;
  if (!settingsRow) return;

  if (settingsRow.is_open === false) {
    fail(400, `المتجر (${settingsRow.store_name || 'المتجر'}) مغلق حالياً.`);
  }

  const openMin = parseTimeToMinutes(settingsRow.open_time);
  const closeMin = parseTimeToMinutes(settingsRow.close_time);
  if (openMin !== null && closeMin !== null && openMin !== closeMin) {
    const nowMin = getCurrentMinutesInTimezone(settingsRow.timezone || 'Asia/Aden');
    let isWithinHours = false;
    if (closeMin > openMin) {
      isWithinHours = nowMin >= openMin && nowMin < closeMin;
    } else {
      // ساعات العمل تتجاوز منتصف الليل (مثال: 18:00 إلى 02:00)
      isWithinHours = nowMin >= openMin || nowMin < closeMin;
    }
    if (!isWithinHours) {
      fail(400, 'المتجر خارج أوقات العمل الرسمية حالياً.');
    }
  }
}

async function evaluateCoupon(code, subtotal) {
  const normalizedCode = String(code || '').trim();
  if (!normalizedCode) {
    fail(400, 'رمز الكوبون مطلوب.');
  }

  const { data: coupon, error } = await supabase
    .from('coupons')
    .select('*')
    .ilike('code', normalizedCode)
    .maybeSingle();

  if (error) throw error;
  if (!coupon) {
    fail(404, 'كوبون الخصم غير موجود.');
  }
  if (coupon.is_active === false) {
    fail(400, 'كوبون الخصم غير مفعل.');
  }
  if (coupon.expires_at && new Date(coupon.expires_at).getTime() <= Date.now()) {
    fail(400, 'انتهت صلاحية كوبون الخصم.');
  }

  const minAmount = Number(coupon.min_order_amount ?? 0);
  if (Number(subtotal) < minAmount) {
    fail(400, `الحد الأدنى للطلب لاستخدام هذا الكوبون هو ${minAmount} ر.ي.`);
  }

  const usageLimit =
    coupon.usage_limit === null || coupon.usage_limit === undefined
      ? null
      : Number(coupon.usage_limit);
  const usedCount = Number(coupon.used_count ?? 0);
  if (usageLimit !== null && usedCount >= usageLimit) {
    fail(400, 'تم الوصول إلى الحد الأقصى لاستخدام هذا الكوبون.');
  }

  const discountValue = Number(coupon.discount_value ?? 0);
  const discountType = String(coupon.discount_type || 'percentage').toLowerCase();
  const maxDiscount = Number(coupon.max_discount ?? 0);

  let discountAmount = 0;
  if (discountType === 'percentage' || discountType === 'percent') {
    discountAmount = Number(subtotal) * (discountValue / 100);
    if (maxDiscount > 0 && discountAmount > maxDiscount) {
      discountAmount = maxDiscount;
    }
  } else {
    discountAmount = discountValue;
  }

  if (discountAmount < 0) discountAmount = 0;
  if (discountAmount > Number(subtotal)) discountAmount = Number(subtotal);
  discountAmount = Math.round(discountAmount * 100) / 100;

  return {
    coupon,
    discountAmount,
    finalSubtotal: Math.max(0, Number(subtotal) - discountAmount),
  };
}

async function consumeCouponUsage(coupon) {
  const currentUsed = Number(coupon.used_count ?? 0);
  const usageLimit =
    coupon.usage_limit === null || coupon.usage_limit === undefined
      ? null
      : Number(coupon.usage_limit);

  if (usageLimit !== null && currentUsed >= usageLimit) {
    fail(400, 'تم استنفاد الحد الأقصى لاستخدام هذا الكوبون.');
  }

  let query = supabase
    .from('coupons')
    .update({ used_count: currentUsed + 1 })
    .eq('id', coupon.id)
    .eq('used_count', currentUsed);

  if (usageLimit !== null) {
    query = query.lt('used_count', usageLimit);
  }

  const { data: updatedCoupon, error } = await query.select('id').maybeSingle();
  if (error) {
    fail(500, `تعذر تحديث عداد استخدام الكوبون: ${error.message}`);
  }
  if (!updatedCoupon) {
    fail(409, 'تعذر تطبيق الكوبون بسبب التزامن أو نفاد حد الاستخدام.');
  }
}

async function sendOneSignalNotification({ targetPlayerIds, title, body, dataPayload }) {
  const uniqueIds = Array.from(
    new Set((targetPlayerIds || []).map((id) => String(id || '').trim()).filter(Boolean))
  );
  if (uniqueIds.length === 0) return { sent: false, skipped: true };

  const appId =
    config.oneSignalAppId ||
    process.env.ONESIGNAL_APP_ID ||
    '60850bed-4af8-4df1-a2f5-77411630f447';
  const restApiKey =
    config.oneSignalRestApiKey || process.env.ONESIGNAL_REST_API_KEY;

  if (!restApiKey) {
    return { sent: false, error: 'مفتاح OneSignal السري غير مضبوط على الخادم.' };
  }

  const response = await fetch('https://api.onesignal.com/notifications', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Key ${restApiKey}`,
    },
    body: JSON.stringify({
      app_id: appId,
      include_subscription_ids: uniqueIds,
      headings: { en: title, ar: title },
      contents: { en: body, ar: body },
      ...(dataPayload ? { data: dataPayload } : {}),
    }),
  });

  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    return {
      sent: false,
      status: response.status,
      error: data?.errors?.[0] || 'تعذر إرسال الإشعار عبر OneSignal.',
    };
  }

  return { sent: true, notification: data };
}

function isOrderAssignedToCourier(order, userProfile) {
  const profileId =
    userProfile?.id !== undefined && userProfile?.id !== null
      ? String(userProfile.id).trim()
      : '';
  const orderCourierId =
    order?.courier_id !== undefined && order?.courier_id !== null
      ? String(order.courier_id).trim()
      : '';

  if (orderCourierId && profileId) {
    return orderCourierId === profileId;
  }

  const profileName = String(userProfile?.name || '').trim();
  const orderCourierName = String(order?.assigned_courier || '').trim();
  return Boolean(profileName && orderCourierName && profileName === orderCourierName);
}

api.get('/health', async (_req, res) => {
  const { error } = await supabase.from('settings').select('id').limit(1);
  if (error) throw error;
  res.json({ status: 'ok', service: 'fast-delivery-api' });
});

// 🔐 طلب رمز تحقق OTP لرقم العميل (تجريبي في otp_codes لحين ربط WhatsApp الرسمي)
api.post('/auth/otp/request', async (req, res) => {
  const body = z.object({ phone: z.string().trim().min(6).max(25) }).parse(req.body);
  const cleanPhone = normalizePhone(body.phone);
  if (!cleanPhone) {
    fail(400, 'رقم الهاتف غير صالح.');
  }

  const now = Date.now();
  const prev = otpStore.get(cleanPhone);
  if (prev && now - prev.lastSentAt < 30000) {
    fail(429, 'يرجى الانتظار قبل طلب رمز تحقق جديد.');
  }
  if (prev && prev.requestCount >= 5 && now < prev.resetAt) {
    fail(429, 'تم تجاوز الحد المسموح لطلبات رمز التحقق مؤقتاً.');
  }

  const { data: existingCustomer } = await supabase
    .from('customers')
    .select('id, name, address')
    .eq('phone', cleanPhone)
    .maybeSingle();

  const code = String(crypto.randomInt(100000, 999999));
  const codeHash = crypto.createHash('sha256').update(`${cleanPhone}:${code}`).digest('hex');
  const expiresAtIso = new Date(now + 5 * 60 * 1000).toISOString();

  await supabase.from('otp_codes').insert({
    phone: cleanPhone,
    code_hash: codeHash,
    expires_at: expiresAtIso,
    used: false,
    attempts: 0,
  });

  const nextCount = prev && now < prev.resetAt ? prev.requestCount + 1 : 1;
  const resetAt = prev && now < prev.resetAt ? prev.resetAt : now + 60 * 60 * 1000;

  otpStore.set(cleanPhone, {
    codeHash,
    expiresAt: now + 5 * 60 * 1000,
    attempts: 0,
    requestCount: nextCount,
    lastSentAt: now,
    resetAt,
  });

  const isProd = process.env.NODE_ENV === 'production';
  res.json({
    exists: Boolean(existingCustomer),
    experimental_otp: true,
    message: 'رمز تحقق تجريبي مؤقت (بانتظار ربط WhatsApp الرسمي)',
    ...(isProd ? {} : { debug_otp: code }),
  });
});

// 🔐 التحقق من رمز OTP وتسجيل/تحديث بيانات العميل
api.post('/auth/otp/verify', async (req, res) => {
  const body = z
    .object({
      phone: z.string().trim().min(6).max(25),
      otp_code: z.string().trim().min(4).max(10),
    })
    .parse(req.body);

  const cleanPhone = normalizePhone(body.phone);
  if (!cleanPhone) {
    fail(400, 'رقم الهاتف غير صالح.');
  }

  const entry = otpStore.get(cleanPhone);
  if (!entry || entry.expiresAt <= Date.now()) {
    otpStore.delete(cleanPhone);
    return res.status(400).json({
      verified: false,
      error: 'رمز التحقق غير صحيح أو منتهي الصلاحية.',
    });
  }

  if (entry.attempts >= 5) {
    otpStore.delete(cleanPhone);
    return res.status(429).json({
      verified: false,
      error: 'تم تجاوز الحد الأقصى لمحاولات التحقق.',
    });
  }

  const candidateHash = crypto
    .createHash('sha256')
    .update(`${cleanPhone}:${body.otp_code.trim()}`)
    .digest('hex');

  if (candidateHash !== entry.codeHash) {
    entry.attempts += 1;
    otpStore.set(cleanPhone, entry);
    return res.status(400).json({
      verified: false,
      error: 'رمز التحقق غير صحيح.',
    });
  }

  otpStore.delete(cleanPhone);
  await supabase
    .from('otp_codes')
    .update({ used: true })
    .eq('phone', cleanPhone)
    .eq('code_hash', entry.codeHash);

  const { data: customer } = await supabase
    .from('customers')
    .select('id, phone, name, address')
    .eq('phone', cleanPhone)
    .maybeSingle();

  res.json({
    verified: true,
    phone: cleanPhone,
    name: customer?.name || '',
    address: customer?.address || '',
  });
});

// 🔔 إرسال إشعار OneSignal (للمشرف فقط عند الإرسال المباشر إلى Player IDs محددة، أو عبر أحداث النظام من الخادم)
api.post('/notifications/send', ...adminGuard, async (req, res) => {
  const body = z
    .object({
      target_player_id: z.string().trim().min(1).max(200).optional(),
      target_player_ids: z.array(z.string().trim().min(1).max(200)).max(200).optional(),
      title: z.string().trim().min(1).max(200),
      body: z.string().trim().min(1).max(1000),
      additional_data: z.record(z.any()).optional(),
    })
    .parse(req.body);

  const targets = [
    ...(body.target_player_id ? [body.target_player_id] : []),
    ...(body.target_player_ids || []),
  ];

  if (targets.length === 0) {
    fail(400, 'يجب تحديد مستلم واحد على الأقل.');
  }

  const result = await sendOneSignalNotification({
    targetPlayerIds: targets,
    title: body.title,
    body: body.body,
    dataPayload: body.additional_data,
  });

  if (!result.sent) {
    fail(result.status || 502, result.error || 'تعذر إرسال الإشعار عبر OneSignal.');
  }

  res.json({ sent: true, notification: result.notification });
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

// 🎟️ التحقق من الكوبون وحساب الخصم في الخادم
api.post('/coupons/validate', ...authGuard, async (req, res) => {
  const body = z
    .object({
      code: z.string().trim().min(1).max(60),
      subtotal: z.number().min(0),
    })
    .parse(req.body);

  const { coupon, discountAmount } = await evaluateCoupon(body.code, body.subtotal);

  res.json({
    valid: true,
    code: coupon.code,
    discount_type: coupon.discount_type,
    discount_amount: discountAmount,
    message: 'تم تطبيق الكوبون بنجاح! 🎉',
  });
});

// 🛒 إنشاء طلب جديد (يعتمد معرف المنتج والكمية فقط ويحسب الأسعار في الخادم، ويدعم custom_)
api.post('/orders', ...customerGuard, async (req, res) => {
  const body = z
    .object({
      items: z
        .array(
          z.object({
            product_id: z.string().trim().min(1).max(120),
            quantity: z.number().int().min(1).max(99),
            name: z.string().trim().max(200).optional(),
            unit_price: z.number().min(0).optional(),
            suggested_unit_price: z.number().min(0).optional(),
            is_custom: z.boolean().optional(),
          })
        )
        .min(1)
        .max(50),
      address: z.string().trim().min(4).max(500),
      notes: z.string().max(1000).optional().default(''),
      customer_name: z.string().trim().max(150).optional(),
      phone: z.string().trim().max(25).optional(),
      coupon_code: z.string().trim().max(60).optional(),
      payment_method: z.string().trim().max(60).optional(),
      payment_account: z.string().trim().max(120).optional(),
      client_request_key: z.string().trim().max(120).optional(),
      idempotency_key: z.string().trim().max(120).optional(),
    })
    .parse(req.body);

  await assertStoreOpen();

  const requestKey = body.client_request_key || body.idempotency_key;
  const actorKey = `${req.user?.id || req.userProfile?.phone || 'anon'}`;
  const dedupSignature = requestKey
    ? `${actorKey}:${requestKey}`
    : `${actorKey}:${body.address}:${JSON.stringify(body.items)}`;

  const now = Date.now();
  for (const [k, entry] of recentOrderSubmissions.entries()) {
    if (now - entry.createdAt > 30000) {
      recentOrderSubmissions.delete(k);
    }
  }
  const existingSubmission = recentOrderSubmissions.get(dedupSignature);
  if (existingSubmission && now - existingSubmission.createdAt < 30000) {
    return res.status(200).json({
      order: existingSubmission.order,
      message: 'تم استلام الطلب مسبقاً',
    });
  }

  const customerName = body.customer_name || req.userProfile?.name || 'عميل';
  const phone = normalizePhone(req.userProfile?.phone || body.phone || '');
  if (!phone) {
    fail(400, 'رقم هاتف العميل مطلوب.');
  }

  const standardProductIds = [];
  for (const item of body.items) {
    const isCustom = item.is_custom === true || item.product_id.startsWith('custom_');
    if (!isCustom) {
      standardProductIds.push(item.product_id);
    }
  }

  let productMap = new Map();
  if (standardProductIds.length > 0) {
    const { data: dbProducts, error: prodError } = await supabase
      .from('products')
      .select('id, name, price, available, restaurant_id, restaurant_name')
      .in('id', Array.from(new Set(standardProductIds)));

    if (prodError) throw prodError;
    productMap = new Map((dbProducts || []).map((p) => [String(p.id), p]));
  }

  const restaurantIds = new Set();
  const restaurantNames = new Set();

  let productsTotal = 0;
  let hasCustomOrVariablePrice = false;
  const itemsDescriptionParts = [];
  const preparedOrderItems = [];

  for (const item of body.items) {
    const isCustom = item.is_custom === true || item.product_id.startsWith('custom_');
    const quantity = item.quantity;

    if (isCustom) {
      hasCustomOrVariablePrice = true;
      const customName = item.name || 'طلب خاص';
      const customPrice =
        item.unit_price !== undefined && Number.isFinite(item.unit_price) && item.unit_price >= 0
          ? item.unit_price
          : 0;
      const lineTotal = Math.round(customPrice * quantity * 100) / 100;
      productsTotal = Math.round((productsTotal + lineTotal) * 100) / 100;
      itemsDescriptionParts.push(
        customPrice > 0
          ? `${customName} (${quantity}) - ${lineTotal} ر.ي`
          : `${customName} (${quantity}) - تسعير حسب الطلب`
      );
      preparedOrderItems.push({
        product_name: customName,
        price: customPrice,
        quantity,
        total_price: lineTotal,
      });
      continue;
    }

    const product = productMap.get(item.product_id);
    if (!product) {
      fail(400, `المنتج غير موجود: ${item.product_id}`);
    }
    if (product.available === false) {
      fail(400, `المنتج غير متوفر حالياً: ${product.name}`);
    }

    const rawPrice = Number(product.price ?? 0);
    if (!Number.isFinite(rawPrice) || rawPrice < 0) {
      fail(400, `سعر المنتج غير صالح: ${product.name}`);
    }

    // في حال كان المنتج بسعر متغير (0) ويوجد سعر مقترح، يُسجل كسعر مبدئي ويُحول للتسعير/التأكيد
    const unitPrice = rawPrice === 0 && item.suggested_unit_price ? item.suggested_unit_price : rawPrice;
    if (rawPrice === 0) {
      hasCustomOrVariablePrice = true;
    }

    const lineTotal = Math.round(unitPrice * quantity * 100) / 100;
    productsTotal = Math.round((productsTotal + lineTotal) * 100) / 100;
    itemsDescriptionParts.push(`${product.name} (${quantity}) - ${lineTotal} ر.ي`);

    if (product.restaurant_id) restaurantIds.add(String(product.restaurant_id));
    if (product.restaurant_name) restaurantNames.add(String(product.restaurant_name));

    preparedOrderItems.push({
      product_name: product.name,
      price: unitPrice,
      quantity,
      total_price: lineTotal,
    });
  }

  if (restaurantIds.size > 1) {
    fail(400, 'لا يمكن الجمع بين منتجات من مطاعم متعددة في طلب واحد.');
  }

  let discountAmount = 0;
  let validatedCoupon = null;
  if (body.coupon_code) {
    const couponResult = await evaluateCoupon(body.coupon_code, productsTotal);
    discountAmount = couponResult.discountAmount;
    validatedCoupon = couponResult.coupon;
  }

  const discountedProductsTotal = Math.max(0, Math.round((productsTotal - discountAmount) * 100) / 100);

  const { data: settingsData } = await supabase
    .from('settings')
    .select('delivery_fee')
    .eq('id', 1)
    .maybeSingle();

  const deliveryFee = settingsData
    ? Number(settingsData.delivery_fee)
    : Number(config.deliveryBaseFee ?? 0);
  const totalPrice = Math.round((discountedProductsTotal + deliveryFee) * 100) / 100;
  const itemsDescription = itemsDescriptionParts.join(', ');
  const trackingCode = crypto.randomBytes(4).toString('hex').toUpperCase();

  const singleRestaurantId =
    restaurantIds.size === 1 ? Array.from(restaurantIds)[0] : null;
  const singleRestaurantName =
    restaurantNames.size === 1 ? Array.from(restaurantNames)[0] : null;
  const isRestaurant = Boolean(
    singleRestaurantId ||
      (singleRestaurantName &&
        singleRestaurantName !== 'متجر عام' &&
        singleRestaurantName !== 'خدمة الطلبات الخاصة')
  );

  const { data: orderData, error: orderError } = await supabase
    .from('orders')
    .insert({
      customer_name: customerName,
      phone,
      address: body.address,
      items_description: itemsDescription,
      notes: body.notes,
      tracking_code: trackingCode,
      products_total: discountedProductsTotal,
      delivery_fee: deliveryFee,
      total_price: totalPrice,
      total_amount: totalPrice,
      ...(body.payment_method ? { payment_method: body.payment_method } : {}),
      ...(body.payment_account ? { payment_account: body.payment_account } : {}),
      restaurant_id: singleRestaurantId,
      restaurant_name: singleRestaurantName,
      is_restaurant: isRestaurant,
      status: 'waitingForPricing',
      is_fee_sent: false,
      is_settled: false,
    })
    .select()
    .single();

  if (orderError) throw orderError;

  const itemsToInsert = preparedOrderItems.map((item) => ({
    order_id: orderData.id,
    ...item,
  }));

  const { error: itemsError } = await supabase.from('order_items').insert(itemsToInsert);
  if (itemsError) {
    await supabase.from('orders').delete().eq('id', orderData.id);
    fail(500, 'تعذر حفظ تفاصيل أصناف الطلب، تم إلغاء إنشاء الطلب.');
  }

  if (validatedCoupon && discountAmount > 0) {
    await consumeCouponUsage(validatedCoupon);
  }

  await recordStatusHistory({
    orderId: orderData.id,
    oldStatus: null,
    newStatus: 'waitingForPricing',
    changedBy: req.user?.id || phone,
  });

  // إشعار المشرفين عبر OneSignal عند إنشاء طلب جديد
  const { data: adminRows } = await supabase
    .from('admins')
    .select('onesignal_player_id')
    .not('onesignal_player_id', 'is', null);
  const adminPlayerIds = (adminRows || []).map((a) => a.onesignal_player_id);
  if (adminPlayerIds.length > 0) {
    await sendOneSignalNotification({
      targetPlayerIds: adminPlayerIds,
      title: 'طلب جديد في النظام 🛒',
      body: `تم استلام طلب جديد رقم #${orderData.id} (${hasCustomOrVariablePrice ? 'يتطلب مراجعة التسعير' : `${totalPrice} ر.ي`})`,
      dataPayload: { order_id: orderData.id, status: 'waitingForPricing' },
    });
  }

  recentOrderSubmissions.set(dedupSignature, {
    createdAt: now,
    order: orderData,
  });

  res.status(201).json({
    order: orderData,
    discount_amount: discountAmount,
    message: 'تم إرسال الطلب بنجاح',
  });
});

// 📦 جلب طلبات العميل الشخصية (المسار المعتمد /api/orders/my والمتوافق /api/orders/mine)
async function handleGetMyOrders(req, res) {
  const phone = normalizePhone(req.userProfile?.phone || '');
  if (!phone) return res.json({ orders: [] });

  const { data: orders, error } = await supabase
    .from('orders')
    .select('*, order_items(*)')
    .eq('phone', phone)
    .order('created_at', { ascending: false });

  if (error) throw error;
  res.json({ orders: orders || [] });
}

api.get('/orders/my', ...customerGuard, handleGetMyOrders);
api.get('/orders/mine', ...customerGuard, handleGetMyOrders);

// 📋 جلب الطلبات حسب الدور (مشرف / مندوب)
api.get('/orders', ...authGuard, async (req, res) => {
  const role = req.userRole;
  const status = req.query.status ? String(req.query.status).trim() : '';

  if (role === 'admin') {
    let query = supabase
      .from('orders')
      .select('*, order_items(*)')
      .order('created_at', { ascending: false })
      .limit(300);
    if (status) query = query.eq('status', status);
    const { data, error } = await query;
    if (error) throw error;
    return res.json({ orders: data || [] });
  }

  if (role === 'courier') {
    const courierId =
      req.userProfile?.id !== undefined ? String(req.userProfile.id).trim() : '';
    const courierName = String(req.userProfile?.name || '').trim();

    let query = supabase
      .from('orders')
      .select('*, order_items(*)')
      .order('created_at', { ascending: false });

    if (courierId && courierName) {
      query = query.or(
        `courier_id.eq.${courierId},assigned_courier.eq.${courierName}`
      );
    } else if (courierId) {
      query = query.eq('courier_id', courierId);
    } else if (courierName) {
      query = query.eq('assigned_courier', courierName);
    } else {
      return res.json({ orders: [] });
    }

    if (status) query = query.eq('status', status);
    const { data, error } = await query;
    if (error) throw error;
    return res.json({ orders: data || [] });
  }

  return handleGetMyOrders(req, res);
});

// 🛠️ لوحة تحكم المشرف: جلب جميع الطلبات
api.get('/admin/orders', ...adminGuard, async (req, res) => {
  const status = req.query.status ? String(req.query.status).trim() : '';
  let query = supabase
    .from('orders')
    .select('*, order_items(*)')
    .order('created_at', { ascending: false })
    .limit(300);
  if (status) {
    query = query.eq('status', status);
  }
  const { data, error } = await query;
  if (error) throw error;
  res.json({ orders: data || [] });
});

// 💰 تسعير الطلب وتعيين المندوب (المسار المعتمد /api/orders/:id/pricing والمتوافق /api/admin/orders/:id/pricing)
async function handlePricingOrder(req, res) {
  const orderId = parseOrderId(req.params.id);
  const body = z
    .object({
      deliveryFee: z.number().min(0).optional(),
      delivery_fee: z.number().min(0).optional(),
      assignedCourier: z.string().trim().min(1).optional(),
      assigned_courier: z.string().trim().min(1).optional(),
      courier_id: z.string().trim().min(1).optional(),
    })
    .parse(req.body);

  const fee = body.deliveryFee ?? body.delivery_fee;
  if (fee === undefined || !Number.isFinite(fee) || fee < 0) {
    fail(400, 'رسوم التوصيل غير صالحة.');
  }

  let courierRecord = null;
  if (body.courier_id) {
    const { data: cById, error: cErr } = await supabase
      .from('couriers')
      .select('id, name, onesignal_player_id')
      .eq('id', body.courier_id)
      .maybeSingle();
    if (cErr) throw cErr;
    courierRecord = cById;
  }

  const courierNameInput = (body.assignedCourier ?? body.assigned_courier ?? '').trim();
  if (!courierRecord && courierNameInput) {
    const { data: cByName, error: cNameErr } = await supabase
      .from('couriers')
      .select('id, name, onesignal_player_id')
      .eq('name', courierNameInput)
      .maybeSingle();
    if (cNameErr) throw cNameErr;
    courierRecord = cByName;
  }

  const finalCourierName =
    courierRecord?.name || courierNameInput || 'مندوب عام';
  const finalCourierId = courierRecord?.id
    ? String(courierRecord.id)
    : body.courier_id || null;

  const { data: order, error: fetchError } = await supabase
    .from('orders')
    .select('id, status, phone, products_total, total_price')
    .eq('id', orderId)
    .maybeSingle();

  if (fetchError) throw fetchError;
  if (!order) fail(404, 'الطلب غير موجود.');

  const productsTotal =
    Number(order.products_total ?? order.total_price ?? 0) || 0;
  const totalPrice = Math.round((productsTotal + fee) * 100) / 100;
  const nextStatus = 'pricingSentToCustomer';

  const { data, error } = await supabase
    .from('orders')
    .update({
      delivery_fee: fee,
      products_total: productsTotal,
      total_price: totalPrice,
      total_amount: totalPrice,
      assigned_courier: finalCourierName,
      driver_name: finalCourierName,
      courier_id: finalCourierId,
      status: nextStatus,
      is_fee_sent: true,
      admin_message: `تم تحديد رسوم التوصيل (${fee} ر.ي). بانتظار موافقة العميل ⏳`,
      updated_at: new Date().toISOString(),
    })
    .eq('id', orderId)
    .select()
    .single();

  if (error) throw error;

  await recordStatusHistory({
    orderId,
    oldStatus: order.status,
    newStatus: nextStatus,
    changedBy: req.user?.id || 'admin',
  });

  // إشعار العميل بتوفر التسعير
  if (order.phone) {
    const { data: cust } = await supabase
      .from('customers')
      .select('onesignal_player_id')
      .eq('phone', normalizePhone(order.phone))
      .maybeSingle();
    if (cust?.onesignal_player_id) {
      await sendOneSignalNotification({
        targetPlayerIds: [cust.onesignal_player_id],
        title: 'تم تسعير طلبك 💰',
        body: `إجمالي الطلب #${orderId} أصبح ${totalPrice} ر.ي (شامل التوصيل). يرجى تأكيد الموافقة.`,
        dataPayload: { order_id: orderId, status: nextStatus },
      });
    }
  }

  res.json({ order: data, message: 'تم تحديث السعر بنجاح' });
}

api.post('/orders/:id/pricing', ...adminGuard, handlePricingOrder);
api.patch('/admin/orders/:id/pricing', ...adminGuard, handlePricingOrder);

// 🔄 تحديث حالة الطلب للمشرف (المسار المعتمد PATCH /api/orders/:id/status والمتوافق /api/admin/orders/:id/status)
async function handleAdminUpdateStatus(req, res) {
  const orderId = parseOrderId(req.params.id);
  const body = z.object({ status: z.string().trim().min(1) }).parse(req.body);

  const { data: existing, error: fetchErr } = await supabase
    .from('orders')
    .select('id, status, phone, courier_id, assigned_courier')
    .eq('id', orderId)
    .maybeSingle();

  if (fetchErr) throw fetchErr;
  if (!existing) fail(404, 'الطلب غير موجود.');

  if (!canTransitionStatus(existing.status, body.status)) {
    fail(
      400,
      `لا يمكن الانتقال من الحالة (${existing.status}) إلى (${body.status}).`
    );
  }

  const { data, error } = await supabase
    .from('orders')
    .update({
      status: body.status,
      updated_at: new Date().toISOString(),
    })
    .eq('id', orderId)
    .select()
    .single();

  if (error) throw error;

  await recordStatusHistory({
    orderId,
    oldStatus: existing.status,
    newStatus: body.status,
    changedBy: req.user?.id || 'admin',
  });

  if (existing.phone) {
    const { data: cust } = await supabase
      .from('customers')
      .select('onesignal_player_id')
      .eq('phone', normalizePhone(existing.phone))
      .maybeSingle();
    if (cust?.onesignal_player_id) {
      await sendOneSignalNotification({
        targetPlayerIds: [cust.onesignal_player_id],
        title: 'تحديث حالة الطلب 📦',
        body: `تم تحديث حالة الطلب #${orderId} إلى: ${body.status}`,
        dataPayload: { order_id: orderId, status: body.status },
      });
    }
  }

  res.json({ order: data, message: 'تم تحديث الحالة بنجاح' });
}

api.patch('/orders/:id/status', ...authGuard, async (req, res, next) => {
  if (req.userRole === 'admin') {
    return handleAdminUpdateStatus(req, res).catch(next);
  }
  if (req.userRole === 'courier') {
    return handleCourierUpdateStatus(req, res).catch(next);
  }
  return fail(403, 'غير مصرح لك بتحديث حالة الطلب.');
});

api.patch('/admin/orders/:id/status', ...adminGuard, handleAdminUpdateStatus);

// ✅ إجراء العميل على الطلب (تأكيد السعر أو إلغاء الطلب)
api.post('/orders/:id/customer-action', ...customerGuard, async (req, res) => {
  const orderId = parseOrderId(req.params.id);
  const body = z
    .object({
      action: z.enum(['approve', 'cancel']),
    })
    .parse(req.body);

  const { data: existing, error: fetchErr } = await supabase
    .from('orders')
    .select('id, phone, status, courier_id, assigned_courier')
    .eq('id', orderId)
    .maybeSingle();

  if (fetchErr) throw fetchErr;
  if (!existing) fail(404, 'الطلب غير موجود.');

  const requesterPhone = normalizePhone(req.userProfile?.phone || '');
  const orderPhone = normalizePhone(existing.phone || '');
  if (!requesterPhone || !orderPhone || orderPhone !== requesterPhone) {
    fail(403, 'هذا الطلب لا يخص حسابك.');
  }

  const nextStatus =
    body.action === 'approve' ? 'waitingCourierApproval' : 'cancelledByCustomer';
  const adminMessage =
    body.action === 'approve'
      ? 'تم تأكيد السعر من قبل العميل، بانتظار موافقة المندوب ✅'
      : 'تم إلغاء الطلب من قبل العميل ❌';

  if (!canTransitionStatus(existing.status, nextStatus)) {
    fail(
      400,
      `لا يمكن تنفيذ الإجراء على الطلب في حالته الحالية (${existing.status}).`
    );
  }

  const { data, error } = await supabase
    .from('orders')
    .update({
      status: nextStatus,
      admin_message: adminMessage,
      updated_at: new Date().toISOString(),
    })
    .eq('id', orderId)
    .select()
    .single();

  if (error) throw error;

  await recordStatusHistory({
    orderId,
    oldStatus: existing.status,
    newStatus: nextStatus,
    changedBy: req.user?.id || requesterPhone || 'customer',
  });

  if (body.action === 'approve' && existing.courier_id) {
    const { data: courierRow } = await supabase
      .from('couriers')
      .select('onesignal_player_id')
      .eq('id', existing.courier_id)
      .maybeSingle();
    if (courierRow?.onesignal_player_id) {
      await sendOneSignalNotification({
        targetPlayerIds: [courierRow.onesignal_player_id],
        title: 'طلب بانتظار موافقتك 🛵',
        body: `وافق العميل على الطلب #${orderId}، يرجى مراجعة الطلب.`,
        dataPayload: { order_id: orderId, status: nextStatus },
      });
    }
  }

  res.json({ order: data });
});

// 🛵 طلبات المندوب المسندة إليه
api.get('/courier/orders', ...courierGuard, async (req, res) => {
  const courierId =
    req.userProfile?.id !== undefined ? String(req.userProfile.id).trim() : '';
  const courierName = String(req.userProfile?.name || '').trim();
  if (!courierId && !courierName) return res.json({ orders: [] });

  let query = supabase
    .from('orders')
    .select('*, order_items(*)')
    .order('created_at', { ascending: false });

  if (courierId && courierName) {
    query = query.or(
      `courier_id.eq.${courierId},assigned_courier.eq.${courierName}`
    );
  } else if (courierId) {
    query = query.eq('courier_id', courierId);
  } else {
    query = query.eq('assigned_courier', courierName);
  }

  const { data, error } = await query;
  if (error) throw error;
  res.json({ orders: data || [] });
});

// 🛵 المندوب: تحديث حالة الطلب المسند إليه فقط
async function handleCourierUpdateStatus(req, res) {
  const orderId = parseOrderId(req.params.id);
  const body = z
    .object({
      status: z.enum([
        'acceptedByCourier',
        'rejectedByCourier',
        'onTheWay',
        'arrivedToCustomer',
        'delivered',
        'cancelled',
      ]),
    })
    .parse(req.body);

  const { data: existing, error: fetchErr } = await supabase
    .from('orders')
    .select('id, status, phone, courier_id, assigned_courier')
    .eq('id', orderId)
    .maybeSingle();

  if (fetchErr) throw fetchErr;
  if (!existing) fail(404, 'الطلب غير موجود.');

  if (!isOrderAssignedToCourier(existing, req.userProfile)) {
    fail(403, 'هذا الطلب غير مسند إلى حسابك.');
  }

  if (!canTransitionStatus(existing.status, body.status)) {
    fail(
      400,
      `انتقال غير مسموح من الحالة (${existing.status}) إلى (${body.status}).`
    );
  }

  const updatePayload = {
    status: body.status,
    updated_at: new Date().toISOString(),
  };

  if (body.status === 'delivered') {
    updatePayload.payment_status = 'paid';
    updatePayload.cash_collected_at = new Date().toISOString();
    if (req.user?.id) {
      updatePayload.cash_collected_by = req.user.id;
    }
  }

  const { data, error } = await supabase
    .from('orders')
    .update(updatePayload)
    .eq('id', orderId)
    .select()
    .single();

  if (error) throw error;

  await recordStatusHistory({
    orderId,
    oldStatus: existing.status,
    newStatus: body.status,
    changedBy: req.user?.id || String(req.userProfile?.id || 'courier'),
  });

  if (existing.phone) {
    const { data: cust } = await supabase
      .from('customers')
      .select('onesignal_player_id')
      .eq('phone', normalizePhone(existing.phone))
      .maybeSingle();
    if (cust?.onesignal_player_id) {
      await sendOneSignalNotification({
        targetPlayerIds: [cust.onesignal_player_id],
        title: 'تحديث حالة التوصيل 🛵',
        body: `حالة الطلب #${orderId} الآن: ${body.status}`,
        dataPayload: { order_id: orderId, status: body.status },
      });
    }
  }

  res.json({ order: data, message: 'تم تحديث الحالة بنجاح' });
}

api.patch('/courier/orders/:id/status', ...courierGuard, handleCourierUpdateStatus);

// 📍 المندوب: تحديث الموقع الجغرافي (Upsert على courier_id الفريد)
api.post('/courier/location', ...courierGuard, async (req, res) => {
  const body = z
    .object({
      latitude: z.number().min(-90).max(90),
      longitude: z.number().min(-180).max(180),
      courier_id: z.string().trim().optional(),
    })
    .parse(req.body);

  const authenticatedCourierId =
    req.userProfile?.id !== undefined && req.userProfile?.id !== null
      ? String(req.userProfile.id).trim()
      : '';
  if (!authenticatedCourierId) {
    fail(401, 'حساب المندوب غير محدد.');
  }

  if (body.courier_id && body.courier_id !== authenticatedCourierId) {
    fail(403, 'لا يمكنك تحديث موقع مندوب آخر.');
  }

  const { data, error } = await supabase
    .from('courier_locations')
    .upsert(
      {
        courier_id: authenticatedCourierId,
        latitude: body.latitude,
        longitude: body.longitude,
        updated_at: new Date().toISOString(),
      },
      { onConflict: 'courier_id' }
    )
    .select()
    .single();

  if (error) throw error;
  res.status(200).json({ location: data });
});

// 📍 جلب موقع المندوب للعميل صاحب الطلب فقط
api.get('/orders/:id/courier-location', ...customerGuard, async (req, res) => {
  const orderId = parseOrderId(req.params.id);

  const { data: order, error: orderErr } = await supabase
    .from('orders')
    .select('id, phone, status, courier_id, assigned_courier')
    .eq('id', orderId)
    .maybeSingle();

  if (orderErr) throw orderErr;
  if (!order) fail(404, 'الطلب غير موجود.');

  const requesterPhone = normalizePhone(req.userProfile?.phone || '');
  const orderPhone = normalizePhone(order.phone || '');
  if (!requesterPhone || requesterPhone !== orderPhone) {
    fail(403, 'غير مصرح لك بالاطلاع على موقع المندوب لهذا الطلب.');
  }

  const activeTrackingStatuses = new Set([
    'acceptedByCourier',
    'assigned',
    'onTheWay',
    'arrivedToCustomer',
  ]);
  if (!activeTrackingStatuses.has(String(order.status || ''))) {
    return res.json({ location: null });
  }

  let targetCourierId = order.courier_id ? String(order.courier_id).trim() : '';
  if (!targetCourierId && order.assigned_courier) {
    const { data: courierRow } = await supabase
      .from('couriers')
      .select('id')
      .eq('name', String(order.assigned_courier).trim())
      .maybeSingle();
    if (courierRow?.id) targetCourierId = String(courierRow.id);
  }

  if (!targetCourierId) {
    return res.json({ location: null });
  }

  const { data: loc, error: locErr } = await supabase
    .from('courier_locations')
    .select('courier_id, latitude, longitude, updated_at')
    .eq('courier_id', targetCourierId)
    .maybeSingle();

  if (locErr) throw locErr;
  res.json({ location: loc || null });
});

export const errorHandler = (error, _req, res, _next) => {
  if (error instanceof z.ZodError) {
    return res.status(400).json({
      error: 'البيانات المرسلة غير مكتملة أو غير صحيحة.',
      details: error.issues.map((issue) => ({
        field: issue.path.join('.'),
        message: issue.message,
      })),
    });
  }
  const status = Number.isInteger(error.status) ? error.status : 500;
  if (status >= 500) console.error(error);
  return res.status(status).json({
    error: status >= 500 ? 'حدث خطأ داخلي في الخادم.' : error.message,
  });
};
