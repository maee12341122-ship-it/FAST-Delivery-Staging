import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import { config } from './config.js';
import { router, errorHandler } from './routes.js';

const app = express();
app.disable('x-powered-by');

if (config.nodeEnv === 'production') {
  app.set('trust proxy', 1);
}

app.use(helmet());

app.use(
  cors({
    origin(origin, callback) {
      if (!origin || config.corsOrigins.includes(origin)) {
        return callback(null, true);
      }
      const corsError = new Error('CORS origin not allowed');
      corsError.status = 403;
      return callback(corsError);
    },
  })
);

app.use(express.json({ limit: '1mb' }));

app.use(
  rateLimit({
    windowMs: 15 * 60 * 1000,
    limit: 300,
    standardHeaders: 'draft-8',
    legacyHeaders: false,
  })
);

// ربط المسارات الأساسية
app.use(router);

// معالجة المسارات غير الموجودة
app.use((_req, res) => res.status(404).json({ error: 'المسار غير موجود.' }));

// معالجة الأخطاء العامة (بما في ذلك أخطاء CORS)
app.use((err, req, res, next) => {
  if (err && err.message === 'CORS origin not allowed') {
    return res.status(403).json({ error: 'المصدر غير مسموح به (CORS).' });
  }
  return errorHandler(err, req, res, next);
});

const server = app.listen(config.port, () => {
  console.log(`FAST Delivery API listening on port ${config.port} 🚀`);
});

async function shutdown(signal) {
  console.log(`${signal}: shutting down gracefully...`);
  server.close(async () => {
    // نظراً لأن Supabase يعتمد على اتصالات HTTP REST API، فلا داعي لإنهاء Pool تقليدي
    console.log('Server closed successfully.');
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 10_000).unref();
}

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
