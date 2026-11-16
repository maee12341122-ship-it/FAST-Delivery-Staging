import { createClient } from '@supabase/supabase-js';
import { config } from './config.js';

// التأكد من توفر المتغيرات مطابقة لما في ملف التكوين config.js
const serviceKey = config.supabaseServiceKey;

if (!config.supabaseUrl || !serviceKey) {
  throw new Error('⚠️ متطلبات الاتصال بـ Supabase (URL أو Service Role Key) غير موجودة في ملفات البيئة.');
}

// إنشاء عميل Supabase للعمليات الخلفية الآمنة في السيرفر باستخدام مفتاح الخدمة
export const supabase = createClient(
  config.supabaseUrl, 
  serviceKey, 
  {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  }
);
