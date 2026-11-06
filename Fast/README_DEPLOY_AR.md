# تشغيل وتجهيز FAST قبل النشر

هذه الحزمة **نسخة تجهيز واختبار (Staging)**. لا ترفعها للجمهور أو Google Play قبل تنفيذ جميع الخطوات أدناه وفحصها على جهاز حقيقي.

## 1) ما الذي تغير؟

- توحيد Android `applicationId` و`namespace` إلى `com.example.taiz_express`.
- إزالة ملفات Gradle المكررة وملف Firebase الفارغ و`local.properties` الخاص بجهاز المطور.
- إزالة مفاتيح Meta وOneSignal REST وGoogle Maps التي كانت مكتوبة داخل تطبيق الهاتف. إزالة المفاتيح من المصدر لا تلغيها من حسابات المزودين؛ يجب تدويرها فوراً.
- تسجيل دخول المشرف والمندوب أصبح عبر Supabase Auth مع التحقق من `app_metadata.role`.
- إنشاء المندوب عبر Edge Function محمية بدور المشرف، وليس بإدخال كلمة مرور نصية في جدول `couriers`.
- إضافة Edge Functions لإنشاء الطلب ومتابعته وتأكيد السعر/الإلغاء وتحديث حالة المندوب. رمز متابعة الطلب عشوائي بطول 24 خانة، ويُحفظ Hash فقط في قاعدة البيانات.
- الدفع في هذه المرحلة نقداً عند الاستلام فقط. تأكيد التسليم من المندوب يسجل `payment_status=collected` ووقت التحصيل وهوية المندوب.
- العميل يستطيع الاستمرار كضيف بعد فتح رسالة واتساب الجاهزة إلى FAST. هذا **ليس تحققاً من ملكية رقم الهاتف**.

## 2) حماية بيانات الخدمات المكشوفة

قبل النشر:

1. من Meta for Developers ألغِ رمز الوصول الذي كان موجوداً داخل `app_state.dart` وأنشئ رمزاً جديداً. لا تضع الرمز الجديد في Flutter.
2. من OneSignal ألغِ REST API Key الذي كان موجوداً داخل `notification_service.dart`. لا تضعه في التطبيق. إرسال Push متوقف في نسخة الهاتف حتى إعداد مرسل خادمي آمن.
3. قيّد/دوّر مفتاح Google Maps الذي كان داخل `AndroidManifest.xml`، وقيّده بمعرف Android النهائي وبصمة SHA-1/واجهات API المطلوبة.
4. لا تضع كلمة مرور المدير في ملفات Dart أو SQL أو Git. كلمة المرور التي أُرسلت في المحادثة اعتبرها مكشوفة، واختر كلمة جديدة عند إنشاء حساب Auth.

## 3) قاعدة Supabase الحالية

خذ نسخة احتياطية أولاً، ثم افتح SQL Editor وشغّل الملف:

`supabase/migrations/202611060001_fast_security_and_compat.sql`

هذا الترحيل يفترض الجداول اليدوية التي أرسلت أعمدتها: `couriers`, `customers`, `orders`, `products`, `settings`. لا تشغّل `backend/db/schema.sql` فوق هذه الجداول؛ فهو مخطط معماري آخر مختلف.

قبل الترحيل، افحص تكرار أرقام العملاء لأن الفهرس الفريد يتطلب عدم وجود أرقام مكررة:

```sql
select phone, count(*)
from public.customers
where phone is not null and phone <> ''
group by phone
having count(*) > 1;
```

إذا ظهرت نتائج، عالج التكرار يدوياً قبل تشغيل الترحيل. لا تحذف بيانات العملاء تلقائياً.

بعد الترحيل، يجب ألا توجد سياسات `ALL` بـ `USING (true)` أو `WITH CHECK (true)` على `orders` أو `couriers` أو بقية الجداول الحساسة.

## 4) إنشاء حساب المشرف

1. افتح Supabase Dashboard → Authentication → Users → Add user.
2. أنشئ المستخدم بالبريد `admin@fast.local`، واختر كلمة مرور جديدة قوية بنفسك. لا تضع كلمة المرور داخل هذا المشروع.
3. بعد إنشاء المستخدم، افتح SQL Editor وشغّل:

```sql
update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"role":"admin"}'::jsonb
where email = 'admin@fast.local';
```

4. سجّل الخروج ثم الدخول من التطبيق باسم المستخدم `admin` وكلمة المرور التي عينتها.

يجب أن يكون الدور في `app_metadata` وليس `user_metadata` لأن الصلاحيات تعتمد على بيانات موثوقة من الخادم.

## 5) نشر Supabase Edge Functions

ثبّت Supabase CLI وسجّل الدخول واربط مجلد المشروع بمعرف مشروعك، ثم من مجلد `Fast` نفّذ:

```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase functions deploy admin-create-courier
supabase functions deploy create-order
supabase functions deploy track-order
supabase functions deploy customer-order-action
supabase functions deploy courier-update-order
```

Supabase يحقن `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` تلقائياً في Edge Functions. لا تضع Service Role Key داخل Flutter أو داخل ZIP.

اختبر الوظائف بحسابات منفصلة:
- عميل ضيف: إرسال طلب، استلام رقم الطلب ورمز المتابعة.
- العميل نفسه: الموافقة على السعر أو إلغاء الطلب باستخدام رمز المتابعة المحفوظ على جهازه.
- المشرف: إنشاء مندوب، إضافة منتج، تسعير الطلب وإسناده.
- المندوب: تسجيل الدخول، قبول/رفض الطلب، الوصول، والتسليم مع تسجيل التحصيل النقدي.

## 6) واتساب

رقم FAST المعتمد في التطبيق: `967775145534`.

رابط `wa.me` يفتح محادثة برسالة مجهزة. العميل هو من يضغط إرسال. لا يوجد إرسال تلقائي ولا تحقق من ملكية الرقم ولا استقبال Webhook في هذه النسخة.

## 7) Google Maps وOneSignal

- متغير Android المطلوب لمفتاح الخرائط: `GOOGLE_MAPS_API_KEY` (Gradle project property). لا تضع مفتاحاً غير مقيد في المستودع.
- OneSignal App ID ظاهر في تطبيق الهاتف ويمكن استخدامه لتهيئة SDK، لكنه لا يكفي لإرسال الإشعارات. أضف REST Key كـ Secret في Edge Function/Backend، ثم أنشئ مرسل إشعارات يتحقق من صلاحية الطرف وعلاقته بالطلب قبل الإرسال. الإرسال الحالي متوقف عمداً.
- ملف `google-services.json` حُذف لأنه كان فارغاً. لا تضفه إلا إذا أعددت Firebase فعلياً وتحتاج تكامل FCM المطلوب.

## 8) Backend Node.js المنفصل

الـ Backend الموجود يستخدم PostgreSQL ومخطط `backend/db/schema.sql`، وليس جداول Supabase اليدوية الحالية. لا تشغله على قاعدة Supabase الحالية قبل ترحيل البيانات وتوحيد المخطط.

إذا قررت تشغيله مستقلاً، انسخ `backend/.env.example` إلى `backend/.env` وضع `DATABASE_URL` و`JWT_SECRET` (32 حرفاً عشوائياً على الأقل) و`CORS_ORIGINS` الحقيقي. لا تستخدم `*` في الإنتاج.

## 9) Codemagic وتوقيع Android

- workflow: `fast-taiz-android-apk`.
- `com.example.taiz_express` هو معرف التطبيق الموحد في هذه الحزمة. إذا سبق نشر التطبيق بمعرف مختلف، لا تغيّره؛ يجب استخدام معرف النسخة المنشورة كي تصل التحديثات إلى نفس التطبيق.
- إذا لم تُضف keystore، فنسخة APK تستخدم توقيع Debug للاختبار فقط ولا تصلح لـ Google Play.
- للنشر، أضف Keystore إلى Codemagic وأعد متغيرات البيئة: `CM_KEYSTORE_PATH`, `CM_KEYSTORE_PASSWORD`, `CM_KEY_ALIAS`, `CM_KEY_PASSWORD`. احتفظ بنسخة احتياطية آمنة من ملف التوقيع.
- أضف `GOOGLE_MAPS_API_KEY` كمتغير بيئة/Gradle property في بيئة البناء.

## 10) الفحوصات

من مجلد `backend`:

```bash
npm install
npm test
npm run check
```

ومن جهاز عليه Flutter SDK مطابق لـ `pubspec.yaml`:

```bash
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

لا تعتبر نجاح بناء APK دليلاً كافياً. اختبر إنشاء الطلبات وتحديثها مع RLS مفعّل، وجرّب مستخدم عميل ومشرف ومندوب كلٌّ على جهاز منفصل.

## حدود معروفة يجب إكمالها قبل الإطلاق العام

- OneSignal Push غير مفعّل حتى إعداد مرسل خادمي آمن.
- WhatsApp ليس تحقق OTP؛ التسجيل الحالي يتيح المتابعة كضيف غير موثّق. أضف مزود OTP حقيقياً أو Webhook موثوقاً إذا كان التحقق إلزامياً.
- لا يوجد حالياً تتبع GPS حي للمندوب؛ الخرائط تفتح العنوان فقط حيث تدعم الواجهة ذلك.
- محادثة العميل مع المشرف تحتاج سياسات/وظيفة وسيطة برمز متابعة مثل تحديثات الطلب، ولا تُفتح للـ anon في الترحيل.
- العميل يستطيع استعادة آخر طلب برمز المتابعة على الجهاز نفسه؛ لم تُبنَ شاشة استعادة متعددة الطلبات/الأجهزة.
- قيمة المنتجات المرسلة من جهاز العميل تقديرية ويمكن التلاعب بها؛ على المشرف مراجعة وصف الطلب ومجموع المنتجات قبل تحديد الرسوم. لا تعتمدها محاسبياً قبل ربط تفاصيل السلة بمعرفات المنتجات وأسعارها المحققة من قاعدة البيانات.
- لم يتم بناء APK في بيئة إعداد هذه الحزمة لعدم توفر Flutter SDK هنا.
