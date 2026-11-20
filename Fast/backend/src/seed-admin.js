import bcrypt from 'bcryptjs';
import { supabase } from './db.js';

const name = process.env.ADMIN_NAME?.trim() || 'Admin';
const username = process.env.ADMIN_USERNAME?.trim();
const password = process.env.ADMIN_PASSWORD;
const phone = process.env.ADMIN_PHONE?.trim() || null;

function normalizePhone(rawPhone) {
  if (!rawPhone) return null;
  let clean = String(rawPhone).trim().replace(/\s+/g, '');
  if (clean.startsWith('+967')) clean = clean.slice(4);
  else if (clean.startsWith('967')) clean = clean.slice(3);
  if (clean.startsWith('0')) clean = clean.slice(1);
  return clean || null;
}

if (!username || !password || password.length < 12) {
  console.error(
    '⚠️ عيّن ADMIN_USERNAME و ADMIN_PASSWORD (12 حرفاً على الأقل) كمتغيرات بيئة قبل إنشاء حساب المشرف.'
  );
  process.exitCode = 1;
} else {
  try {
    const normalizedUsername = username.toLowerCase();
    const normalizedPhone = normalizePhone(phone);
    const email = username.includes('@')
      ? normalizedUsername
      : `${normalizedUsername}@fast.local`;

    // جلب قائمة المستخدمين عبر Supabase Auth Admin API
    const { data: listData, error: listError } =
      await supabase.auth.admin.listUsers();
    if (listError) throw listError;

    const existingUser = (listData?.users || []).find(
      (u) => (u.email || '').toLowerCase() === email
    );

    let authUserId = null;

    if (existingUser) {
      const { data: updatedData, error: updateError } =
        await supabase.auth.admin.updateUserById(existingUser.id, {
          password,
          app_metadata: { role: 'admin' },
          user_metadata: {
            ...(existingUser.user_metadata || {}),
            name,
          },
        });
      if (updateError) throw updateError;
      authUserId = updatedData?.user?.id || existingUser.id;
      console.log('🔄 تم تحديث حساب المشرف القائم في Supabase Auth بنجاح.');
    } else {
      const { data: createdData, error: createError } =
        await supabase.auth.admin.createUser({
          email,
          password,
          email_confirm: true,
          app_metadata: { role: 'admin' },
          user_metadata: { name },
        });
      if (createError) throw createError;
      authUserId = createdData?.user?.id || null;
      console.log('✨ تم إنشاء حساب المشرف الجديد في Supabase Auth بنجاح.');
    }

    // توليد password_hash آمن لجدول admins وجدول users
    const passwordHash = await bcrypt.hash(password, 12);

    // مزامنة جدول admins دون تخزين UUID في عمود id (integer) ودون عمود name
    const { data: existingAdmin, error: fetchAdminError } = await supabase
      .from('admins')
      .select('id, username, phone')
      .eq('username', normalizedUsername)
      .maybeSingle();

    if (fetchAdminError) {
      throw fetchAdminError;
    }

    if (existingAdmin) {
      const adminUpdatePayload = {
        username: normalizedUsername,
        password_hash: passwordHash,
        ...(normalizedPhone ? { phone: normalizedPhone } : {}),
      };

      const { error: adminUpdateError } = await supabase
        .from('admins')
        .update(adminUpdatePayload)
        .eq('id', existingAdmin.id);

      if (adminUpdateError) {
        throw adminUpdateError;
      }
      console.log('🔄 تم تحديث سجل المشرف في جدول admins بنجاح.');
    } else {
      const adminInsertPayload = {
        username: normalizedUsername,
        password_hash: passwordHash,
        ...(normalizedPhone ? { phone: normalizedPhone } : {}),
      };

      const { error: adminInsertError } = await supabase
        .from('admins')
        .insert(adminInsertPayload);

      if (adminInsertError) {
        throw adminInsertError;
      }
      console.log('✨ تم إدراج سجل المشرف في جدول admins بنجاح.');
    }

    // مزامنة سجل المشرف في جدول users إن أمكن لضمان تحقق الأدوار الموثوق
    const { data: existingDbUser, error: fetchUserError } = await supabase
      .from('users')
      .select('id')
      .eq('username', normalizedUsername)
      .maybeSingle();

    if (!fetchUserError) {
      if (existingDbUser) {
        await supabase
          .from('users')
          .update({
            role: 'admin',
            name,
            password_hash: passwordHash,
            is_active: true,
            ...(normalizedPhone ? { phone: normalizedPhone } : {}),
            updated_at: new Date().toISOString(),
          })
          .eq('id', existingDbUser.id);
      } else {
        await supabase.from('users').insert({
          role: 'admin',
          name,
          username: normalizedUsername,
          password_hash: passwordHash,
          is_active: true,
          ...(normalizedPhone ? { phone: normalizedPhone } : {}),
        });
      }
    }

    if (authUserId) {
      console.log('🔐 تم ربط صلاحية المشرف (role: admin) بحساب Auth بنجاح.');
    }
    console.log(
      '🎉 تم إعداد حساب المشرف بالكامل. لا تطبع كلمة المرور ولا تحفظها داخل ملفات المشروع.'
    );
  } catch (error) {
    console.error('❌ تعذر إعداد حساب المشرف:', error.message);
    process.exitCode = 1;
  }
}
