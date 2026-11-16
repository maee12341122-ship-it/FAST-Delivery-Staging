import { supabase } from './db.js';

const name = process.env.ADMIN_NAME?.trim();
const username = process.env.ADMIN_USERNAME?.trim();
const password = process.env.ADMIN_PASSWORD;

if (!name || !username || !password || password.length < 12) {
  console.error('⚠️ عيّن ADMIN_NAME و ADMIN_USERNAME و ADMIN_PASSWORD (12 حرفاً على الأقل) كمتغيرات بيئة قبل إنشاء حساب المشرف.');
  process.exitCode = 1;
} else {
  try {
    // توحيد نمط البريد الإلكتروني للمشرف المتوافق مع AppState و Auth
    const email = username.includes('@') ? username : `${username.toLowerCase()}@fast.local`;

    // جلب قائمة المستخدمين عبر Supabase Auth Admin API
    const { data: listData, error: listError } = await supabase.auth.admin.listUsers();
    if (listError) throw listError;

    let existingUser = listData.users.find(u => u.email === email);
    let userId;

    if (existingUser) {
      userId = existingUser.id;
      // تحديث كلمة المرور والصلاحيات للمشرف الحالي
      const { error: updateError } = await supabase.auth.admin.updateUserById(userId, {
        password: password,
        app_metadata: { role: 'admin' },
        user_metadata: { name: name }
      });
      if (updateError) throw updateError;
      console.log('🔄 تم تحديث حساب المشرف القائم في Supabase Auth بنجاح.');
    } else {
      // إنشاء حساب مشرف جديد في Supabase Auth
      const { data: createData, error: createError } = await supabase.auth.admin.createUser({
        email: email,
        password: password,
        email_confirm: true,
        app_metadata: { role: 'admin' },
        user_metadata: { name: name }
      });
      if (createError) throw createError;
      userId = createData.user.id;
      console.log('✨ تم إنشاء حساب المشرف الجديد في Supabase Auth بنجاح.');
    }

    // مزامنة البيانات مع جدول admins في قاعدة البيانات
    const { error: adminTableError } = await supabase
      .from('admins')
      .upsert({
        id: userId,
        username: username.toLowerCase(),
        name: name
      }, { onConflict: 'id' });

    if (adminTableError) {
      console.error('⚠️ تحذير: تعذر مزامنة جدول admins:', adminTableError.message);
    } else {
      console.log('✅ تم مزامنة بيانات جدول admins بنجاح.');
    }

    console.log('🎉 تم إعداد حساب المشرف بالكامل. لا تطبع كلمة المرور ولا تحفظها داخل ملفات المشروع.');
  } catch (error) {
    console.error('❌ تعذر إعداد حساب المشرف:', error.message);
    process.exitCode = 1;
  }
}
