import 'dotenv/config';

// دالة جلب المتغيرات مع توفير قيمة افتراضية لتجنب توقف السيرفر
function getEnv(name, defaultValue = '') {
  const value = process.env[name]?.trim();
  return value || defaultValue;
}

function parsePositiveInt(name, defaultValue) {
  const raw = process.env[name];
  if (raw === undefined || String(raw).trim() === '') return defaultValue;
  const parsed = Number.parseInt(String(raw).trim(), 10);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : defaultValue;
}

const parsedPort = Number.parseInt(String(process.env.PORT ?? '3000').trim(), 10);
const parsedBaseFee = Number(process.env.DELIVERY_BASE_FEE_YER ?? 500);
const parsedPerKmFee = Number(process.env.DELIVERY_PER_KM_FEE_YER ?? 100);

export const config = {
  nodeEnv: getEnv('NODE_ENV', 'development'),
  port: Number.isInteger(parsedPort) && parsedPort >= 1 && parsedPort <= 65535 ? parsedPort : 3000,

  // إعدادات Supabase الأساسية للاتصال الآمن عبر العميل
  supabaseUrl: getEnv('SUPABASE_URL'),
  supabaseServiceKey: getEnv('SUPABASE_SERVICE_ROLE_KEY'),

  // إعدادات اختيارية للتوافق إن لزم الأمر
  jwtSecret: getEnv('JWT_SECRET'),
  jwtExpiresIn: getEnv('JWT_EXPIRES_IN', '12h'),

  // إعدادات CORS والرسوم
  corsOrigins: getEnv('CORS_ORIGINS')
    .split(',')
    .map((x) => x.trim())
    .filter(Boolean),
  deliveryBaseFee:
    Number.isFinite(parsedBaseFee) && parsedBaseFee >= 0 ? parsedBaseFee : 500,
  deliveryPerKmFee:
    Number.isFinite(parsedPerKmFee) && parsedPerKmFee >= 0 ? parsedPerKmFee : 100,

  // إعدادات إشعارات OneSignal في الخادم فقط
  onesignalAppId: getEnv('ONESIGNAL_APP_ID'),
  onesignalApiKey: getEnv('ONESIGNAL_REST_API_KEY'),

  // إعدادات WhatsApp و OTP في الخادم فقط
  whatsappApiUrl: getEnv('WHATSAPP_API_URL'),
  whatsappApiToken: getEnv('WHATSAPP_API_TOKEN'),
  whatsappSenderPhone: getEnv('WHATSAPP_SENDER_PHONE', '967776857316'),
  otpTtlSeconds: parsePositiveInt('OTP_TTL_SECONDS', 300),
  otpMaxAttempts: parsePositiveInt('OTP_MAX_ATTEMPTS', 5),
  otpRateLimitWindowSec: parsePositiveInt('OTP_RATE_LIMIT_WINDOW_SEC', 60),
  otpRateLimitMax: parsePositiveInt('OTP_RATE_LIMIT_MAX', 3),
};

// قيود وضع الإنتاج (Production Security Checks)
if (config.nodeEnv === 'production') {
  if (!config.supabaseUrl) {
    throw new Error('SUPABASE_URL is required in production.');
  }
  if (!config.supabaseServiceKey) {
    throw new Error('SUPABASE_SERVICE_ROLE_KEY is required in production.');
  }
  if (!config.corsOrigins.length || config.corsOrigins.includes('*')) {
    throw new Error('Set explicit CORS_ORIGINS in production.');
  }
}
