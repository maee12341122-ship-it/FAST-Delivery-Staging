# FAST Delivery Taiz — تجهيز Flutter للبناء

هذه النسخة تحافظ على ملفات `lib` الأصلية، وتضيف ملفات المشروع الأساسية الناقصة لبناء Android APK وFlutter Web.

## الإصدارات

- Flutter: `3.50.0` (Dart `3.14` ضمن هذه السلسلة).
- Java: `17`.
- Android Gradle Plugin: `8.13.2`، وGradle Wrapper: `8.13`.
- Android: `compileSdk/targetSdk` من Flutter، والحد الأدنى يعتمد قيمة Flutter الحالية (API 24 في Flutter 3.50).
- اسم حزمة Dart: `fast` حتى تعمل الاستيرادات الموجودة مثل `package:fast/...`.
- Android applicationId: `com.fast.deliverytaiz`؛ غُيّر/أُنشئ هنا لأن ملفات Android الأصلية لم تكن ضمن الأرشيف.

ثبتُّ إصداراتًا محافظة لبعض الإضافات التي يستعمل كودك واجهاتها القديمة (خصوصًا `share_plus` و`flutter_local_notifications`) حتى لا نضطر لإعادة كتابة الشاشات.

## تشغيل محلي على الكمبيوتر

من مجلد المشروع نفسه (المجلد الذي يحتوي `pubspec.yaml`):

```bash
flutter --version
flutter clean
flutter pub get
flutter build apk --release
flutter build web --release
```

النواتج:

- APK: `build/app/outputs/flutter-apk/app-release.apk`
- Web: محتويات `build/web/`

## GitHub ثم Codemagic

1. أنشئ مستودعًا جديدًا في GitHub.
2. فك ضغط هذه النسخة، ثم ارفع **محتويات مجلد المشروع مباشرة** إلى جذر المستودع؛ يجب أن يظهر `pubspec.yaml` و`codemagic.yaml` في الصفحة الرئيسية للمستودع، وليس داخل مجلد فرعي اسمه `Fast`.
3. افتح Codemagic وسجّل الدخول بحساب GitHub، ثم اختر **Add application** واربط المستودع.
4. اختر Flutter، ثم افحص ملف الإعداد `codemagic.yaml` الموجود في جذر المستودع، واختر workflow باسم `FAST Delivery - APK + Web`.
5. شغّل البناء. بعد اكتماله ستجد APK وملفات الويب ضمن Artifacts في صفحة البناء.
6. لبناء APK تجريبي قابل للتثبيت لا تحتاج إلى keystore؛ الإعداد الحالي يوقّعه بمفتاح debug. للنشر على Google Play، ارفع keystore إنتاجيًا من **Code signing identities** في Codemagic، ثم أضف اسمه المرجعي تحت `environment.android_signing` في `codemagic.yaml`؛ عندها سيستخدم ملف Gradle متغيرات `CM_KEYSTORE_PATH` و`CM_KEYSTORE_PASSWORD` و`CM_KEY_ALIAS` و`CM_KEY_PASSWORD` تلقائيًا. احتفظ بنسخة آمنة من المفتاح ولا ترفعه إلى GitHub.

ملف GitHub Actions الموجود أيضًا سيبني APK والويب عند الدفع إلى `main` أو `master`. إذا كنت تريد Codemagic وحده لتقليل البناء المكرر، عطّل workflow من تبويب Actions أو احذف trigger الدفع.

## خرائط Google (اختياري)

في `delivery_dashboard.dart` توجد شاشة تستخدم `google_maps_flutter`. أضف متغيرًا سريًا باسم `MAPS_API_KEY` في إعدادات البيئة في Codemagic وGitHub Actions، مع تفعيل Maps SDK for Android وMaps JavaScript API في Google Cloud. من دون المفتاح قد لا تظهر خريطة Google، بينما بقية التطبيق يمكن أن تبنى. شاشات `flutter_map` تعتمد على مزود خرائط الإنترنت الخاص بها.

## قاعدة بيانات Supabase المرسلة

تمت مقارنة أسماء الجداول والحقول المستخدمة من Flutter بالمخطط الذي أرسلته. يوجد اعتماد مباشر على الحقل `customers.onesignal_player_id` بينما هذا الحقل غير ظاهر في تعريف جدول `customers` المرفق. أضفت ملف `supabase/COMPATIBILITY_SQL.sql` وفيه إضافة آمنة واحدة باستخدام `IF NOT EXISTS`. نفّذها من Supabase SQL Editor بعد التأكد من نسختك الاحتياطية، ولا تشغّل ملفات SQL أخرى تلقائيًا.

**تنبيه مهم:** الملف الموجود مسبقًا `supabase/migrations/202611060001_fast_security_and_compat.sql` يبدو غير متوافق مع المخطط الذي أرسلته: فهو يتعامل مع `customers.id` كما لو كان رقمًا متسلسلًا، بينما نوعه في مخططك `uuid`، كما يحاول وضع قيمة نصية افتراضية على `orders.id` مع أن نوعه `integer`. لم أعدّل هذا الملف ولم أطبّقه. لا تشغّله على قاعدة بياناتك قبل مراجعته وتصحيح جميع تعارضاته.

يوجد أيضًا `backend/db/schema.sql` وهو تصميم مستقل لخادم Node/PostgreSQL ويختلف عن مخطط Supabase الحالي الذي أرسلته. لا تنفّذه على قاعدة بيانات التطبيق الحالية.

## حدود مهمة قبل الإطلاق

- OneSignal والإشعارات المحلية مهيأة أساسًا لتطبيق Android؛ لا تعتبر إشعارات الويب جاهزة بهذا الإعداد.
- رفع صور المنتجات أصبح يستخدم bytes بدل `dart:io File` حتى لا يمنع تجميع الويب.
- ملف Android أنشئ من الصفر؛ راجع `applicationId` قبل نشر التطبيق رسميًا، ولا تغيّره بعد أول نشر للمستخدمين إلا بخطة ترحيل تطبيق منفصلة.
- APK الافتراضي عندما لا تضبط keystore يوقّع بمفتاح debug لتجربة التثبيت فقط. للنشر عبر Google Play اربط keystore إنتاجي في Codemagic ولا تفقده، لأن تحديث التطبيق يتطلب نفس مفتاح التوقيع.
- هذا التجهيز يعيد ملفات البناء الناقصة ويعالج استيرادين مكسورين؛ لكنه لا يعني أن كل تدفقات قاعدة البيانات والصلاحيات وRLS والإشعارات قد اختُبرت على مشروع Supabase الحي.
