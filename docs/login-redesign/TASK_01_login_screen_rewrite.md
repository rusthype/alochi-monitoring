# TASK 01 — Rewrite login_screen.dart layout

**File:** `lib/features/auth/login_screen.dart`
**Sonnet implements. Do not commit — lead agent verifies first.**

## 0. State field addition
In `_LoginScreenState` field block (currently L162–172), add after `String? _error;`:
```dart
bool _expanded = false; // accordion: login form revealed
```

## 1. Keep / Delete / Replace
- KEEP unchanged: imports (L1–13), `checkOnlineWithRetry` (L14–32), `LoginScreen`
  (L34–38), `_Dot/_NetworkPainter/_NetworkBg/_NetworkBgState` (L40–159), state fields
  (L162–172 + new `_expanded`), `_tryAutoLogin/_showForm/_checkOnline/_retryOnlineCheck/_login`
  (L188–310), `_field()` (L686–730), `_statusColor` (L732–735).
- DELETE: `_wideLayout/_narrowLayout/_leftPanel/_circle/_infoRow` (L346–437) and the
  entire `_formPanel()` (L439–684).
- REPLACE: the layout body inside `build()` (the `_wideLayout()/_narrowLayout()` dispatch).
  PRESERVE the auto-login spinner branch and the `CallbackShortcuts` Enter→`_login` wrapper.

## 2. New build() — full code
Replace the existing `build()` (L314–344). Keep the early auto-login spinner exactly as
it is now; only the post-spinner return changes:
```dart
@override
Widget build(BuildContext context) {
  if (_autoLogging) {
    // KEEP the existing auto-logging spinner Scaffold exactly as in current L316–331.
    return const Scaffold(
      backgroundColor: Color(0xFFF5F0E8),
      body: Center(child: CircularProgressIndicator(color: AppColors.brand)),
    );
  }

  return CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.enter): () {
        if (_expanded) _login();
      },
    },
    child: Focus(
      autofocus: true,
      child: Scaffold(
        body: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Color(0xFFF5F0E8))),
            const Positioned.fill(child: _NetworkBg()),
            Positioned.fill(
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Logo in white rounded box
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: AppColors.border),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: .10),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Image.asset('assets/logo.png',
                                  width: 56, height: 56, fit: BoxFit.contain),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text('Alochi Monitoring',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.titleLarge
                                  .copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text("Ta'lim monitoring platformasi",
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodyMedium
                                  .copyWith(color: AppColors.ink2)),
                          const SizedBox(height: 24),
                          _routeButtons(),
                          _accordion(),
                          const SizedBox(height: 16),
                          // Bottom row: sync + history
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SyncImagesButton(),
                              const SizedBox(width: 4),
                              TextButton.icon(
                                onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => const HistoryScreen())),
                                icon: const Icon(Icons.history_rounded, size: 16),
                                label: const Text('Oflayn Tarix'),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.ink2,
                                  textStyle: const TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
```
> If the current auto-logging branch differs in detail, preserve its exact existing
> body — only ensure the non-auto-logging return is the Stack above.

## 3. New `_routeButtons()` — full code
Two equal-width buttons in a Row.
```dart
Widget _routeButtons() {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: _routeButton(
          icon: Icons.monitor_rounded,
          label: 'Alochi Monitoring',
          active: _expanded,
          onTap: () => setState(() => _expanded = !_expanded),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _routeButton(
          icon: Icons.quiz_rounded,
          label: 'Testlar',
          active: false,
          disabled: true,
          badge: 'Tez kunda',
          onTap: null,
        ),
      ),
    ],
  );
}
```

## 4. New `_routeButton(...)` helper — full code
```dart
Widget _routeButton({
  required IconData icon,
  required String label,
  required bool active,
  VoidCallback? onTap,
  bool disabled = false,
  String? badge,
}) {
  final content = AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
    decoration: BoxDecoration(
      color: disabled
          ? AppColors.muted
          : (active ? AppColors.brand : AppColors.surface),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: active ? AppColors.brand : AppColors.border,
        width: active ? 2 : 1,
      ),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon,
            size: 28,
            color: disabled
                ? AppColors.ink3
                : (active ? Colors.white : AppColors.ink2)),
        const SizedBox(height: 10),
        Text(
          label,
          textAlign: TextAlign.center,
          style: AppTextStyles.labelLarge.copyWith(
            fontWeight: FontWeight.w700,
            color: disabled
                ? AppColors.ink3
                : (active ? Colors.white : AppColors.ink1),
          ),
        ),
      ],
    ),
  );

  Widget result = disabled
      ? Opacity(opacity: .6, child: content)
      : GestureDetector(onTap: onTap, child: content);

  if (badge != null) {
    result = Stack(
      clipBehavior: Clip.none,
      children: [
        result,
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.brand,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              badge,
              style: AppTextStyles.caption.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 9.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
  return result;
}
```

## 5. New `_accordion()` — full code
Holds the existing form pieces (status row, fields, error, Kirish, Oddiy kirish).
The primary button KEEPS dynamic online/offline text+icon.
```dart
Widget _accordion() {
  return ClipRect(
    child: AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: !_expanded
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Server status row (reuse existing dot + _statusColor logic)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _checkingOnline
                              ? SizedBox(
                                  width: 10,
                                  height: 10,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: _statusColor))
                              : Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                      shape: BoxShape.circle, color: _statusColor)),
                          const SizedBox(width: 7),
                          Text(_statusMsg,
                              style: AppTextStyles.labelMedium.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: _checkingOnline
                                      ? AppColors.brand
                                      : (_isOnline ? AppColors.ok : AppColors.ink2))),
                          if (!_checkingOnline && !_isOnline) ...[
                            const Spacer(),
                            TextButton(
                              onPressed: _retryOnlineCheck,
                              style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  minimumSize: const Size(0, 0),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap),
                              child: Text('Qayta tekshirish',
                                  style: AppTextStyles.labelMedium
                                      .copyWith(color: AppColors.brand)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('Kirish',
                          style: AppTextStyles.titleMedium
                              .copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text("Login va parolni o'qituvchingizdan oling",
                          style: AppTextStyles.labelMedium
                              .copyWith(color: AppColors.ink2)),
                      const SizedBox(height: 16),
                      _field(
                        controller: _userCtrl,
                        label: 'Login',
                        hint: '',
                        icon: Icons.person_outline_rounded,
                        action: TextInputAction.next,
                        validator: (v) => v!.isEmpty ? 'Login kiriting' : null,
                      ),
                      const SizedBox(height: 14),
                      _field(
                        controller: _passCtrl,
                        label: 'Parol',
                        hint: '',
                        icon: Icons.lock_outline_rounded,
                        obscure: !_showPass,
                        action: TextInputAction.done,
                        onSubmit: (_) => _login(),
                        validator: (v) => v!.isEmpty ? 'Parol kiriting' : null,
                        suffix: IconButton(
                          icon: Icon(
                              _showPass
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 18),
                          onPressed: () => setState(() => _showPass = !_showPass),
                          color: AppColors.ink3,
                        ),
                      ),
                      // Error box (reuse existing AnimatedSize pattern)
                      AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        child: _error == null
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.only(top: 14),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 11),
                                  decoration: BoxDecoration(
                                    color: AppColors.err.withValues(alpha: .07),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color:
                                            AppColors.err.withValues(alpha: .2)),
                                  ),
                                  child: Row(children: [
                                    const Icon(Icons.error_outline_rounded,
                                        color: AppColors.err, size: 16),
                                    const SizedBox(width: 8),
                                    Expanded(
                                        child: Text(_error!,
                                            style: AppTextStyles.labelLarge.copyWith(
                                                color: AppColors.err,
                                                fontWeight: FontWeight.w400))),
                                  ]),
                                ),
                              ),
                      ),
                      const SizedBox(height: 18),
                      // Primary "Kirish" — KEEP dynamic online/offline text+icon
                      SizedBox(
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: _loading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.brand,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13)),
                          ),
                          icon: _loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : Icon(_isOnline
                                  ? Icons.arrow_forward_rounded
                                  : Icons.wifi_off_rounded),
                          label: Text(_isOnline ? 'Kirish' : 'Offline kirish',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 14)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const LocalGradeScreen())),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.ink2,
                            side: const BorderSide(color: AppColors.border),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13)),
                          ),
                          icon: const Icon(Icons.groups_rounded, size: 18),
                          label: const Text('Oddiy kirish (Internet kerak emas)',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    ),
  );
}
```
> Confirm exact constructor/labels for `LocalGradeScreen()`, `HistoryScreen()`,
> `SyncImagesButton()`, `_field(...)`, `_login`, `_retryOnlineCheck`, `_statusColor`,
> `_statusMsg`, `_checkingOnline`, `_isOnline`, `_loading`, `_showPass`, `_userCtrl`,
> `_passCtrl`, `_formKey`, `_error` against the current file before finalizing; reuse
> the current strings/icons verbatim where they exist.

## Verify
- `cd /Users/max/PycharmProjects/AlochiSchool/alochi-monitoring-flutter`
- `flutter analyze` → **0 errors** (warnings about unused old helpers mean a delete was missed).
