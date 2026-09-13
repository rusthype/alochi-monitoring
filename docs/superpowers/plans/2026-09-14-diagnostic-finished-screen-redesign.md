# Diagnostika "test yakunlandi" ekranini qayta dizayn qilish — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `DiagnosticFinishedScreen`ni (diagnostika testi tugagach ko'rinadigan ekran) shaxsiylashtirilgan tabrik, medal-badge, ketma-ket yulduzlar, ball ko'rsatmaydigan status-pill qatori va countdown pauza tugmasi bilan boyitish — ball/foiz hech qachon ko'rsatilmaydi.

**Architecture:** Ikki mustaqil, FAYL DARAJASIDA bir-biriga tegmaydigan track. **Track A (Wiring)** — `app_router.dart`, `diagnostic_test_runner_screen.dart`, ARB fayllar: yangi `studentName`/`subjectsCompleted` ma'lumotini ekranga oldindan KELISHILGAN interfeys orqali yetkazadi. **Track B (Screen)** — `diagnostic_finished_screen.dart`ning o'zi: yangi konstruktor maydonlari + butunlay yangi vizual tarkib, xuddi shu KELISHILGAN interfeysga yozadi. Ikkala track BIR VAQTDA, bir-birini kutmasdan ishlay oladi (interfeys pastda §0da qotirilgan), keyin bitta integratsiya bosqichida birlashtiriladi.

**Tech Stack:** Flutter (Dart), `go_router`, mavjud `AppLocalizations`/ARB, mavjud `AppColors` dizayn tizimi. Yangi paket QO'SHILMAYDI.

**Spec:** `docs/superpowers/specs/2026-09-14-diagnostic-finished-screen-redesign-design.md` (3-marta review qilingan, ✅ Approved — jumladan `result_screen.dart`ga tegilmasligi va mavjud `CelebrationParticles`/animatsiya controller'larni qayta ishlatish qarori).

---

## §0. QOTIRILGAN INTERFEYS (ikkala track ham shunga amal qiladi, boshqacha yozmasin)

```dart
// lib/features/diagnostic/screens/diagnostic_finished_screen.dart
class DiagnosticFinishedScreen extends StatefulWidget {
  const DiagnosticFinishedScreen({
    super.key,
    this.studentName,          // RAW roster ismi, formatlanmagan — Track B
                                // buni formatStudentDisplayName() bilan
                                // formatlaydi, Track A xom holicha uzatadi.
    this.subjectsCompleted = const [],
  });

  final String? studentName;
  final List<String> subjectsCompleted;
}
```

ARB kalitlari (Track A qo'shadi, Track B ishlatadi — nomlar bir xil bo'lishi SHART):
`diagnosticFinishedGreeting` (`{name}`), `diagnosticFinishedSubjectsPill`
(`{count}`), `diagnosticFinishedSubmittedPill`, `diagnosticFinishedSecurePill`,
`diagnosticFinishedPauseBtn`, `diagnosticFinishedResumeBtn`.

---

## TRACK A — Wiring (ARB + router + runner screen)

**Fayllar:**
- Modify: `lib/l10n/app_uz.arb`, `lib/l10n/app_ru.arb`
- Modify: `lib/core/router/app_router.dart:418-420`
- Modify: `lib/features/diagnostic/screens/diagnostic_test_runner_screen.dart`
- Test: `test/features/diagnostic/diagnostic_test_runner_subjects_test.dart` (yangi)

**BU TRACK `diagnostic_finished_screen.dart`ga UMUMAN TEGMAYDI** — faqat
Track B qotirgan §0 interfeysiga ishonib, shunga mos `extra:` yuboradi.

### A1: ARB kalitlarini qo'shish

`lib/l10n/app_uz.arb`da, `"autoReturnTimerText"` blokidan keyin (35-37 qator atrofi) qo'shing — ICU plural EMAS, oddiy `{count}`/`{name}` placeholder (loyihada hech qayerda ICU plural ishlatilmagan, `autoReturnTimerText`ning o'zi ham oddiy `{seconds}: int` pattern, shunga ergashiladi):

```json
  "diagnosticFinishedGreeting": "Barakalla, {name}!",
  "@diagnosticFinishedGreeting": {
    "placeholders": { "name": { "type": "String" } }
  },
  "diagnosticFinishedSubjectsPill": "{count} ta fan topshirildi",
  "@diagnosticFinishedSubjectsPill": {
    "placeholders": { "count": { "type": "int" } }
  },
  "diagnosticFinishedSubmittedPill": "Yuborildi",
  "diagnosticFinishedSecurePill": "Xavfsiz saqlandi",
  "diagnosticFinishedPauseBtn": "To'xtatish",
  "diagnosticFinishedResumeBtn": "Davom ettirish",
```

`lib/l10n/app_ru.arb`da xuddi shu joyga (rus tiliga tarjima bilan, key nomlar bir xil):

```json
  "diagnosticFinishedGreeting": "Молодец, {name}!",
  "@diagnosticFinishedGreeting": {
    "placeholders": { "name": { "type": "String" } }
  },
  "diagnosticFinishedSubjectsPill": "Предметов сдано: {count}",
  "@diagnosticFinishedSubjectsPill": {
    "placeholders": { "count": { "type": "int" } }
  },
  "diagnosticFinishedSubmittedPill": "Отправлено",
  "diagnosticFinishedSecurePill": "Надёжно сохранено",
  "diagnosticFinishedPauseBtn": "Остановить",
  "diagnosticFinishedResumeBtn": "Продолжить",
```

- [ ] Yozing (ikkala faylga)
- [ ] `flutter gen-l10n` ishga tushiring (repo root'da)
- [ ] Tekshiring: `lib/l10n/app_localizations.dart` (generated) yangi getter'larni o'z ichiga oladimi — `grep diagnosticFinishedGreeting lib/l10n/app_localizations*.dart`
- [ ] Commit: `git add lib/l10n/ && git commit -m "feat(diagnostic): add ARB keys for finished-screen personalization"`

### A2: Runner screen — `_subjectsCompleted` state qo'shish

**Fayl:** `lib/features/diagnostic/screens/diagnostic_test_runner_screen.dart`

`_currentSubject` (~115-qator) yonida yangi state maydoni qo'shing:

```dart
  String _currentSubject = '';
  final List<String> _subjectsCompleted = [];   // <-- YANGI
  _SubjectTransition? _transition;
```

Uchta chaqiruv joyida `_finishTest()`dan OLDIN joriy fan ro'yxatga qo'shiladi
(faqat GENUINE tugallanish — countdown-timeout (~169-qator) va proctoring
onTerminated (~196-qator) da QO'SHILMAYDI, chunki u yerda fan yarim qolgan):

1. `_submit()`, fan almashish tarmog'i (~347-358, mavjud kod):
```dart
      if (finished && nextSubject.isNotEmpty) {
        _timer?.cancel();
        _subjectsCompleted.add(_currentSubject);   // <-- YANGI qator
        if (!mounted) return;
```

2. `_submit()`, yakuniy tugallanish tarmog'i (~342-345, mavjud kod):
```dart
      if (finished && nextSubject.isEmpty) {
        _timer?.cancel();
        _subjectsCompleted.add(_currentSubject);   // <-- YANGI qator
        _finishTest();
        return;
      }
```

3. Fixed-variant `_confirmAndFinishPackage()` yakuniy qismi (~450-451, mavjud kod):
```dart
    _timer?.cancel();
    _subjectsCompleted.add(_currentSubject);   // <-- YANGI qator
    _finishTest();
```

- [ ] **Step 1: Yozing (yuqoridagi 4 ta o'zgarish)**
- [ ] **Step 2: `flutter analyze lib/features/diagnostic/screens/diagnostic_test_runner_screen.dart` — 0 xato**

### A3: Runner screen — `extra:` bilan navigatsiya qilish

Ikkita LITERAL `pushReplacement('/diagnostic_finished')` joyiga (§Ko'lam bo'yicha aynan shu ikkitasi, boshqa hech qayerda emas — `_finishTest()`ning o'zi 3 xil yo'ldan chaqirilsa ham, navigatsiya kodi faqat shu 2 joyda yozilgan):

1. `onTerminated` callback (~196-qator):
```dart
    HeartbeatService.instance.onTerminated = () {
      ProctorService.instance.stop();
      HeartbeatService.instance.finishTest();
      if (mounted) {
        context.pushReplacement('/diagnostic_finished', extra: {
          'studentName': widget.studentName,
          'subjectsCompleted': _subjectsCompleted,
        });
      }
    };
```

2. `_finishTest()` (~239-244):
```dart
  void _finishTest() {
    ProctorService.instance.stop();
    HeartbeatService.instance.finishTest();
    if (!mounted) return;
    context.pushReplacement('/diagnostic_finished', extra: {
      'studentName': widget.studentName,
      'subjectsCompleted': _subjectsCompleted,
    });
  }
```

- [ ] **Step 1: Yozing**
- [ ] **Step 2: `flutter analyze` — 0 xato** (E'TIBOR: `DiagnosticFinishedScreen` konstruktori bu vaqtda hali eski — `extra` parametri go_router darajasida `Object?` bo'lgani uchun bu qatorlarning o'zi xato bermaydi; xato faqat Track B qo'shiladigan router builder'da chiqishi mumkin, bu — kutilgan, integratsiya bosqichida hal bo'ladi)

### A4: Router — `/diagnostic_finished` route'ini yangilash

**Fayl:** `lib/core/router/app_router.dart:418-420`

Joriy:
```dart
      GoRoute(
          path: '/diagnostic_finished',
          builder: (context, state) => const DiagnosticFinishedScreen()),
```

Yangisi (faylning o'zida 24+ marta ishlatilgan naqsh bilan bir xil, masalan
`app_router.dart:406-417`dagi qo'shni route'ga qarang):

```dart
      GoRoute(
          path: '/diagnostic_finished',
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return DiagnosticFinishedScreen(
              studentName: extra['studentName'] as String?,
              subjectsCompleted:
                  (extra['subjectsCompleted'] as List?)?.cast<String>() ??
                      const [],
            );
          }),
```

- [ ] **Step 1: Yozing**
- [ ] **Step 2: Commit qilmang hali** — bu integratsiya bosqichigacha kutadi (chunki `DiagnosticFinishedScreen`ning yangi konstruktor maydonlari Track B'da, alohida branch'da yoziladi; shu o'zgarishni alohida commit sifatida saqlab, integratsiya paytida qo'shing — pastdagi "Integratsiya" bo'limiga qarang)

### A5: Runner screen'ning yangi logikasi uchun test

**Fayl (yangi):** `test/features/diagnostic/diagnostic_test_runner_subjects_test.dart`

Runner screen testlari uchun mavjud namunani toping (`grep -rn "DiagnosticTestRunnerScreen(" test/` — override funksiyalar orqali fake API javoblari beriladigan mavjud testlar bor, o'sha patterndan foydalaning). Minimal test:

```dart
// Ikki fanli (masalan math->english) CAT oqimini fake API bilan simulyatsiya
// qiladi, oxirida go_router'ga yuborilgan `extra['subjectsCompleted']`
// ro'yxatida IKKALA fan ham borligini tekshiradi (bitta emas — bu aynan
// A2-qadamda tuzatilgan "oxirgi fan hisobga olinmaydi" xatosining
// regressiyasi).
testWidgets(
  'both subjects appear in subjectsCompleted extra after full CAT completion',
  (tester) async {
    // Arrange: startAttemptOverride/submitAnswerOverride orqali
    // math -> (finished:false, next savol) -> ... -> (finished:true,
    // next_subject:'english') -> english -> (finished:true,
    // next_subject:'') ketma-ketligini simulyatsiya qiling.
    // Act: oxirgi javobni tanlang, submit tugmasini bosing.
    // Assert: navigatsiya '/diagnostic_finished'ga extra bilan
    // ['math', 'english'] ro'yxati bilan sodir bo'lganini tekshiring
    // (go_router test observer yoki mock orqali).
  },
);
```

- [ ] **Step 1: Testni yozing** (mavjud runner-screen test faylidagi fake-API
      override pattern'ini aniq nusxa oling — `grep -rn
      "startAttemptOverride:" test/` bilan toping)
- [ ] **Step 2: Ishga tushiring, muvaffaqiyatli tugashini tekshiring:**
      `flutter test test/features/diagnostic/diagnostic_test_runner_subjects_test.dart`
- [ ] **Step 3: Commit:** `git add lib/features/diagnostic/screens/diagnostic_test_runner_screen.dart test/features/diagnostic/diagnostic_test_runner_subjects_test.dart && git commit -m "feat(diagnostic): track completed subjects and thread student name to finished screen"`

---

## TRACK B — Screen redesign (`diagnostic_finished_screen.dart`)

**Fayllar:**
- Modify: `lib/features/diagnostic/screens/diagnostic_finished_screen.dart` (TO'LIQ)
- Test: `test/features/diagnostic/diagnostic_finished_screen_test.dart` (yangi)

**BU TRACK boshqa hech qanday faylga TEGMAYDI.** §0dagi ARB kalitlari va
konstruktor interfeysi hali Track A'da bo'lmasa ham, ularni MAVJUD deb faraz
qilib yozing (nomlar qotirilgan) — `flutter analyze` integratsiyagacha xato
berishi kutilgan holat.

Joriy fayl (`diagnostic_finished_screen.dart`, 199 qator) mutlaqo ISHLAYDIGAN
kod — `_entranceController`, `_particlesController`, `_pulseController`,
`_autoReturnTimer`, `CelebrationParticles`, ko'k ishonch-box, CTA tugma
BARCHASI SAQLANADI. Faqat quyidagilar o'zgaradi/qo'shiladi.

### B1: Konstruktorga yangi parametrlar qo'shish

```dart
class DiagnosticFinishedScreen extends StatefulWidget {
  const DiagnosticFinishedScreen({
    super.key,
    this.studentName,
    this.subjectsCompleted = const [],
  });

  final String? studentName;
  final List<String> subjectsCompleted;

  @override
  State<DiagnosticFinishedScreen> createState() =>
      _DiagnosticFinishedScreenState();
}
```

Import qo'shing (fayl boshiga, boshqa import'lar bilan):
```dart
import '../../../core/utils/student_name_formatter.dart';
```

- [ ] **Step 1: Yozing**
- [ ] **Step 2: `flutter analyze lib/features/diagnostic/screens/diagnostic_finished_screen.dart`** — ARB getter'lari hali yo'qligi sababli xato ko'rsatishi MUMKIN, bu bosqichda normal (integratsiyada hal bo'ladi); faqat Dart sintaksis xatolarini tekshiring.

### B2: Markaziy vizualni "medal-badge"ga aylantirish

Joriy (97-123 qator atrofidagi) 84x84 doira + `Icons.verified_rounded`ni
almashtiring — mavjud `_pulseController`dan FOYDALANING (yangi controller
YARATMANG):

```dart
                        AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            final scale = 1.0 + (_pulseController.value * 0.06);
                            return Transform.scale(scale: scale, child: child);
                          },
                          child: SizedBox(
                            width: 104,
                            height: 104,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  width: 96,
                                  height: 96,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(28),
                                    gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [AppColors.gold, AppColors.amber],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.amber.withValues(alpha: 0.35),
                                        blurRadius: 24,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.emoji_events_rounded,
                                    color: Colors.white,
                                    size: 52,
                                  ),
                                ),
                                Positioned(
                                  bottom: -4,
                                  right: -4,
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: AppColors.success,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 2.5),
                                    ),
                                    child: const Icon(
                                      Icons.check_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
```

- [ ] **Step 1: Yozing, eski Container+Icon blokini o'chiring**

### B3: Ketma-ket 3 ta yulduz — yangi kichik widget

Xuddi shu faylga (fayl oxiriga, `_DiagnosticFinishedScreenState` klassidan
tashqariga) qo'shing:

```dart
class _SequentialStars extends StatefulWidget {
  const _SequentialStars();

  @override
  State<_SequentialStars> createState() => _SequentialStarsState();
}

class _SequentialStarsState extends State<_SequentialStars> {
  final List<bool> _lit = [false, false, false];

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: 400 + i * 400), () {
        if (!mounted) return;
        setState(() => _lit[i] = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final lit = _lit[i];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: AnimatedScale(
            scale: lit ? 1.0 : 0.8,
            duration: const Duration(milliseconds: 300),
            curve: Curves.elasticOut,
            child: Icon(
              lit ? Icons.star_rounded : Icons.star_outline_rounded,
              size: i == 1 ? 30 : 24,
              color: lit ? AppColors.gold : AppColors.ink3,
            ),
          ),
        );
      }),
    );
  }
}
```

`build()` ichida medal-badge ostiga, sarlavhadan oldin qo'shing:
```dart
                        const SizedBox(height: 12),
                        const _SequentialStars(),
```

- [ ] **Step 1: Yozing**

### B4: Shaxsiylashtirilgan sarlavha

Joriy `Text(l10n.diagnosticFinishedTitle, ...)`ni shartli qilib almashtiring:

```dart
                        Text(
                          (widget.studentName != null &&
                                  widget.studentName!.trim().isNotEmpty)
                              ? l10n.diagnosticFinishedGreeting(
                                  formatStudentDisplayName(widget.studentName!))
                              : l10n.diagnosticFinishedTitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.ink1,
                          ),
                        ),
```

(Subtitle — `l10n.diagnosticFinishedSubtitle` — O'ZGARTIRILMAYDI, o'z holicha qoladi.)

- [ ] **Step 1: Yozing**

### B5: Status-pill qatori

Subtitle bilan ko'k ishonch-box orasiga qo'shing:

```dart
                        const SizedBox(height: 16),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _StatusPill(
                              icon: Icons.check_circle_rounded,
                              label: l10n.diagnosticFinishedSubmittedPill,
                              color: AppColors.success,
                            ),
                            if (widget.subjectsCompleted.isNotEmpty)
                              _StatusPill(
                                icon: Icons.menu_book_rounded,
                                label: l10n.diagnosticFinishedSubjectsPill(
                                    widget.subjectsCompleted.length),
                                color: AppColors.blue,
                              ),
                            _StatusPill(
                              icon: Icons.lock_rounded,
                              label: l10n.diagnosticFinishedSecurePill,
                              color: AppColors.violet,
                            ),
                          ],
                        ),
```

Yangi kichik widget (fayl oxiriga, `_SequentialStars` yonida):
```dart
class _StatusPill extends StatelessWidget {
  const _StatusPill(
      {required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}
```

(`AppColors.blue` va `AppColors.violet` — ikkalasi ham `app_colors.dart:55,49`da tasdiqlangan mavjud tokenlar.)

- [ ] **Step 1: Yozing**

### B6: Countdown'ga pauza/davom-ettirish

`_isPaused` state qo'shing va `Timer.periodic` callback'ini o'zgartiring:

```dart
  bool _isPaused = false;   // <-- YANGI, State klassiga qo'shiladi
```

```dart
    _autoReturnTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isPaused) return;                          // <-- YANGI qator
      if (_secondsLeft <= 1) {
        timer.cancel();
        if (mounted) context.go('/');
        return;
      }
      setState(() => _secondsLeft--);
    });
```

Matn-tugma qo'shing (countdown matni yonida):
```dart
                        const SizedBox(height: 6),
                        TextButton(
                          onPressed: () =>
                              setState(() => _isPaused = !_isPaused),
                          child: Text(_isPaused
                              ? l10n.diagnosticFinishedResumeBtn
                              : l10n.diagnosticFinishedPauseBtn),
                        ),
```

(`dispose()`ga qo'shimcha o'zgarish KERAK EMAS — `_isPaused` oddiy bool,
resurs emas, mavjud `_autoReturnTimer?.cancel()` yetarli.)

- [ ] **Step 1: Yozing**

### B7: Widget test

**Fayl (yangi):** `test/features/diagnostic/diagnostic_finished_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_finished_screen.dart';

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

void main() {
  testWidgets('shows neutral title when studentName is null', (tester) async {
    await tester.pumpWidget(_wrap(const DiagnosticFinishedScreen()));
    await tester.pump();
    final l10n = AppLocalizations.of(
        tester.element(find.byType(DiagnosticFinishedScreen)))!;
    expect(find.text(l10n.diagnosticFinishedTitle), findsOneWidget);
  });

  testWidgets('shows personalized greeting when studentName is set',
      (tester) async {
    await tester.pumpWidget(_wrap(
        const DiagnosticFinishedScreen(studentName: 'ALIYEV VALI OGLI')));
    await tester.pump();
    expect(find.textContaining('Vali'), findsOneWidget); // patronymic stripped
  });

  testWidgets('hides subjects pill when subjectsCompleted is empty',
      (tester) async {
    await tester.pumpWidget(_wrap(const DiagnosticFinishedScreen()));
    await tester.pump();
    expect(find.byIcon(Icons.menu_book_rounded), findsNothing);
  });

  testWidgets('shows subjects pill with count when non-empty', (tester) async {
    await tester.pumpWidget(_wrap(const DiagnosticFinishedScreen(
        subjectsCompleted: ['math', 'english'])));
    await tester.pump();
    expect(find.byIcon(Icons.menu_book_rounded), findsOneWidget);
  });

  testWidgets('pause button toggles to resume label', (tester) async {
    await tester.pumpWidget(_wrap(const DiagnosticFinishedScreen()));
    await tester.pump();
    final l10n = AppLocalizations.of(
        tester.element(find.byType(DiagnosticFinishedScreen)))!;
    expect(find.text(l10n.diagnosticFinishedPauseBtn), findsOneWidget);
    await tester.tap(find.text(l10n.diagnosticFinishedPauseBtn));
    await tester.pump();
    expect(find.text(l10n.diagnosticFinishedResumeBtn), findsOneWidget);
  });
}
```

- [ ] **Step 1: Testlarni yozing**
- [ ] **Step 2: Ishga tushiring:** `flutter test test/features/diagnostic/diagnostic_finished_screen_test.dart` — barchasi PASS
- [ ] **Step 3: `flutter analyze lib/features/diagnostic/screens/diagnostic_finished_screen.dart`** — Track A'ning ARB/konstruktor o'zgarishi hali qo'shilmagani sababli xato bo'lishi MUMKIN (kutilgan)
- [ ] **Step 4: Commit:** `git add lib/features/diagnostic/screens/diagnostic_finished_screen.dart test/features/diagnostic/diagnostic_finished_screen_test.dart && git commit -m "feat(diagnostic): redesign finished screen with medal badge, stars, status pills, countdown pause"`

---

## INTEGRATSIYA (ikkala track tugagach, bitta joyda)

- [ ] **Step 1:** Track A va Track B branch/worktree'larini bitta branch'ga birlashtiring (`git merge` yoki cherry-pick — fayl to'qnashuvi BO'LMASLIGI kerak, chunki ikki track hech qanday umumiy faylga tegmagan, faqat A4-qadamdagi router o'zgarishi alohida saqlab qo'yilgan edi — endi uni ham qo'shing).
- [ ] **Step 2:** `flutter gen-l10n` qayta ishga tushiring (ikkala track ARB'ga tegishi mumkin bo'lgani uchun generated fayl yangilanishi kerak).
- [ ] **Step 3:** `flutter analyze` (butun loyiha) — 0 xato/ogohlantirish.
- [ ] **Step 4:** `flutter test test/features/diagnostic/` — barcha testlar (yangi + mavjud regressiya) PASS.
- [ ] **Step 5:** Qo'lda tekshirish: `flutter run -d macos --release` (DEBUG rejimda tap gesture buzilishi — loyihaning ma'lum muammosi), diagnostika testini oxirigacha o'tib, yangi ekranni ko'ring — `studentName` bor va yo'q ikkala holatda ham.
- [ ] **Step 6:** T1 review (`/code-review high`) — yangi endpoint/auth emas, lekin bir nechta fayl+navigatsiya o'zgargani uchun bir marta o'tish tavsiya etiladi.
- [ ] **Step 7:** Commit + push ishchi branch'ga (`feat/diagnostic-finished-screen-redesign`), foydalanuvchiga hisobot.
