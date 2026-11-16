import bcrypt from 'bcryptjs';
import { supabase } from './db.js';

export async function hashPassword(password) {
  return bcrypt.hash(password, 12);
}

export async function verifyPassword(password, passwordHash) {
  return bcrypt.compare(password, passwordHash);
}

// ملاحظة: إنشاء الرمز يتم عبر Supabase Auth، ولكن نبقي الدالة كمتوافقية إن لزم الأمر
export function createToken(user) {
  return null;
}

// وسيط التحقق من المصادقة باستخدام Supabase Auth Token الفعلي
export async function authenticate(req, res, next) {
  const header = req.get('authorization') || '';
  const match = header.match(/^Bearer\s+(.+)$/i);
  if (!match) return res.status(401).json({ error: 'يلزم تسجيل الدخول.' });
  
  try {
    const token = match[1];
    const { data: { user }, error } = await supabase.auth.getUser(token);
    
    if (error || !user) {
      return res.status(401).json({ error: 'جلسة الدخول غير صالحة أو منتهية.' });
    }

    // استخراج الدور (Role) من بيانات المستخدم الإضافية
    const role = user.app_metadata?.role || user.user_metadata?.role || 'customer';

    req.auth = {
      sub: user.id,
      role: role,
      email: user.email,
    };
    req.user = user;
    
    return next();
  } catch (err) {
    return res.status(401).json({ error: 'حدث خطأ أثناء التحقق من جلسة الدخول.' });
  }
}

export function allowRoles(...roles) {
  return (req, res, next) => {
    if (!req.auth || !roles.includes(req.auth.role)) {
      return res.status(403).json({ error: 'ليست لديك صلاحية لتنفيذ هذا الإجراء.' });
    }
    return next();
  };
}

// جلب تفاصيل المستخدم من الجداول الحقيقية (admins, couriers, customers) بناءً على الدور
export async function loadUser(req, res, next) {
  try {
    if (!req.auth || !req.auth.sub) {
      return res.status(401).json({ error: 'المستخدم غير مسجل الدخول.' });
    }

    const role = req.auth.role;
    let userData = null;

    if (role === 'admin') {
      const { data } = await supabase
        .from('admins')
        .select('id, username')
        .eq('id', req.auth.sub)
        .maybeSingle();
      userData = data;
    } else if (role === 'courier') {
      const { data } = await supabase
        .from('couriers')
        .select('id, name, phone, status, auth_user_id')
        .eq('auth_user_id', req.auth.sub)
        .maybeSingle();
      
      if (data && data.status === 'disabled') {
        return res.status(401).json({ error: 'حساب المندوب موقوف.' });
      }
      userData = data;
    } else {
      // العملاء
      const { data } = await supabase
        .from('customers')
        .select('id, name, phone, address')
        .eq('id', req.auth.sub)
        .maybeSingle();
      userData = data;
    }

    req.userProfile = userData || { id: req.auth.sub, role: role };
    return next();
  } catch (error) {
    return next(error);
  }
}
