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
  yangi `final List<String> _subjectsCompleted = []` state qo'shiladi (fan
  yakunlanganda to'ldiriladi); `pushReplacement('/diagnostic_finished')`ning
  ikkita LITERAL yozilish joyiga (proctoring `onTerminated`, ~satr 196; va
  umumiy `_finishTest()` helper ichida, ~satr 243) `extra: {'studentName':
  widget.studentName, 'subjectsCompleted': _subjectsCompleted}` qo'shiladi.
  `_finishTest()`ning o'zi 3 xil yo'ldan (countdown-timeout ~169, `_submit()`
  finished tarmog'i ~344, fixed-variant final `finishAttempt` ~451) chaqirilsa
  ham, ~243-qatordagi bitta tahrir barchasini qamrab oladi — faqat 196- va
  243-qatorlar qo'lda tahrirlanadi.
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

`app_router.dart`da — faylning boshqa 24+ route'ida allaqachon ishlatilgan
naqsh bilan bir xil (`extra as Map<String, dynamic>? ?? {}` +
non-nullable key access, masalan `app_router.dart:66,75,85,96,123,135`),
joriy `const DiagnosticFinishedScreen()` registratsiyasi (`app_router.dart:
418-420`) shunga almashtiriladi:

```dart
GoRoute(
  path: '/diagnostic_finished',
  builder: (context, state) {
    final extra = state.extra as Map<String, dynamic>? ?? {};
    return DiagnosticFinishedScreen(
      studentName: extra['studentName'] as String?,
      subjectsCompleted:
          (extra['subjectsCompleted'] as List?)?.cast<String>() ?? const [],
    );
  },
),
```

**`studentName`** — `diagnostic_test_runner_screen.dart`da tayyor holda bor:
`widget.studentName` (required `final String`, satr ~73/90) — ikkala chaqiruv
joyida bevosita shundan olinadi.

**`subjectsCompleted`** — koddan tasdiqlandi: bunday ro'yxat HOZIR MAVJUD
EMAS. Runner faqat bitta `_currentSubject` (`String`, satr ~115) saqlaydi va
har `_startSubject()` chaqirilganda uni ustiga yozadi (satr ~284) — fanlar
orasida akkumulyatsiya qiluvchi hech narsa yo'q. Shuning uchun bu — YANGI
holat: `final List<String> _subjectsCompleted = [];` runner state'ga
qo'shiladi va **faqat** `finished == true && nextSubject.isNotEmpty` tarmog'ida
(`_submit()` ichida, hozirgi fan navbatga qo'yilganda, ~satr 347-358) shu fan
ro'yxatga qo'shiladi.

Muhim: test countdown-timeout (`_finishTest()` chaqiruvi timer orqali, ~satr
169) yoki proctoring-terminatsiya (~satr 196) orqali TO'XTATILGANDA, joriy fan
"tugallangan" deb hisoblanmaydi — u ro'yxatga QO'SHILMAYDI. Demak
`subjectsCompleted` ko'pincha bo'sh `[]` yoki to'liqsiz bo'lishi — bu xato
emas, dizayn bo'yicha kutilgan holat (shuning uchun ekran bu ro'yxatsiz ham
to'liq ishlashi SHART — pastdagi pill shunga ko'ra shartli ko'rsatiladi).
`studentName` `null`/bo'sh bo'lsa ham ekran neytral "Barakalla!" sarlavhasini
ko'rsatadi.

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

`result_screen.dart:694-726` (`_Particle`) va `:728-766` (`_ConfettiPainter`)
hozircha **konfiguratsiyalanmaydi** — ranglar `_Particle` ichidagi
`static const _colors`ga qattiq yozilgan, zarrachalar soni (`80`) esa
`_ResultScreenState.initState()`da (`result_screen.dart:70`,
`List.generate(80, ...)`) qattiq yozilgan; animatsiyani boshqaruvchi
`_celebCtrl` (`AnimationController`) butunlay `_ResultScreenState`ga tegishli
va faqat konfetti uchun ishlatiladi (`:47,73-75,156,186,189` — boshqa hech
narsaga bog'liq emas, shuning uchun ko'chirish xavfsiz).

Bu — haqiqiy refactor, "deyarli o'zgarishsiz ko'chirish" emas:

- `ConfettiBurst extends StatefulWidget` yaratiladi, `_celebCtrl`ni O'ZI
  boshqaradi (o'z `initState`/`dispose`i bilan).
- Konstruktor parametrlari: `particleCount` (default 80, joriy qiymatga mos),
  `colors` (default — joriy `_colors` ro'yxati), **`duration`** (MAJBURIY
  farqlanadigan parametr — `result_screen.dart` joriy holatda 3400ms bir
  martalik burst'ga bog'langan (overlay-dismiss vaqti bilan mos), yangi
  diagnostika ekrani esa ~1.2s so'nishni xohlaydi; `duration` parametrisiz bu
  ikkisi bir xil widget'ni ishlata olmaydi).
- `_Particle`ga `colors` ro'yxati konstruktor/`_reset()` orqali uzatiladi
  (hozir hardcoded).
- `result_screen.dart` shu umumiy widgetni import qilib, `duration: 3400ms,
  particleCount: 80` bilan chaqiradi — **tashqi ko'rinish/vaqtlash
  o'zgarmaydi**, faqat ichki implementatsiya umumiy joyga ko'chadi (DRY).
- Yangi `diagnostic_finished_screen.dart` esa `duration: 1200ms` bilan
  chaqiradi.

### 4. Lokalizatsiya (ARB) — MAJBURIY, e'tibordan chetda qolmasin

Joriy `diagnostic_finished_screen.dart` barcha matnlarni `AppLocalizations`
orqali oladi — real ARB kalitlari allaqachon bor: `lib/l10n/app_uz.arb:32-37`
va `lib/l10n/app_ru.arb:32-37` (`diagnosticFinishedTitle`,
`diagnosticFinishedSubtitle`, `diagnosticFinishedInfoNote`, `backToKioskBtn`,
`autoReturnTimerText`). Bu repo ikki tilli (uz/ru) — Bu spec'dagi barcha yangi
matnlar (yuqoridagi 2-bo'lim: shaxsiylashtirilgan sarlavha `{name}`
interpolatsiyasi bilan, iliqroq subtitle, 3 ta status-pill matni — jumladan
`{count}` bilan, CTA matni, pauza/davom-ettirish va countdown matni) **bare
Uzbek string literal sifatida YOZILMAYDI** — har biri tegishli ICU
placeholder/plural bilan ham `app_uz.arb`ga, ham `app_ru.arb`ga YANGI kalit
sifatida qo'shiladi (masalan `diagnosticFinishedGreeting` `{name}` bilan,
`diagnosticFinishedSubjectsPill` `{count}` bilan `plural` ICU formatida), so'ng
`flutter gen-l10n` ishga tushiriladi. Bu — mavjud ekranning bir tilga
regressiyasini oldini olish uchun MAJBURIY qadam, ixtiyoriy emas.

### 5. AnimationController inventarizatsiyasi — barchasi `dispose()` qilinishi SHART

Joriy ekranda 3 ta `AnimationController` bor va barchasi to'g'ri
`dispose()` qilingan (`diagnostic_finished_screen.dart:57-63`). Yangi dizayn
qo'shadigan barcha controller'lar ham xuddi shunday `dispose()` qilinishi
SHART (bu seansda aynan shu turdagi lifecycle-bug — Timer/Completer race —
allaqachon topilgan va tuzatilgan edi, xuddi shu ehtiyotkorlik animatsiyalarga
ham tegishli):

- Badge "breathe" controller (2.5s, cheksiz takror) — `dispose()`da to'xtatiladi.
- 3 ta yulduz uchun controller(lar) — `Future.delayed`/`Timer` bilan
  boshqarilsa, ekran `dispose` bo'lganda hali kutilayotgan delayed
  callback'lar `mounted` tekshiruvisiz `setState` chaqirmasligi kerak.
- `ConfettiBurst`ning o'z ichki `AnimationController`i — o'zi `StatefulWidget`
  bo'lgani uchun o'z `dispose()`ida o'zi tozalanadi (yuqoridagi 3-bo'limga
  qarang), lekin bu ham ro'yxatda aniq qayd etiladi.
- Countdown `Timer.periodic` — `dispose()`da `cancel()` (allaqachon spec
  ichida yozilgan, shu yerda takror eslatiladi).

### 6. Nima qo'shilmaydi (ataylab qisqartirilgan)

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
