# إعداد Android والبناء والنشر على Google Play

## الإصدارات المعتمدة في هذه الحزمة

- Android Gradle Plugin: `8.10.1`
- Gradle Wrapper: `8.14`
- Kotlin Gradle Plugin: `2.2.20`
- Google Services Gradle Plugin: `4.5.0`
- Java: `17` أو أحدث متوافق
- `compileSdk`: `36`
- `targetSdk`: `36`
- الحد الأدنى: `max(قيمة Flutter، 23)`

استخدم Flutter stable حديثاً (يفضل `3.38` أو أحدث) وثبّت Android SDK Platform 36 وBuild Tools من Android Studio > SDK Manager.

## أول تشغيل على جهازك

من مجلد المشروع `Fast` نفّذ:

```bash
flutter doctor -v
flutter clean
flutter pub get
flutter analyze
flutter test
```

ملف `android/local.properties` لا يُضمّن في الحزمة لأنه خاص بمسارات جهازك. ينشئه Flutter عادةً عند تشغيل أوامر Flutter، أو يمكن تعريف `flutter.sdk` و`sdk.dir` فيه يدوياً. لا تنسخ مسار SDK من جهاز آخر.

## إنشاء مفتاح رفع Google Play

أنشئ مفتاح رفع خاصاً بك، واحتفظ بنسخة احتياطية منه في مكان آمن:

```bash
keytool -genkeypair -v -keystore android/upload-keystore.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000
```

انسخ `android/key.properties.example` إلى `android/key.properties`، ثم اكتب كلمة المرور واسم المفتاح والمسار الصحيح. لا تشارك ملف keystore أو كلمات مروره.

يمكن بدلاً من ذلك ضبط متغيرات Codemagic التالية: `CM_KEYSTORE_PATH`, `CM_KEYSTORE_PASSWORD`, `CM_KEY_ALIAS`, `CM_KEY_PASSWORD`.

## إنشاء ملف Google Play AAB

بعد إعداد مفتاح الرفع:

```bash
flutter build appbundle --release
```

الناتج:

`build/app/outputs/bundle/release/app-release.aab`

إذا لم تضبط مفتاح الرفع، فسيستخدم بناء release مفتاح debug للاختبار فقط، وسيظهر تحذير واضح؛ لا ترفع هذه النسخة إلى Google Play.

## تنبيه بشأن معرّف التطبيق

المعرّف الفعلي في إعداد Android هو `com.maeen.fastdelivery`، وهو المطابق لعميل Android الموجود في `app/google-services.json`. أما `namespace` فهو `com.example.taiz_express` لأنه يطابق حزمة `MainActivity.kt`. قبل أول نشر، تأكد أن `com.maeen.fastdelivery` هو المعرّف الذي تريد حجزه في Play Console. بعد نشر التطبيق لا يمكن تغيير `applicationId` للتحديثات.

## صلاحية الموقع في الخلفية

يحتوي Manifest على `ACCESS_BACKGROUND_LOCATION`. لا تُبقِ هذه الصلاحية في الإصدار النهائي إلا إذا كان تتبع الموقع في الخلفية ميزة أساسية ومفعّلة فعلاً، مع الإفصاح الواضح وطلب الموافقة وتعبئة نموذج Google Play الخاص بالموقع في الخلفية. راجع سلوك التطبيق الفعلي قبل الإرسال.
