# Diagnostika "test yakunlandi" ekranini qayta dizayn qilish

## Kontekst

`DiagnosticFinishedScreen` — diagnostika testi (CAT/adaptive va shu jumladan
runner orqali o'tadigan fixed-variant oqim) tugagach ko'rsatiladigan yakuniy
ekran. Hozirgi holati mutlaqo minimal: doira ichida check-ikonka, sarlavha,
bitta izoh matni va "orqaga" tugmasi — hech qanday animatsiya, shaxsiylashtirish
yoki auto-redirect yo'q. Foydalanuvchi buni HTML namuna
(`~/Downloads/diagnostika_yakunlandi.html` — personallashtirilgan header, 3D
kubok, ketma-ket yulduzlar, konfetti, statistika pill'lari, gradient CTA,
countdown+progress bar) darajasidagi "chiroyli" tajribaga aylantirishni so'radi,
LEKIN namunadagi ko'zli/kulgan-yuzli oltin kubok mascot'ini aynan nusxalashni
emas — o'ziga xos, sodda va zamonaviy markaziy tasvir taklif qilishni so'radi.

Diagnostika — baholash emas, aniqlash (assessment, not grading) vositasi
bo'lgani uchun foydalanuvchi bilan brainstorming davomida qaror qilindi: **aniq
ball/foiz hech qachon ko'rsatilmaydi** — faqat tabrik va neytral holat
ko'rsatkichlari (bu qaror `DiagnosticFinishedScreen` boshidagi mavjud izohga
ham mos: "the results endpoint is staff-only, so no scores are shown here").

## Ko'lam

Faqat `alochi-monitoring-flutter` repo. Backend'ga tegilmaydi (ball
ko'rsatilmagani uchun yangi API maydon kerak emas). Faqat quyidagi fayllar:

- `lib/features/diagnostic/screens/diagnostic_finished_screen.dart` — to'liq
  qayta yoziladi
- `lib/features/diagnostic/screens/diagnostic_test_runner_screen.dart` —
  ikkala `pushReplacement('/diagnostic_finished')` chaqiruviga
  `extra: {'studentName': ..., 'subjectsCompleted': ...}` qo'shiladi
- `lib/core/router/app_router.dart` — `/diagnostic_finished` route'i `extra`ni
  o'qib `DiagnosticFinishedScreen`ga parametr sifatida uzatadi
- Yangi umumiy widget: `lib/shared/widgets/confetti_burst.dart` —
  `lib/features/result/result_screen.dart` dagi `_ConfettiPainter`/`_Particle`
  patternidan chiqarilgan, qayta ishlatiladigan konfetti widget

## Dizayn

### 1. Ma'lumot oqimi (parametrlar)

`DiagnosticFinishedScreen` endi ixtiyoriy parametrlar oladi:

```dart
class DiagnosticFinishedScreen extends StatefulWidget {
  const DiagnosticFinishedScreen({
    super.key,
    this.studentName,
    this.subjectsCompleted = const [],
  });

  final String? studentName;
  final List<String> subjectsCompleted; // masalan ['Matematika', 'Ingliz tili']
}
```

`app_router.dart`da:

```dart
GoRoute(
  path: '/diagnostic_finished',
  builder: (context, state) {
    final extra = state.extra as Map<String, dynamic>?;
    return DiagnosticFinishedScreen(
      studentName: extra?['studentName'] as String?,
      subjectsCompleted:
          (extra?['subjectsCompleted'] as List?)?.cast<String>() ?? const [],
    );
  },
),
```

`diagnostic_test_runner_screen.dart`dagi ikkala chaqiruv joyida (proctoring
`onTerminated` va `_submit()` ichida) `context.pushReplacement(
'/diagnostic_finished', extra: {...})` shu maydonlar bilan to'ldiriladi —
runner screen'da o'quvchi ismi va tugallangan fanlar ro'yxati allaqachon
mavjud state'da bor (`widget.studentName`, `_subjectsCompleted` yoki
ekvivalenti — implementatsiya vaqtida runner screendan aniq nom o'qiladi).
Agar `studentName` `null`/bo'sh bo'lsa, ekran neytral "Barakalla!" sarlavhasini
ko'rsatadi (ism ixtiyoriy, ekran ismsiz ham to'liq ishlashi shart).

### 2. Vizual tarkib (yuqoridan pastga)

1. **Fon** — `AppColors.bg` ustida 2-3 ta statik, yumshoq rangli, blur'langan
   doira (`Container` + `BoxDecoration` + `ImageFilter.blur` yoki oddiy
   past-opacity to'ldirilgan doiralar — animatsiyasiz, arzon).
2. **Markaziy "medal-badge"** — 96x96 yumaloq burchakli kvadrat, gradient fon
   (`AppColors.gold` → `amber`), markazda `Icons.emoji_events_rounded` yoki
   yulduz-lenta shakli (implementatsiya vaqtida ikkalasi ham prototip qilinib,
   ko'zga chiroyliroq ko'ringani tanlanadi), pastki-o'ng burchakda kichik
   yashil doira ichida oq check-belgi (`Icons.check` , `AppColors.success`
   fon). Sekin "breathe" animatsiyasi: `AnimationController` bilan scale
   0.97↔1.03, 2.5s davr, `Curves.easeInOut`, cheksiz takror.
   HTML namunadagi ko'zli/yuzli mascot **ishlatilmaydi** — bu toza,
   "yuzsiz" trophy/medal uslubi.
3. **Ketma-ket 3 ta yulduz** — badge ostida, kichik gap bilan, sahifa
   ochilgach 400ms/800ms/1200ms kechikish bilan birma-bir "yonadi" (kulrang
   outline → to'ldirilgan sariq yulduz, scale-bounce
   `Curves.elasticOut`). Ovozsiz (kiosk sinf muhiti uchun shovqin kerak emas).
4. **Sarlavha** — `studentName` bo'lsa: "Barakalla, {Ism}!"; bo'lmasa:
   "Barakalla!". Pastida izoh: "Diagnostika testi yakunlandi. Natijalaringiz
   xavfsiz yuborildi." (hozirgi matnga yaqin, ohang iliqroq).
5. **Status-pill qatori** (ball YO'Q) — 2-3 ta neytral pill, mavjud
   ma'lumotlardan:
   - "✅ Yuborildi" (doim)
   - "📚 {N} ta fan topshirildi" (`subjectsCompleted.length`dan, 0 bo'lsa
     yashiriladi)
   - "🔒 Xavfsiz saqlandi"
6. **Ishonch bildirish qutisi** — hozirgi ko'k box saqlanadi, faqat
   qayta stilize: "Natijalar maktab ma'muriyati va o'qituvchilar uchun
   tayyorlanmoqda."
7. **CTA tugma** — gradient (`AppColors.secondary` asosida), "Bosh sahifaga
   qaytish", bosilganda darhol `context.go('/')`.
8. **Auto-redirect countdown** — 10 soniya, `Timer.periodic(Duration(seconds:
   1))` + chiziqli progress-bar (`LinearProgressIndicator` yoki maxsus
   `Container`), matn "{n} soniyadan so'ng avtomatik qaytiladi" + "To'xtatish/
   Davom ettirish" matn-tugmasi. `dispose()`da timer albatta `cancel()`
   qilinadi (bu seansda topilgan Timer/Completer race xatosidan saqlanish
   uchun — countdown mustaqil `Timer.periodic`, `Completer` shart emas, chunki
   bu yerda kutilayotgan tashqi Future yo'q, faqat UI-tick).
9. **Konfetti** — ekran ochilgach bir marta (`initState`da) `ConfettiBurst`
   widget orqali otiladi, 1.2s davomida so'nadi.

### 3. `ConfettiBurst` umumiy widget

`result_screen.dart`dagi `_ConfettiPainter`/`_Particle` klasslari deyarli
o'zgarishsiz `lib/shared/widgets/confetti_burst.dart`ga ko'chiriladi (nom:
`ConfettiBurst extends StatefulWidget`, `particleCount`, `colors` parametrli),
so'ng `result_screen.dart` shu umumiy widgetni import qilib ishlatadigan
bo'ladi (kod dublikatsiyasi yo'qoladi — DRY). Bu refactor `result_screen.dart`
ning tashqi ko'rinishini o'zgartirmasligi shart (faqat ichki implementatsiya
umumiy joyga ko'chadi).

### 4. Nima qo'shilmaydi (ataylab qisqartirilgan)

- Ovoz effektlari — sinfda bir nechta kiosk bir vaqtda ishlaganda shovqin
  yaratadi.
- Sichqoncha sparkle-trail va 3D tilt-parallax — web-only effekt, Flutter
  desktop/touch kiosk uchun mos emas, narxi (murakkablik) foydadan yuqori.
- Haqiqiy ball/foiz/to'g'ri-noto'g'ri son — brainstorming qaroriga ko'ra.
- Dark theme — boshqa diagnostika ekranlari ham hozircha faqat light rejimga
  bog'langan, shu konvensiya davom ettiriladi.

## Testlash

- `flutter analyze` — 0 xato/ogohlantirish.
- Yangi widget test: `test/features/diagnostic/diagnostic_finished_screen_test.dart`
  — `studentName` bor/yo'q holatlarini, pill ro'yxati to'g'ri render
  bo'lishini, countdown 10dan boshlanib pauza/davom tugmasi ishlashini
  tekshiradi (`fakeAsync`/`WidgetTester.pump` bilan, real `Timer` kutmasdan).
- `flutter run -d macos --release` orqali qo'lda ko'rish (DEBUG rejimda tap
  gesture buzilishi loyihaning ma'lum muammosi — shuning uchun `--release`).
- Qo'lda: `studentName: null` holatida ekran hali ham to'liq ishlashini
  tekshirish (regression — runner screen har doim ismni yubormasligi mumkin).

## Xavf va chegaralar

- `diagnostic_test_runner_screen.dart` boshqa sessiya tomonidan hozir
  faol o'zgartirilmoqda (branch `feat/diagnostic-kiosk-web-test-bridge`,
  working-tree dirty) — shuning uchun bu ish alohida worktree'da,
  `origin/main`dan boshlab olib boriladi; runner screen'ga qilinadigan
  o'zgarish minimal (faqat `extra:` qo'shish) va merge paytida albatta
  qayta tekshiriladi.
- Fixed-variant oqim qisman tashqi brauzerga (`launchUrl`) chiqib ketishi
  mumkinligi aniqlandi (`hasWebTest`/"Veb-test" yo'li) — bu holatda
  `DiagnosticFinishedScreen` umuman ishlatilmaydi (tashqi sahifa, bu repo
  doirasidan tashqarida). Bu spec faqat runner screen orqali ICHKI o'tadigan
  CAT va native fixed-variant oqimlarga tegishli.
