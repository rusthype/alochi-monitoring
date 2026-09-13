# Diagnostika "test yakunlandi" ekranini qayta dizayn qilish

## Kontekst

> **TUZATISH (2026-09-14, spec 3-iteratsiya):** Quyidagi tavsif ilgari NOTO'G'RI
> edi — birinchi Explore agent `alochi-monitoring-flutter` repo'ning ASOSIY
> (iflos, boshqa sessiya ishlatayotgan `feat/diagnostic-kiosk-web-test-bridge`)
> checkoutini o'qigan, u esa `origin/main`dagi haqiqiy holatdan ORQADA/farqli
> edi. `origin/main`dan olingan izolyatsiyalangan worktree'dagi haqiqiy faylni
> o'zim to'g'ridan-to'g'ri o'qib chiqqach, ma'lum bo'ldiki ekran allaqachon
> ancha boy: `git log` bo'yicha `feat(diagnostic): animate finished screen with
> celebration + auto-return timer` va `fix(diagnostic): address code review
> findings on finished screen` commitlari orqali oldinroq ishlab chiqilgan.
> Pastdagi "Ko'lam" va "Dizayn" bo'limlari shu HAQIQIY boshlang'ich holatga
> mos qilib qayta yozildi (jumladan alohida "ConfettiBurst extraction from
> result_screen.dart" g'oyasi butunlay OLIB TASHLANDI — sababi pastda).

`DiagnosticFinishedScreen` — diagnostika testi (CAT/adaptive va shu jumladan
runner orqali o'tadigan fixed-variant oqim) tugagach ko'rsatiladigan yakuniy
ekran. **Hozirgi HAQIQIY holati** (`lib/features/diagnostic/screens/
diagnostic_finished_screen.dart`, `lib/features/diagnostic/widgets/
celebration_particles.dart`):

- 3 ta `AnimationController` allaqachon bor va to'g'ri `dispose()` qilingan:
  `_entranceController` (600ms, kirish scale+fade), `_particlesController`
  (4s, cheksiz takror — fon zarralarini boshqaradi), `_pulseController`
  (1200ms, `repeat(reverse: true)` — markaziy ikonkaning "nafas olish"
  scale-effekti, 1.0↔1.08).
- `CelebrationParticles` widget (`lib/features/diagnostic/widgets/
  celebration_particles.dart`) — allaqachon mavjud, ATAYLAB
  `result_screen.dart`dagi `_ConfettiPainter`dan mustaqil qurilgan fon zarra
  animatsiyasi (faylning o'z izohi: *"Deliberately separate from
  result_screen.dart's private _ConfettiPainter (that file is off-limits) —
  static green/blue palette only, no score/percentage input of any kind."*).
  24 ta zarracha, doimiy tushib turadigan (falling) uslub, yashil/ko'k palitra.
- Auto-return `Timer.periodic` — 15 soniya (`_kAutoReturnSeconds`), pauza
  tugmasi YO'Q (faqat `_returnNow()` orqali qo'lda o'tish).
- Markaziy vizual — 84x84 doira, `AppColors.successMuted` fon,
  `Icons.verified_rounded` ikonka (sodda check-belgi, medal/trophy emas).
- Ko'k "ishonch" box (`AppColors.blueMuted`/`blueBorder`/`blueInk`) —
  `l10n.diagnosticFinishedInfoNote` matni bilan — ALLAQACHON bor.
- Sarlavha/subtitle/tugma — barchasi ARB orqali (`diagnosticFinishedTitle`,
  `diagnosticFinishedSubtitle`, `backToKioskBtn`, `autoReturnTimerText`),
  lekin shaxsiylashtirish (`{Ism}`) yo'q — parametrsiz const konstruktor.

**Demak yetishmayotgan narsalar** (bu spec shularga qaratilgan): o'quvchi
ismi bilan shaxsiylashtirish, markaziy vizualning trophy/medal darajasidagi
boyligi (hozir — bitta yassi ikonka), ketma-ket yonuvchi yulduzlar, ball
ko'rsatmaydigan status-pill qatori, va (ixtiyoriy) countdown'ga
pauza/davom-ettirish tugmasi. Foydalanuvchi buni HTML namuna
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

- `lib/features/diagnostic/screens/diagnostic_finished_screen.dart` —
  o'zgartiriladi (TO'LIQ qayta yozilmaydi — mavjud `_entranceController`,
  `_particlesController`, `CelebrationParticles`, auto-return `Timer` va
  ko'k ishonch-box saqlanadi va qayta ishlatiladi; yangi qo'shiladigan: 2
  ta parametr, medal-badge vizuali, yulduzlar qatori, status-pill qatori,
  countdown pauza tugmasi)
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
- `lib/features/diagnostic/widgets/celebration_particles.dart` —
  **O'ZGARTIRILMAYDI**, aynan hozirgi holicha qayta ishlatiladi (pastga
  qarang, nima uchun `result_screen.dart`ga tegilmasligi).

`result_screen.dart`ga UMUMAN TEGILMAYDI — u faylning o'z private
`_ConfettiPainter`si allaqachon "off-limits" deb hujjatlashtirilgan
(`celebration_particles.dart:5-6`), va diagnostika ekrani uchun aynan shu
maqsadda mustaqil `CelebrationParticles` widget allaqachon mavjud. Buni
qayta ishlatish — yangi umumiy widget yaratib ikkalasini birlashtirishdan
ancha kichikroq va xavfsizroq diff (YAGNI: allaqachon bor narsani qayta
qurish shart emas).

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

### 2. Vizual tarkib (yuqoridan pastga) — mavjud elementlar saqlanadi, yangilari qo'shiladi

Fon (`CelebrationParticles`, `_particlesController` bilan) va kirish
animatsiyasi (`_entranceController`) — **o'zgarishsiz saqlanadi**.

1. **Markaziy "medal-badge"** — joriy 84x84 doira+`Icons.verified_rounded`
   o'rniga: 96x96 yumaloq burchakli kvadrat, gradient fon (`AppColors.gold`
   → `amber`), markazda `Icons.emoji_events_rounded`, pastki-o'ng burchakda
   kichik yashil doira ichida oq check-belgi (`Icons.check`,
   `AppColors.success` fon). "Breathe" effekti uchun YANGI controller SHART
   EMAS — mavjud `_pulseController` (1200ms, `repeat(reverse: true)`, hozir
   ham xuddi shu maqsadda ishlatiladi) qayta ishlatiladi, faqat scale
   diapazoni sozlanishi mumkin.
   HTML namunadagi ko'zli/yuzli mascot **ishlatilmaydi** — bu toza,
   "yuzsiz" trophy/medal uslubi.
2. **Ketma-ket 3 ta yulduz** — badge ostida, YANGI qo'shiladi: kichik gap
   bilan, sahifa ochilgach 400ms/800ms/1200ms kechikish bilan birma-bir
   "yonadi" (kulrang outline → to'ldirilgan sariq yulduz, scale-bounce
   `Curves.elasticOut`). `Future.delayed` orqali boshqariladi (pastdagi
   "AnimationController inventarizatsiyasi"ga qarang — `mounted` tekshiruvi
   SHART). Ovozsiz (kiosk sinf muhiti uchun shovqin kerak emas).
3. **Sarlavha** — YANGI, `studentName` bo'lsa: "Barakalla, {Ism}!"; bo'lmasa:
   joriy neytral `l10n.diagnosticFinishedTitle` saqlanadi. Subtitle —
   joriy `l10n.diagnosticFinishedSubtitle` matni saqlanadi (o'zgartirilmaydi,
   qo'shimcha ARB kaliti kerak emas — faqat sarlavha shartli).
4. **Status-pill qatori** (ball YO'Q) — YANGI, 2-3 ta neytral pill, mavjud
   ma'lumotlardan:
   - "✅ Yuborildi" (doim)
   - "📚 {N} ta fan topshirildi" (`subjectsCompleted.length`dan, 0 bo'lsa
     yashiriladi)
   - "🔒 Xavfsiz saqlandi"
5. **Ishonch bildirish qutisi** — joriy ko'k box (`l10n.diagnosticFinishedInfoNote`)
   **o'zgarishsiz saqlanadi**.
6. **CTA tugma** — joriy `ElevatedButton` + `l10n.backToKioskBtn` **saqlanadi**
   (allaqachon `context.go('/')` chaqiradi, `_returnNow()` orqali).
7. **Auto-redirect countdown** — joriy 15 soniyalik `Timer.periodic` va
   `l10n.autoReturnTimerText(_secondsLeft)` matni **saqlanadi**; YANGI
   qo'shiladigan: "To'xtatish/Davom ettirish" matn-tugmasi (`_isPaused` bool
   flag, `Timer.periodic` callback boshida `if (_isPaused) return;` bilan
   — countdown mustaqil `Timer.periodic`ga asoslangani uchun bu yerda
   `Completer` shart emas, `Timer.cancel()` allaqachon to'g'ri ishlaydi,
   `dispose()`da ham saqlanadi).
8. **Konfetti/fon zarralari** — `CelebrationParticles` widget **aynan hozirgi
   holicha, hech qanday o'zgarishsiz** qayta ishlatiladi (yuqoridagi "Ko'lam"
   bo'limiga qarang — `result_screen.dart`ga tegilmaydi).

### 3. Lokalizatsiya (ARB) — MAJBURIY, e'tibordan chetda qolmasin

Joriy `diagnostic_finished_screen.dart` barcha matnlarni `AppLocalizations`
orqali oladi — real ARB kalitlari allaqachon bor: `lib/l10n/app_uz.arb:32-37`
va `lib/l10n/app_ru.arb:32-37` (`diagnosticFinishedTitle`,
`diagnosticFinishedSubtitle`, `diagnosticFinishedInfoNote`, `backToKioskBtn`,
`autoReturnTimerText`) — bular **o'zgartirilmaydi**. Bu repo ikki tilli
(uz/ru). Faqat YANGI qo'shilayotgan matnlar uchun ham `app_uz.arb`ga, ham
`app_ru.arb`ga YANGI kalit qo'shiladi (bare string literal emas):

- `diagnosticFinishedGreeting` — `{name}` placeholder bilan (masalan uz:
  "Barakalla, {name}!").
- `diagnosticFinishedSubjectsPill` — `{count}` bilan, ICU `plural` formatida
  (masalan uz: "{count, plural, =0{Topshirildi} one{{count} ta fan
  topshirildi} other{{count} ta fan topshirildi}}" — uzbekcha grammatikada
  plural farqi yo'q, lekin ICU formatini saqlash kelajakda boshqa tillar
  uchun ham ishlaydi).
- `diagnosticFinishedSubmittedPill`, `diagnosticFinishedSecurePill` —
  oddiy statik matnlar.
- `diagnosticFinishedPauseBtn`, `diagnosticFinishedResumeBtn` —
  countdown pauza/davom-ettirish tugmasi matnlari.

Qo'shilgach `flutter gen-l10n` ishga tushiriladi. Bu — mavjud ekranning bir
tilga regressiyasini oldini olish uchun MAJBURIY qadam, ixtiyoriy emas.

### 4. AnimationController/Timer inventarizatsiyasi — barchasi `dispose()` qilinishi SHART

Joriy ekranda 3 ta `AnimationController` (`_entranceController`,
`_particlesController`, `_pulseController`) va 1 ta `Timer`
(`_autoReturnTimer`) bor, barchasi to'g'ri `dispose()`/`cancel()`
qilingan (`diagnostic_finished_screen.dart:57-63`) — **hech biri
o'zgartirilmaydi/qo'shimcha controller sifatida qayta yaratilmaydi**, faqat
qayta ishlatiladi (masalan `_pulseController` badge breathe uchun ham).
Yagona haqiqiy YANGI holat — 3 ta yulduzning ketma-ket ochilishi
(`Future.delayed` orqali, `Timer`/`AnimationController` shart emas, chunki
bu bir martalik kechikish, takrorlanuvchi emas): har bir `Future.delayed`
callback'i ichida `if (!mounted) return;` tekshiruvi SHART (bu seansda
Timer/Completer race klassidagi lifecycle-bug allaqachon topilgan va
tuzatilgan edi — xuddi shu ehtiyotkorlik shu yerga ham tegishli). Countdown
`Timer.periodic`ning pauza logikasi ham mavjud `dispose()`dagi
`_autoReturnTimer?.cancel()`dan tashqari hech qanday qo'shimcha cleanup
talab qilmaydi (`_isPaused` — oddiy bool, resurs emas).

### 5. Nima qo'shilmaydi (ataylab qisqartirilgan)

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
  bo'lishini, countdown mavjud `_kAutoReturnSeconds` (15) dan boshlanib
  pauza/davom tugmasi ishlashini tekshiradi (`fakeAsync`/`WidgetTester.pump`
  bilan, real `Timer` kutmasdan).
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
