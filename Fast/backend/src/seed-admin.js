import { pool } from './db.js';
import { hashPassword } from './auth.js';

const name = process.env.ADMIN_NAME?.trim();
const username = process.env.ADMIN_USERNAME?.trim();
const password = process.env.ADMIN_PASSWORD;
if (!name || !username || !password || password.length < 12) {
  console.error('عيّن ADMIN_NAME و ADMIN_USERNAME و ADMIN_PASSWORD (12 حرفاً على الأقل) كمتغيرات بيئة قبل إنشاء حساب المشرف.');
  process.exitCode = 1;
} else {
  try {
    const passwordHash = await hashPassword(password);
    await pool.query(
      `INSERT INTO users(role,name,username,password_hash)
       VALUES('admin',$1,$2,$3)
       ON CONFLICT(username) DO UPDATE SET name=EXCLUDED.name,password_hash=EXCLUDED.password_hash,role='admin',is_active=TRUE,updated_at=NOW()`,
      [name, username, passwordHash],
    );
    console.log('تم إعداد حساب المشرف. لا تطبع كلمة المرور ولا تحفظها داخل ملفات المشروع.');
  } catch (error) {
    console.error('تعذر إعداد حساب المشرف:', error.message);
    process.exitCode = 1;
  } finally {
    await pool.end();
  }
}
