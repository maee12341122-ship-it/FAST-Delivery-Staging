import jwt from 'jsonwebtoken';
import bcrypt from 'bcryptjs';
import { config } from './config.js';
import { pool } from './db.js';

export async function hashPassword(password) {
  return bcrypt.hash(password, 12);
}

export async function verifyPassword(password, passwordHash) {
  return bcrypt.compare(password, passwordHash);
}

export function createToken(user) {
  return jwt.sign({ sub: user.id, role: user.role }, config.jwtSecret, { expiresIn: config.jwtExpiresIn });
}

export function authenticate(req, res, next) {
  const header = req.get('authorization') || '';
  const match = header.match(/^Bearer\s+(.+)$/i);
  if (!match) return res.status(401).json({ error: 'يلزم تسجيل الدخول.' });
  try {
    req.auth = jwt.verify(match[1], config.jwtSecret);
    return next();
  } catch {
    return res.status(401).json({ error: 'جلسة الدخول غير صالحة أو منتهية.' });
  }
}

export function allowRoles(...roles) {
  return (req, res, next) => {
    if (!req.auth || !roles.includes(req.auth.role)) return res.status(403).json({ error: 'ليست لديك صلاحية لتنفيذ هذا الإجراء.' });
    return next();
  };
}

export async function loadUser(req, res, next) {
  try {
    const { rows } = await pool.query(
      'SELECT id, role, name, phone, username, is_active FROM users WHERE id = $1',
      [req.auth.sub],
    );
    if (!rows[0] || !rows[0].is_active) return res.status(401).json({ error: 'الحساب غير موجود أو موقوف.' });
    req.user = rows[0];
    req.auth.role = rows[0].role; // Read the current role from the database, not only the token.
    return next();
  } catch (error) {
    return next(error);
  }
}
