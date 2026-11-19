import bcrypt from 'bcryptjs';
import { supabase } from './db.js';

export async function hashPassword(password) {
  return bcrypt.hash(password, 12);
}

export async function verifyPassword(password, passwordHash) {
  return bcrypt.compare(password, passwordHash);
}

// ملاحظة: إنشاء الرمز يتم عبر Supabase Auth، ولكن نبقي الدالة كمتوافقية إن لزم الأمر
export function createToken(_user) {
  return null;
}

function normalizePhone(phone) {
  let clean = String(phone || '').trim().replace(/\s+/g, '');
  if (clean.startsWith('+967')) clean = clean.slice(4);
  else if (clean.startsWith('967')) clean = clean.slice(3);
  if (clean.startsWith('0')) clean = clean.slice(1);
  return clean;
}

async function resolveTrustedRole(user) {
  const metadataRole = user.app_metadata?.role;
  const email = (user.email || '').trim().toLowerCase();
  const phone = normalizePhone(user.phone || user.user_metadata?.phone || '');

  // التحقق من سجل المستخدم في جدول users إن وُجد
  let dbUserRecord = null;
  if (phone) {
    const { data: byPhone } = await supabase
      .from('users')
      .select('id, role, name, phone, username, is_active')
      .eq('phone', phone)
      .maybeSingle();
    dbUserRecord = byPhone;
  }

  if (!dbUserRecord && email && email.endsWith('@courier.fast.local')) {
    const usernamePart = email.split('@')[0];
    const { data: byUsername } = await supabase
      .from('users')
      .select('id, role, name, phone, username, is_active')
      .eq('username', usernamePart)
      .maybeSingle();
    dbUserRecord = byUsername;
  }

  if (dbUserRecord && dbUserRecord.is_active === false) {
    return { errorStatus: 401, errorMessage: 'هذا الحساب موقوف.' };
  }

  // التحقق من صلاحية المشرف دون مقارنة UUID مع admins.id (integer)
  if (metadataRole === 'admin' || dbUserRecord?.role === 'admin') {
    let adminRecord = null;

    if (phone) {
      const { data: adminByPhone } = await supabase
        .from('admins')
        .select('id, username, phone, onesignal_player_id')
        .eq('phone', phone)
        .maybeSingle();
      adminRecord = adminByPhone;
    }

    if (!adminRecord && email) {
      const candidateUsername = email.includes('@') ? email.split('@')[0] : email;
      const { data: adminByUsername } = await supabase
        .from('admins')
        .select('id, username, phone, onesignal_player_id')
        .eq('username', candidateUsername)
        .maybeSingle();
      adminRecord = adminByUsername;
    }

    // السماح بدور المشرف فقط إذا كان مصرحاً به في app_metadata ومرتبطاً بسجل مشرف/مستخدم نشط
    if (metadataRole === 'admin' && (adminRecord || dbUserRecord?.role === 'admin')) {
      return {
        role: 'admin',
        adminRecord: adminRecord || null,
        dbUserRecord: dbUserRecord || null,
      };
    }

    return { errorStatus: 403, errorMessage: 'صلاحية المشرف غير موثقة في النظام.' };
  }

  // التحقق من صلاحية المندوب عبر auth_user_id في جدول couriers
  const { data: courierRecord } = await supabase
    .from('couriers')
    .select('id, name, phone, username, status, is_logged_in, auth_user_id, onesignal_player_id')
    .eq('auth_user_id', user.id)
    .maybeSingle();

  if (courierRecord) {
    if (courierRecord.status === 'disabled') {
      return { errorStatus: 401, errorMessage: 'حساب المندوب موقوف.' };
    }
    return {
      role: 'courier',
      courierRecord,
      dbUserRecord: dbUserRecord || null,
    };
  }

  if (metadataRole === 'courier') {
    return { errorStatus: 403, errorMessage: 'حساب المندوب غير مرتبط بسجل نشط.' };
  }

  // الوضع الافتراضي الآمن: عميل
  return {
    role: 'customer',
    dbUserRecord: dbUserRecord || null,
  };
}

// وسيط التحقق من المصادقة باستخدام Supabase Auth Token الفعلي
export async function authenticate(req, res, next) {
  const header = req.get('authorization') || '';
  const match = header.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    return res.status(401).json({ error: 'يلزم تسجيل الدخول.' });
  }

  try {
    const token = match[1].trim();
    const {
      data: { user },
      error,
    } = await supabase.auth.getUser(token);

    if (error || !user) {
      return res.status(401).json({ error: 'جلسة الدخول غير صالحة أو منتهية.' });
    }

    const resolved = await resolveTrustedRole(user);
    if (resolved.errorStatus) {
      return res.status(resolved.errorStatus).json({ error: resolved.errorMessage });
    }

    req.auth = {
      sub: user.id,
      role: resolved.role,
      email: user.email,
      adminRecord: resolved.adminRecord || null,
      courierRecord: resolved.courierRecord || null,
      dbUserRecord: resolved.dbUserRecord || null,
    };
    req.userRole = resolved.role;
    req.user = user;

    return next();
  } catch (_err) {
    return res.status(401).json({ error: 'حدث خطأ أثناء التحقق من جلسة الدخول.' });
  }
}

export function allowRoles(...roles) {
  return (req, res, next) => {
    const activeRole = req.auth?.role || req.userRole;
    if (!req.auth || !roles.includes(activeRole)) {
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
      if (req.auth.adminRecord) {
        userData = {
          id: req.auth.adminRecord.id,
          auth_user_id: req.auth.sub,
          username: req.auth.adminRecord.username,
          phone: req.auth.adminRecord.phone || null,
          role: 'admin',
        };
      } else {
        userData = {
          id: null,
          auth_user_id: req.auth.sub,
          username: req.auth.dbUserRecord?.username || req.auth.email || 'admin',
          phone: req.auth.dbUserRecord?.phone || null,
          role: 'admin',
        };
      }
    } else if (role === 'courier') {
      const courier = req.auth.courierRecord;
      if (!courier) {
        return res.status(403).json({ error: 'سجل المندوب غير موجود.' });
      }
      if (courier.status === 'disabled') {
        return res.status(401).json({ error: 'حساب المندوب موقوف.' });
      }
      userData = {
        ...courier,
        role: 'courier',
      };
    } else {
      const { data: byId } = await supabase
        .from('customers')
        .select('id, name, phone, address, onesignal_player_id')
        .eq('id', req.auth.sub)
        .maybeSingle();

      userData = byId;

      if (!userData) {
        const cleanPhone = normalizePhone(
          req.auth.dbUserRecord?.phone ||
            req.user?.phone ||
            req.user?.user_metadata?.phone ||
            ''
        );
        if (cleanPhone) {
          const { data: byPhone } = await supabase
            .from('customers')
            .select('id, name, phone, address, onesignal_player_id')
            .eq('phone', cleanPhone)
            .maybeSingle();
          userData = byPhone;
        }
      }

      userData = userData
        ? { ...userData, role: 'customer' }
        : {
            id: req.auth.sub,
            phone: normalizePhone(
              req.auth.dbUserRecord?.phone ||
                req.user?.phone ||
                req.user?.user_metadata?.phone ||
                ''
            ),
            role: 'customer',
          };
    }

    req.userProfile = userData;
    return next();
  } catch (error) {
    return next(error);
  }
}
