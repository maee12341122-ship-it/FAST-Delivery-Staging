# تقرير مراجعة FAST - نسخة 6 نوفمبر 2026

## ما عُدّل في هذه الحزمة
- إزالة رمز Meta Cloud API المكشوف من تطبيق الهاتف؛ التواصل الآن برسالة `wa.me` يرسلها العميل بنفسه إلى 967775145534. هذا ليس تحققاً من ملكية الرقم.
- إزالة مفتاح OneSignal REST من التطبيق وتعطيل الإرسال المباشر من الهاتف. الإرسال يحتاج خادماً موثوقاً.
- إزالة مفاتيح Google Maps الصلبة من Manifest واستبدالها بمتغير Gradle.
- إزالة قبول كلمة مرور المدير الاحتياطية الثابتة، والتحويل إلى Supabase Auth مع شرط `app_metadata.role=admin`.
- التحويل إلى Supabase Auth للمندوبين، وإنشاء حساب المندوب عبر Edge Function يتحقق من دور المدير ويخزن الدور في app_metadata.
- إصلاح صياغة `whereType` في OrderModel.
- إضافة Edge Functions لإنشاء الطلب برمز متابعة، متابعة الطلب، موافقة العميل/إلغاؤه برمز المتابعة، وتحديث الطلب بواسطة المندوب مع تسجيل تحصيل النقد عند التسليم.
- إضافة ترحيل SQL متوافق مع الجداول اليدوية التي قدمها المستخدم وسياسات RLS.
- توحيد Android applicationId والـ namespace إلى `com.example.taiz_express`، وحذف ملفات Gradle المكررة وملف Firebase الفارغ وlocal.properties المحلي.
- تحسين إعداد Backend حتى لا يستخدم JWT secret أو قاعدة بيانات افتراضية في الإنتاج.

## نتائج الاختبار المتاحة
- اختبارات Node.js: 4/4 ناجحة (`node --test backend/test/domain.test.js`).
- يجب تنفيذ `npm run check` في backend.
- لم يتم تنفيذ Flutter analyze أو بناء APK في بيئة الفحص لعدم توفر Flutter/Dart SDK.
- لم يتم الاتصال بمشروع Supabase الحي؛ يجب تنفيذ الترحيل ونشر Edge Functions وإعداد مستخدم المدير.

## ما لا يزال مطلوباً قبل الإنتاج
1. إلغاء/تدوير مفاتيح Meta وOneSignal وGoogle Maps التي كانت موجودة في النسخة الأصلية؛ إزالتها من ZIP لا تلغي صلاحيتها لدى مزود الخدمة.
2. تشغيل ملف `supabase/migrations/202611060001_fast_security_and_compat.sql` بعد نسخة احتياطية، وفحص وجود أرقام هواتف مكررة قبل الفهرس الفريد.
3. إنشاء مستخدم Auth للمدير وإسناد `app_metadata.role=admin` وفق README_DEPLOY_AR.md. لا تُضمّن كلمة المرور في ملفات المصدر.
4. نشر Edge Functions: `admin-create-courier`, `create-order`, `track-order`, `customer-order-action`, `courier-update-order`.
5. ضبط مفاتيح Google Maps وOneSignal server-side، وإعداد مزود OTP حقيقي إذا أردت التحقق من ملكية الهاتف. حالياً العميل يكمل كضيف غير موثق.
6. إعداد Keystore release في Codemagic. النسخة الموقعة بمفتاح debug للاختبار فقط وليست مناسبة لمتجر Google Play.
7. اختبار كامل على أجهزة فعلية وحسابات عميل/مشرف/مندوب، خصوصاً المحادثات والإشعارات وحالات الطلب وفشل الشبكة.

**الحالة:** نسخة تجهيز واختبار (staging candidate)، وليست إعلاناً عن جاهزية إنتاج أو متجر قبل استكمال البنود أعلاه.
