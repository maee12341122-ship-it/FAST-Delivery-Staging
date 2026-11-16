import 'dotenv/config';

// دالة جلب المتغيرات مع توفير قيمة افتراضية لتجنب توقف السيرفر
function getEnv(name, defaultValue = '') {
  const value = process.env[name]?.trim();
  return value || defaultValue;
}

const jwtSecret = getEnv('JWT_SECRET');

export const config = {
  nodeEnv: process.env.NODE_ENV || 'development',
  port: Number(process.env.PORT || 3000),
  // استبدال DATABASE_URL بمتغيرات Supabase الأساسية للاتصال الآمن عبر العميل
  supabaseUrl: getEnv('SUPABASE_URL'),
  supabaseServiceKey: getEnv('SUPABASE_SERVICE_ROLE_KEY'),
  jwtSecret,
  jwtExpiresIn: process.env.JWT_EXPIRES_IN || '12h',
  corsOrigins: (process.env.CORS_ORIGINS || '').split(',').map((x) => x.trim()).filter(Boolean),
  deliveryBaseFee: Number(process.env.DELIVERY_BASE_FEE_YER ?? 500),
  deliveryPerKmFee: Number(process.env.DELIVERY_PER_KM_FEE_YER ?? 100),
};

// التحقق من صحة رقم المنفذ (Port)
if (!Number.isInteger(config.port) || config.port < 1 || config.port > 65535) {
  config.port = 3000;
}

// التحقق من صحة رسوم التوصيل
if (![config.deliveryBaseFee, config.deliveryPerKmFee].every((n) => Number.isInteger(n) && n >= 0)) {
  config.deliveryBaseFee = 500;
  config.deliveryPerKmFee = 100;
}

// قيود وضع الإنتاج (Production Security Checks)
if (config.nodeEnv === 'production') {
  if (!config.supabaseUrl) throw new Error('SUPABASE_URL is required in production.');
  if (!config.supabaseServiceKey) throw new Error('SUPABASE_SERVICE_ROLE_KEY is required in production.');
  if (!config.jwtSecret || config.jwtSecret.length < 32) throw new Error('JWT_SECRET must be at least 32 characters in production.');
  if (!config.corsOrigins.length || config.corsOrigins.includes('*')) throw new Error('Set explicit CORS_ORIGINS in production.');
}
