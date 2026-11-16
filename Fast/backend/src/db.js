import { createClient } from '@supabase/supabase-js';
import { config } from './config.js';

if (!config.supabaseUrl || !config.supabaseServiceRoleKey) {
  throw new Error('⚠️ متطلبات الاتصال بـ Supabase (URL أو Service Role Key) غير موجودة في ملفات البيئة.');
}

// إنشاء عميل Supabase للعمليات الخلفية الآمنة في السيرفر
export const supabase = createClient(
  config.supabaseUrl, 
  config.supabaseServiceRoleKey, 
  {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  }
);
