import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ru.dart';
import 'app_localizations_uz.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ru'),
    Locale('uz')
  ];

  /// No description provided for @appTitle.
  ///
  /// In uz, this message translates to:
  /// **'Alochi Monitoring'**
  String get appTitle;

  /// No description provided for @loginTitle.
  ///
  /// In uz, this message translates to:
  /// **'Kirish'**
  String get loginTitle;

  /// No description provided for @languageUzbek.
  ///
  /// In uz, this message translates to:
  /// **'O\'zbek'**
  String get languageUzbek;

  /// No description provided for @languageRussian.
  ///
  /// In uz, this message translates to:
  /// **'Русский'**
  String get languageRussian;

  /// No description provided for @bossCreateTitle.
  ///
  /// In uz, this message translates to:
  /// **'Kitobdan test yaratish'**
  String get bossCreateTitle;

  /// No description provided for @logout.
  ///
  /// In uz, this message translates to:
  /// **'Chiqish'**
  String get logout;

  /// No description provided for @serverChecking.
  ///
  /// In uz, this message translates to:
  /// **'Server tekshirilmoqda...'**
  String get serverChecking;

  /// No description provided for @serverConnected.
  ///
  /// In uz, this message translates to:
  /// **'Server bilan ulandi'**
  String get serverConnected;

  /// No description provided for @offlineMode.
  ///
  /// In uz, this message translates to:
  /// **'Offline rejim'**
  String get offlineMode;

  /// No description provided for @invalidCredentials.
  ///
  /// In uz, this message translates to:
  /// **'Login yoki parol noto\'g\'ri'**
  String get invalidCredentials;

  /// No description provided for @tooManyAttempts.
  ///
  /// In uz, this message translates to:
  /// **'Ko\'p urinish. Biroz kuting.'**
  String get tooManyAttempts;

  /// No description provided for @serverErrorRetry.
  ///
  /// In uz, this message translates to:
  /// **'Server xatosi. Qayta urinib ko\'ring.'**
  String get serverErrorRetry;

  /// No description provided for @offlineNoSavedLogin.
  ///
  /// In uz, this message translates to:
  /// **'Internet yo\'q va bu login ilgari saqlanmagan.'**
  String get offlineNoSavedLogin;

  /// No description provided for @connectionError.
  ///
  /// In uz, this message translates to:
  /// **'Ulanishda xatolik'**
  String get connectionError;

  /// No description provided for @loggingIn.
  ///
  /// In uz, this message translates to:
  /// **'Kirish...'**
  String get loggingIn;

  /// No description provided for @appSubtitle.
  ///
  /// In uz, this message translates to:
  /// **'Ta\'lim monitoring platformasi'**
  String get appSubtitle;

  /// No description provided for @testsRoute.
  ///
  /// In uz, this message translates to:
  /// **'Testlar'**
  String get testsRoute;

  /// No description provided for @comingSoon.
  ///
  /// In uz, this message translates to:
  /// **'Tez kunda'**
  String get comingSoon;

  /// No description provided for @retryCheck.
  ///
  /// In uz, this message translates to:
  /// **'Qayta tekshirish'**
  String get retryCheck;

  /// No description provided for @loginInstruction.
  ///
  /// In uz, this message translates to:
  /// **'Login va parolni o\'qituvchingizdan oling'**
  String get loginInstruction;

  /// No description provided for @usernameLabel.
  ///
  /// In uz, this message translates to:
  /// **'Login'**
  String get usernameLabel;

  /// No description provided for @passwordLabel.
  ///
  /// In uz, this message translates to:
  /// **'Parol'**
  String get passwordLabel;

  /// No description provided for @usernameRequired.
  ///
  /// In uz, this message translates to:
  /// **'Login kiriting'**
  String get usernameRequired;

  /// No description provided for @passwordRequired.
  ///
  /// In uz, this message translates to:
  /// **'Parol kiriting'**
  String get passwordRequired;

  /// No description provided for @offlineLogin.
  ///
  /// In uz, this message translates to:
  /// **'Offline kirish'**
  String get offlineLogin;

  /// No description provided for @localGradeEntry.
  ///
  /// In uz, this message translates to:
  /// **'Oddiy kirish (Internet kerak emas)'**
  String get localGradeEntry;

  /// No description provided for @monitoringTestUnit1.
  ///
  /// In uz, this message translates to:
  /// **'Monitoring Test Unit 1'**
  String get monitoringTestUnit1;

  /// No description provided for @offlineHistory.
  ///
  /// In uz, this message translates to:
  /// **'Oflayn Tarix'**
  String get offlineHistory;

  /// No description provided for @selectPdfFirst.
  ///
  /// In uz, this message translates to:
  /// **'Avval PDF fayl tanlang'**
  String get selectPdfFirst;

  /// No description provided for @aiGeneratingMessage.
  ///
  /// In uz, this message translates to:
  /// **'AI savollar yaratmoqda...\nBu 1-2 daqiqa olishi mumkin'**
  String get aiGeneratingMessage;

  /// No description provided for @enterPackageTitle.
  ///
  /// In uz, this message translates to:
  /// **'Paket sarlavhasini kiriting'**
  String get enterPackageTitle;

  /// No description provided for @savingMessage.
  ///
  /// In uz, this message translates to:
  /// **'Saqlanyapti...'**
  String get savingMessage;

  /// No description provided for @backButton.
  ///
  /// In uz, this message translates to:
  /// **'Orqaga'**
  String get backButton;

  /// No description provided for @packageTitleLabel.
  ///
  /// In uz, this message translates to:
  /// **'Paket sarlavhasi'**
  String get packageTitleLabel;

  /// No description provided for @saveAndPublish.
  ///
  /// In uz, this message translates to:
  /// **'Saqlash va nashr etish ({grade}-sinf, {variantCount} variant)'**
  String saveAndPublish(int grade, int variantCount);

  /// No description provided for @questionTextLabel.
  ///
  /// In uz, this message translates to:
  /// **'Savol matni'**
  String get questionTextLabel;

  /// No description provided for @variantLetterLabel.
  ///
  /// In uz, this message translates to:
  /// **'Variant {letter}'**
  String variantLetterLabel(String letter);

  /// No description provided for @aiImagePromptHint.
  ///
  /// In uz, this message translates to:
  /// **'AI rasm taklifi (saqlanmaydi):'**
  String get aiImagePromptHint;

  /// No description provided for @mathSubject.
  ///
  /// In uz, this message translates to:
  /// **'Math'**
  String get mathSubject;

  /// No description provided for @englishSubject.
  ///
  /// In uz, this message translates to:
  /// **'Ingliz'**
  String get englishSubject;

  /// No description provided for @selectPdfBook.
  ///
  /// In uz, this message translates to:
  /// **'PDF kitob tanlang'**
  String get selectPdfBook;

  /// No description provided for @pdfFileHint.
  ///
  /// In uz, this message translates to:
  /// **'.pdf fayl, max 10MB, 50 bet'**
  String get pdfFileHint;

  /// No description provided for @subjectLabel.
  ///
  /// In uz, this message translates to:
  /// **'Fan'**
  String get subjectLabel;

  /// No description provided for @gradeLabel.
  ///
  /// In uz, this message translates to:
  /// **'Sinf'**
  String get gradeLabel;

  /// No description provided for @questionCountLabel.
  ///
  /// In uz, this message translates to:
  /// **'Savollar soni'**
  String get questionCountLabel;

  /// No description provided for @variantCountLabel.
  ///
  /// In uz, this message translates to:
  /// **'Variant soni'**
  String get variantCountLabel;

  /// No description provided for @generateWithAi.
  ///
  /// In uz, this message translates to:
  /// **'AI bilan savollar yaratish'**
  String get generateWithAi;

  /// No description provided for @gradeN.
  ///
  /// In uz, this message translates to:
  /// **'{n}-sinf'**
  String gradeN(int n);

  /// No description provided for @nQuestions.
  ///
  /// In uz, this message translates to:
  /// **'{n} ta savol'**
  String nQuestions(int n);

  /// No description provided for @nVariants.
  ///
  /// In uz, this message translates to:
  /// **'{n} variant'**
  String nVariants(int n);

  /// No description provided for @questionIndex.
  ///
  /// In uz, this message translates to:
  /// **'{index}-savol'**
  String questionIndex(int index);

  /// No description provided for @enterFirstAndLastName.
  ///
  /// In uz, this message translates to:
  /// **'Ism va familiyani kiriting'**
  String get enterFirstAndLastName;

  /// No description provided for @incorrectSecretPassword.
  ///
  /// In uz, this message translates to:
  /// **'Maxfiy parol noto\'g\'ri (Maslahat: 1234)'**
  String get incorrectSecretPassword;

  /// No description provided for @errorPrefix.
  ///
  /// In uz, this message translates to:
  /// **'Xato: {error}'**
  String errorPrefix(String error);

  /// No description provided for @selectVariant.
  ///
  /// In uz, this message translates to:
  /// **'Variantni tanlang'**
  String get selectVariant;

  /// No description provided for @studentInfoTitle.
  ///
  /// In uz, this message translates to:
  /// **'O\'quvchi ma\'lumotlari'**
  String get studentInfoTitle;

  /// No description provided for @localTestInfo.
  ///
  /// In uz, this message translates to:
  /// **'2-sinf Ingliz tili — Interhouse testi\n10 variant · 30 savol · Offline rejim'**
  String get localTestInfo;

  /// No description provided for @continueButton.
  ///
  /// In uz, this message translates to:
  /// **'Davom etish'**
  String get continueButton;

  /// No description provided for @firstNameLabel.
  ///
  /// In uz, this message translates to:
  /// **'Ism'**
  String get firstNameLabel;

  /// No description provided for @firstNameHint.
  ///
  /// In uz, this message translates to:
  /// **'Alisher'**
  String get firstNameHint;

  /// No description provided for @lastNameLabel.
  ///
  /// In uz, this message translates to:
  /// **'Familiya'**
  String get lastNameLabel;

  /// No description provided for @lastNameHint.
  ///
  /// In uz, this message translates to:
  /// **'Karimov'**
  String get lastNameHint;

  /// No description provided for @groupGradeLabel.
  ///
  /// In uz, this message translates to:
  /// **'Guruh / Sinf'**
  String get groupGradeLabel;

  /// No description provided for @groupGradeHint.
  ///
  /// In uz, this message translates to:
  /// **'3-A'**
  String get groupGradeHint;

  /// No description provided for @schoolNameLabel.
  ///
  /// In uz, this message translates to:
  /// **'Maktab nomi'**
  String get schoolNameLabel;

  /// No description provided for @schoolNameHint.
  ///
  /// In uz, this message translates to:
  /// **'12-maktab'**
  String get schoolNameHint;

  /// No description provided for @pinCodeLabel.
  ///
  /// In uz, this message translates to:
  /// **'Parol (PIN kod)'**
  String get pinCodeLabel;

  /// No description provided for @startTest.
  ///
  /// In uz, this message translates to:
  /// **'Testni boshlash'**
  String get startTest;

  /// No description provided for @combinedTestInfo.
  ///
  /// In uz, this message translates to:
  /// **'79 savol · 75 daqiqa · Offline rejim'**
  String get combinedTestInfo;

  /// No description provided for @combinedTestSubjects.
  ///
  /// In uz, this message translates to:
  /// **'30 matematika + 49 ingliz tili'**
  String get combinedTestSubjects;

  /// No description provided for @incorrectPassword.
  ///
  /// In uz, this message translates to:
  /// **'Maxfiy parol noto\'g\'ri'**
  String get incorrectPassword;

  /// No description provided for @confirmLogout.
  ///
  /// In uz, this message translates to:
  /// **'Hisobdan chiqmoqchimisiz?'**
  String get confirmLogout;

  /// No description provided for @cancel.
  ///
  /// In uz, this message translates to:
  /// **'Bekor qilish'**
  String get cancel;

  /// No description provided for @noActiveExamOrExpired.
  ///
  /// In uz, this message translates to:
  /// **'Faol imtihon topilmadi yoki muddati tugagan'**
  String get noActiveExamOrExpired;

  /// No description provided for @loadFailed.
  ///
  /// In uz, this message translates to:
  /// **'Yuklanmadi. Qayta urinib ko\'ring.'**
  String get loadFailed;

  /// No description provided for @gradeClass.
  ///
  /// In uz, this message translates to:
  /// **'{grade}-sinf'**
  String gradeClass(int grade);

  /// No description provided for @variantBadge.
  ///
  /// In uz, this message translates to:
  /// **'Variant {variant}'**
  String variantBadge(int variant);

  /// No description provided for @selectTest.
  ///
  /// In uz, this message translates to:
  /// **'Testni tanlang'**
  String get selectTest;

  /// No description provided for @selectMonitoringTest.
  ///
  /// In uz, this message translates to:
  /// **'Mavjud monitoring testlaridan birini tanlang'**
  String get selectMonitoringTest;

  /// No description provided for @retry.
  ///
  /// In uz, this message translates to:
  /// **'Qayta urinish'**
  String get retry;

  /// No description provided for @noActiveExam.
  ///
  /// In uz, this message translates to:
  /// **'Aktiv imtihon yo\'q'**
  String get noActiveExam;

  /// No description provided for @noExamAssignedOrExpired.
  ///
  /// In uz, this message translates to:
  /// **'Sizga hali imtihon biriktirilmagan\nyoki muddati tugagan'**
  String get noExamAssignedOrExpired;

  /// No description provided for @testsNotLoadedYet.
  ///
  /// In uz, this message translates to:
  /// **'Testlar hali yuklanmagan'**
  String get testsNotLoadedYet;

  /// No description provided for @tryAgainAfterTeacherUploads.
  ///
  /// In uz, this message translates to:
  /// **'O\'qituvchingiz test yuklagandan so\'ng\nqayta urinib ko\'ring'**
  String get tryAgainAfterTeacherUploads;

  /// No description provided for @refresh.
  ///
  /// In uz, this message translates to:
  /// **'Yangilash'**
  String get refresh;

  /// No description provided for @totalLabel.
  ///
  /// In uz, this message translates to:
  /// **'Jami'**
  String get totalLabel;

  /// No description provided for @helloGreeting.
  ///
  /// In uz, this message translates to:
  /// **'Salom!'**
  String get helloGreeting;

  /// No description provided for @mathSubjectFull.
  ///
  /// In uz, this message translates to:
  /// **'Matematika'**
  String get mathSubjectFull;

  /// No description provided for @englishSubjectFull.
  ///
  /// In uz, this message translates to:
  /// **'Ingliz tili'**
  String get englishSubjectFull;

  /// No description provided for @finishConfirmTitle.
  ///
  /// In uz, this message translates to:
  /// **'Tugatish?'**
  String get finishConfirmTitle;

  /// No description provided for @unansweredWarning.
  ///
  /// In uz, this message translates to:
  /// **'{unanswered} ta savol javobsiz qoldi. Shunga qaramay tugatmoqchimisiz?'**
  String unansweredWarning(int unanswered);

  /// No description provided for @mathSectionLabel.
  ///
  /// In uz, this message translates to:
  /// **'Matematika bo\'limi'**
  String get mathSectionLabel;

  /// No description provided for @engSectionLabel.
  ///
  /// In uz, this message translates to:
  /// **'Ingliz tili bo\'limi'**
  String get engSectionLabel;

  /// No description provided for @keyboardButtons.
  ///
  /// In uz, this message translates to:
  /// **'tugmalar'**
  String get keyboardButtons;

  /// No description provided for @previousButton.
  ///
  /// In uz, this message translates to:
  /// **'Oldingi'**
  String get previousButton;

  /// No description provided for @nextButton.
  ///
  /// In uz, this message translates to:
  /// **'Keyingi'**
  String get nextButton;

  /// No description provided for @answeredLabel.
  ///
  /// In uz, this message translates to:
  /// **'javoblandi'**
  String get answeredLabel;

  /// No description provided for @uploadingLabel.
  ///
  /// In uz, this message translates to:
  /// **'Yuklanmoqda'**
  String get uploadingLabel;

  /// No description provided for @timeLeftLabel.
  ///
  /// In uz, this message translates to:
  /// **'qoldi'**
  String get timeLeftLabel;

  /// No description provided for @engSectionTransitionTitle.
  ///
  /// In uz, this message translates to:
  /// **'Ingliz tili bo\'limiga o\'tildi'**
  String get engSectionTransitionTitle;

  /// No description provided for @engSectionTransitionDesc.
  ///
  /// In uz, this message translates to:
  /// **'40 daqiqa · Keyingi savollar ingliz tilida'**
  String get engSectionTransitionDesc;

  /// No description provided for @imageLoadFailed.
  ///
  /// In uz, this message translates to:
  /// **'Rasm yuklanmadi'**
  String get imageLoadFailed;

  /// No description provided for @pdfError.
  ///
  /// In uz, this message translates to:
  /// **'PDF xatosi: {error}'**
  String pdfError(String error);

  /// No description provided for @congratsTitle.
  ///
  /// In uz, this message translates to:
  /// **'Tabriklaymiz!'**
  String get congratsTitle;

  /// No description provided for @goodEffortTitle.
  ///
  /// In uz, this message translates to:
  /// **'Yaxshi harakat!'**
  String get goodEffortTitle;

  /// No description provided for @testFinishedSuccess.
  ///
  /// In uz, this message translates to:
  /// **'Test muvaffaqiyatli yakunlandi'**
  String get testFinishedSuccess;

  /// No description provided for @betterNextTime.
  ///
  /// In uz, this message translates to:
  /// **'Keyingi safarida yaxshiroq bo\'ladi!'**
  String get betterNextTime;

  /// No description provided for @scorePoint.
  ///
  /// In uz, this message translates to:
  /// **'ball'**
  String get scorePoint;

  /// No description provided for @passedMessage.
  ///
  /// In uz, this message translates to:
  /// **'Tabriklaymiz! O\'tdingiz!'**
  String get passedMessage;

  /// No description provided for @failedMessage.
  ///
  /// In uz, this message translates to:
  /// **'O\'tmadi. Harakat qiling!'**
  String get failedMessage;

  /// No description provided for @totalScoreLabel.
  ///
  /// In uz, this message translates to:
  /// **'Jami ball'**
  String get totalScoreLabel;

  /// No description provided for @syncedSuccess.
  ///
  /// In uz, this message translates to:
  /// **'Natija serverga muvaffaqiyatli yuborildi'**
  String get syncedSuccess;

  /// No description provided for @savedOffline.
  ///
  /// In uz, this message translates to:
  /// **'Offline saqlandi. Internet bo\'lganda avtomatik yuboriladi'**
  String get savedOffline;

  /// No description provided for @pdfReady.
  ///
  /// In uz, this message translates to:
  /// **'PDF tayyor'**
  String get pdfReady;

  /// No description provided for @downloadPdf.
  ///
  /// In uz, this message translates to:
  /// **'PDF yuklab olish'**
  String get downloadPdf;

  /// No description provided for @nextStudent.
  ///
  /// In uz, this message translates to:
  /// **'Keyingi talaba'**
  String get nextStudent;

  /// No description provided for @wrongAnswersCount.
  ///
  /// In uz, this message translates to:
  /// **'Xato javoblar — {count} ta'**
  String wrongAnswersCount(int count);

  /// No description provided for @wrongAnswersBreakdown.
  ///
  /// In uz, this message translates to:
  /// **'Mat: {math}  ·  Ing: {eng}'**
  String wrongAnswersBreakdown(int math, int eng);

  /// No description provided for @statusGood.
  ///
  /// In uz, this message translates to:
  /// **'Yaxshi ✓'**
  String get statusGood;

  /// No description provided for @statusAverage.
  ///
  /// In uz, this message translates to:
  /// **'O\'rtacha'**
  String get statusAverage;

  /// No description provided for @statusWeak.
  ///
  /// In uz, this message translates to:
  /// **'Zaif — mashq kerak'**
  String get statusWeak;

  /// No description provided for @subjectAnalysisTitle.
  ///
  /// In uz, this message translates to:
  /// **'Mavzu tahlili'**
  String get subjectAnalysisTitle;

  /// No description provided for @mathTipLow1.
  ///
  /// In uz, this message translates to:
  /// **'Asosiy amallar (qo\'shish, ayirish, ko\'paytirish, bo\'lish)ni qayta o\'rganing.'**
  String get mathTipLow1;

  /// No description provided for @mathTipLow2.
  ///
  /// In uz, this message translates to:
  /// **'Har kuni 20 daqiqa misollar yeching.'**
  String get mathTipLow2;

  /// No description provided for @mathTipLow3.
  ///
  /// In uz, this message translates to:
  /// **'2-sinf dasturidan boshlang.'**
  String get mathTipLow3;

  /// No description provided for @mathTipMed1.
  ///
  /// In uz, this message translates to:
  /// **'Jadval va kasr sonlarni mustahkamlang.'**
  String get mathTipMed1;

  /// No description provided for @mathTipMed2.
  ///
  /// In uz, this message translates to:
  /// **'Xato qilgan savollar turini aniqlang va shu mavzuga e\'tibor bering.'**
  String get mathTipMed2;

  /// No description provided for @mathTipMed3.
  ///
  /// In uz, this message translates to:
  /// **'Har kuni 2-3 ta test masala yeching.'**
  String get mathTipMed3;

  /// No description provided for @mathTipHigh1.
  ///
  /// In uz, this message translates to:
  /// **'Qiyin masalalar (muammo masalalar) ustida ishlang.'**
  String get mathTipHigh1;

  /// No description provided for @mathTipHigh2.
  ///
  /// In uz, this message translates to:
  /// **'Vaqtni boshqarishni mashq qiling.'**
  String get mathTipHigh2;

  /// No description provided for @mathTipHigh3.
  ///
  /// In uz, this message translates to:
  /// **'Har savolga 1-2 daqiqa ajrating.'**
  String get mathTipHigh3;

  /// No description provided for @mathTipExc1.
  ///
  /// In uz, this message translates to:
  /// **'Ajoyib!'**
  String get mathTipExc1;

  /// No description provided for @mathTipExc2.
  ///
  /// In uz, this message translates to:
  /// **'Murakkab olimpiada masalalarini hal qilishga o\'ting.'**
  String get mathTipExc2;

  /// No description provided for @mathTipExc3.
  ///
  /// In uz, this message translates to:
  /// **'Natijani barqaror saqlash uchun muntazam mashq qiling.'**
  String get mathTipExc3;

  /// No description provided for @engTipLow1.
  ///
  /// In uz, this message translates to:
  /// **'Kunlik 10 ta yangi so\'z yodlang (flashcard usuli).'**
  String get engTipLow1;

  /// No description provided for @engTipLow2.
  ///
  /// In uz, this message translates to:
  /// **'Asosiy grammatika: to be, present simple, plural nouns.'**
  String get engTipLow2;

  /// No description provided for @engTipLow3.
  ///
  /// In uz, this message translates to:
  /// **'BBC Learning English, Duolingo ilovalaridan foydalaning.'**
  String get engTipLow3;

  /// No description provided for @engTipMed1.
  ///
  /// In uz, this message translates to:
  /// **'Past simple va present continuous grammatikasini o\'rganing.'**
  String get engTipMed1;

  /// No description provided for @engTipMed2.
  ///
  /// In uz, this message translates to:
  /// **'Har kuni inglizcha 1 ta qisqa matn o\'qing.'**
  String get engTipMed2;

  /// No description provided for @engTipMed3.
  ///
  /// In uz, this message translates to:
  /// **'So\'z boyligini mavzu bo\'yicha guruhlab yodlang.'**
  String get engTipMed3;

  /// No description provided for @engTipHigh1.
  ///
  /// In uz, this message translates to:
  /// **'Tinglash ko\'nikmalarini rivojlantiring.'**
  String get engTipHigh1;

  /// No description provided for @engTipHigh2.
  ///
  /// In uz, this message translates to:
  /// **'YouTube ingliz kontentidan foydalaning.'**
  String get engTipHigh2;

  /// No description provided for @engTipHigh3.
  ///
  /// In uz, this message translates to:
  /// **'Esselar va qisqa hikoyalar yozing.'**
  String get engTipHigh3;

  /// No description provided for @engTipExc1.
  ///
  /// In uz, this message translates to:
  /// **'Ajoyib!'**
  String get engTipExc1;

  /// No description provided for @engTipExc2.
  ///
  /// In uz, this message translates to:
  /// **'IELTS/Cambridge sertifikati uchun tayyorlaning.'**
  String get engTipExc2;

  /// No description provided for @engTipExc3.
  ///
  /// In uz, this message translates to:
  /// **'Murakkab matnlarni o\'qish va tinglashni davom ettiring.'**
  String get engTipExc3;

  /// No description provided for @statusGold.
  ///
  /// In uz, this message translates to:
  /// **'Oltin medal darajasi! Davom eting!'**
  String get statusGold;

  /// No description provided for @statusGoodMsg.
  ///
  /// In uz, this message translates to:
  /// **'Yaxshi natija! Yana bir oz harakat kerak.'**
  String get statusGoodMsg;

  /// No description provided for @statusSatisfactory.
  ///
  /// In uz, this message translates to:
  /// **'Qoniqarli. Tavsiyalarga amal qiling va qayta sinab ko\'ring.'**
  String get statusSatisfactory;

  /// No description provided for @statusKeepTrying.
  ///
  /// In uz, this message translates to:
  /// **'Xafa bo\'lmang! Har bir muvaffaqiyatsizlik yangi boshlang\'ich.'**
  String get statusKeepTrying;

  /// No description provided for @pdfTitle.
  ///
  /// In uz, this message translates to:
  /// **'Natija - {name}'**
  String pdfTitle(String name);

  /// No description provided for @subjectsResultTitle.
  ///
  /// In uz, this message translates to:
  /// **'Fanlar bo\'yicha natija'**
  String get subjectsResultTitle;

  /// No description provided for @totalCorrectAnswers.
  ///
  /// In uz, this message translates to:
  /// **'Jami to\'g\'ri javoblar:'**
  String get totalCorrectAnswers;

  /// No description provided for @howToImprove.
  ///
  /// In uz, this message translates to:
  /// **'Qanday yaxshilash mumkin?'**
  String get howToImprove;

  /// No description provided for @mathRecommendations.
  ///
  /// In uz, this message translates to:
  /// **'Matematika tavsiyalari'**
  String get mathRecommendations;

  /// No description provided for @englishRecommendations.
  ///
  /// In uz, this message translates to:
  /// **'Ingliz tili tavsiyalari'**
  String get englishRecommendations;

  /// No description provided for @wrongAnswersTitle.
  ///
  /// In uz, this message translates to:
  /// **'Xato javoblar'**
  String get wrongAnswersTitle;

  /// No description provided for @wrongAnswersAnalysis.
  ///
  /// In uz, this message translates to:
  /// **'Xato javoblar tahlili'**
  String get wrongAnswersAnalysis;

  /// No description provided for @studentLabel.
  ///
  /// In uz, this message translates to:
  /// **'O\'quvchi'**
  String get studentLabel;

  /// No description provided for @passed.
  ///
  /// In uz, this message translates to:
  /// **'O\'tdi'**
  String get passed;

  /// No description provided for @failed.
  ///
  /// In uz, this message translates to:
  /// **'O\'tmadi'**
  String get failed;

  /// No description provided for @keepTrying.
  ///
  /// In uz, this message translates to:
  /// **'Harakat qiling!'**
  String get keepTrying;

  /// No description provided for @monitoringTestResult.
  ///
  /// In uz, this message translates to:
  /// **'Monitoring test natijasi'**
  String get monitoringTestResult;

  /// No description provided for @alochiMonitoringSystem.
  ///
  /// In uz, this message translates to:
  /// **'Alochi Monitoring tizimi'**
  String get alochiMonitoringSystem;

  /// No description provided for @homePage.
  ///
  /// In uz, this message translates to:
  /// **'Bosh sahifa'**
  String get homePage;

  /// No description provided for @savePdf.
  ///
  /// In uz, this message translates to:
  /// **'PDF Saqlash'**
  String get savePdf;

  /// No description provided for @printPdf.
  ///
  /// In uz, this message translates to:
  /// **'Chop etish'**
  String get printPdf;

  /// No description provided for @sharePdf.
  ///
  /// In uz, this message translates to:
  /// **'Ulashish'**
  String get sharePdf;

  /// No description provided for @loadingLabelDots.
  ///
  /// In uz, this message translates to:
  /// **'Yuklanmoqda...'**
  String get loadingLabelDots;

  /// No description provided for @errorLater.
  ///
  /// In uz, this message translates to:
  /// **'Xatolik. Keyinroq yuboriladi.'**
  String get errorLater;

  /// No description provided for @gradeAndVariant.
  ///
  /// In uz, this message translates to:
  /// **'Sinf va Variant'**
  String get gradeAndVariant;

  /// No description provided for @overallResult.
  ///
  /// In uz, this message translates to:
  /// **'Umumiy Natija'**
  String get overallResult;

  /// No description provided for @topicAnalysisTitle.
  ///
  /// In uz, this message translates to:
  /// **'Mavzular bo\'yicha tahlil'**
  String get topicAnalysisTitle;

  /// No description provided for @topicName.
  ///
  /// In uz, this message translates to:
  /// **'Mavzu nomi'**
  String get topicName;

  /// No description provided for @correctAnswersCount.
  ///
  /// In uz, this message translates to:
  /// **'To\'g\'ri javoblar'**
  String get correctAnswersCount;

  /// No description provided for @percentage.
  ///
  /// In uz, this message translates to:
  /// **'Foiz'**
  String get percentage;

  /// No description provided for @offlineTestResult.
  ///
  /// In uz, this message translates to:
  /// **'Oflayn Test Natijasi'**
  String get offlineTestResult;

  /// No description provided for @clearHistoryTitle.
  ///
  /// In uz, this message translates to:
  /// **'Tozalash'**
  String get clearHistoryTitle;

  /// No description provided for @clearHistoryConfirm.
  ///
  /// In uz, this message translates to:
  /// **'Barcha natijalar tarixi o\'chirib yuborilsinmi?'**
  String get clearHistoryConfirm;

  /// No description provided for @noWord.
  ///
  /// In uz, this message translates to:
  /// **'Yo\'q'**
  String get noWord;

  /// No description provided for @yesDelete.
  ///
  /// In uz, this message translates to:
  /// **'Ha, o\'chirish'**
  String get yesDelete;

  /// No description provided for @offlineHistoryTitle.
  ///
  /// In uz, this message translates to:
  /// **'Oflayn Natijalar Tarixi'**
  String get offlineHistoryTitle;

  /// No description provided for @noHistoryYet.
  ///
  /// In uz, this message translates to:
  /// **'Hozircha tarix yo\'q'**
  String get noHistoryYet;

  /// No description provided for @schoolLabel.
  ///
  /// In uz, this message translates to:
  /// **'Maktab'**
  String get schoolLabel;

  /// No description provided for @dateLabel.
  ///
  /// In uz, this message translates to:
  /// **'Sana'**
  String get dateLabel;

  /// No description provided for @mathShort.
  ///
  /// In uz, this message translates to:
  /// **'Mat'**
  String get mathShort;

  /// No description provided for @engShort.
  ///
  /// In uz, this message translates to:
  /// **'Ing'**
  String get engShort;

  /// No description provided for @syncCompleteMsg.
  ///
  /// In uz, this message translates to:
  /// **'Sinxronizatsiya yakunlandi! {done} ta rasm oflayn saqlandi.'**
  String syncCompleteMsg(String done);

  /// No description provided for @errorOccurred.
  ///
  /// In uz, this message translates to:
  /// **'Xato yuz berdi: '**
  String get errorOccurred;

  /// No description provided for @offlineImagesLoading.
  ///
  /// In uz, this message translates to:
  /// **'Oflayn rasmlar yuklanmoqda...'**
  String get offlineImagesLoading;

  /// No description provided for @savedOutOfTotal.
  ///
  /// In uz, this message translates to:
  /// **'{done} / {total} ta saqlandi'**
  String savedOutOfTotal(String done, String total);

  /// No description provided for @syncImagesOfflineButton.
  ///
  /// In uz, this message translates to:
  /// **'Oflayn rasmlarni tayyorlash (Sync)'**
  String get syncImagesOfflineButton;

  /// No description provided for @localResSending.
  ///
  /// In uz, this message translates to:
  /// **'📤 Yuborilmoqda...'**
  String get localResSending;

  /// No description provided for @localResSavedSending.
  ///
  /// In uz, this message translates to:
  /// **'✅ Saqlandi, yuborilmoqda...'**
  String get localResSavedSending;

  /// No description provided for @localResSaveError.
  ///
  /// In uz, this message translates to:
  /// **'❌ Saqlashda xato. Qayta urinib ko\'ring.'**
  String get localResSaveError;

  /// No description provided for @localResBarakalla.
  ///
  /// In uz, this message translates to:
  /// **'Barakalla!'**
  String get localResBarakalla;

  /// No description provided for @localResYaxshi.
  ///
  /// In uz, this message translates to:
  /// **'Yaxshi!'**
  String get localResYaxshi;

  /// No description provided for @nextStudentButton.
  ///
  /// In uz, this message translates to:
  /// **'Keyingi o\'quvchi'**
  String get nextStudentButton;

  /// No description provided for @questionsUnansweredPrompt.
  ///
  /// In uz, this message translates to:
  /// **'ta savol javobsiz. Tugatmoqchimisiz?'**
  String get questionsUnansweredPrompt;

  /// No description provided for @finishButtonText.
  ///
  /// In uz, this message translates to:
  /// **'Tugatish'**
  String get finishButtonText;

  /// No description provided for @gradeWord.
  ///
  /// In uz, this message translates to:
  /// **'-sinf'**
  String get gradeWord;

  /// No description provided for @mathSectionTimeUp.
  ///
  /// In uz, this message translates to:
  /// **'Matematika bo\'limi vaqti tugagan!'**
  String get mathSectionTimeUp;

  /// No description provided for @engSectionTimeUp.
  ///
  /// In uz, this message translates to:
  /// **'Ingliz tili bo\'limi vaqti tugagan!'**
  String get engSectionTimeUp;

  /// No description provided for @finishTest.
  ///
  /// In uz, this message translates to:
  /// **'Tugatish'**
  String get finishTest;

  /// No description provided for @uploadTest.
  ///
  /// In uz, this message translates to:
  /// **'Yuklash'**
  String get uploadTest;

  /// No description provided for @resultNotSavedError.
  ///
  /// In uz, this message translates to:
  /// **'Natija saqlanmadi — internet yoki xotira muammosi. Qayta urinib ko\'ring.'**
  String get resultNotSavedError;

  /// No description provided for @testLoadFailed.
  ///
  /// In uz, this message translates to:
  /// **'Test yuklanmadi'**
  String get testLoadFailed;

  /// No description provided for @testTitle.
  ///
  /// In uz, this message translates to:
  /// **'Test'**
  String get testTitle;

  /// No description provided for @gradeExcellent.
  ///
  /// In uz, this message translates to:
  /// **'A\'lo'**
  String get gradeExcellent;

  /// No description provided for @gradeGood.
  ///
  /// In uz, this message translates to:
  /// **'Yaxshi'**
  String get gradeGood;

  /// No description provided for @gradeSatisfactory.
  ///
  /// In uz, this message translates to:
  /// **'Qoniqarli'**
  String get gradeSatisfactory;

  /// No description provided for @gradeNeedsPractice.
  ///
  /// In uz, this message translates to:
  /// **'Qo\'shimcha mashq kerak'**
  String get gradeNeedsPractice;

  /// No description provided for @pdfGenerationError.
  ///
  /// In uz, this message translates to:
  /// **'PDF yaratishda xato'**
  String get pdfGenerationError;

  /// No description provided for @resultTitle.
  ///
  /// In uz, this message translates to:
  /// **'Natija'**
  String get resultTitle;

  /// No description provided for @correctAnswersWithCount.
  ///
  /// In uz, this message translates to:
  /// **'To\'g\'ri {count}'**
  String correctAnswersWithCount(String count);

  /// No description provided for @wrongAnswersWithCount.
  ///
  /// In uz, this message translates to:
  /// **'Xato {count}'**
  String wrongAnswersWithCount(String count);

  /// No description provided for @shieldsCount.
  ///
  /// In uz, this message translates to:
  /// **'{count} qalqon'**
  String shieldsCount(String count);

  /// No description provided for @sectionsByTitle.
  ///
  /// In uz, this message translates to:
  /// **'BO\'LIMLAR BO\'YICHA'**
  String get sectionsByTitle;

  /// No description provided for @noDataAvailable.
  ///
  /// In uz, this message translates to:
  /// **'Ma\'lumot yo\'q'**
  String get noDataAvailable;

  /// No description provided for @reopenPdf.
  ///
  /// In uz, this message translates to:
  /// **'PDF qayta ochish'**
  String get reopenPdf;

  /// No description provided for @pdfReportButton.
  ///
  /// In uz, this message translates to:
  /// **'PDF hisobot'**
  String get pdfReportButton;

  /// No description provided for @aiAnalysisTitle.
  ///
  /// In uz, this message translates to:
  /// **'AI tahlil'**
  String get aiAnalysisTitle;

  /// No description provided for @analysisPreparing.
  ///
  /// In uz, this message translates to:
  /// **'Tahlil tayyorlanmoqda…'**
  String get analysisPreparing;

  /// No description provided for @strongSidesTitle.
  ///
  /// In uz, this message translates to:
  /// **'Kuchli tomonlar'**
  String get strongSidesTitle;

  /// No description provided for @weakSidesTitle.
  ///
  /// In uz, this message translates to:
  /// **'Zaif tomonlar'**
  String get weakSidesTitle;

  /// No description provided for @recommendationsTitle.
  ///
  /// In uz, this message translates to:
  /// **'Tavsiyalar'**
  String get recommendationsTitle;

  /// No description provided for @focus14DaysTitle.
  ///
  /// In uz, this message translates to:
  /// **'14 kunlik e\'tibor'**
  String get focus14DaysTitle;

  /// No description provided for @subjectAnalysisByTopic.
  ///
  /// In uz, this message translates to:
  /// **'Mavzu bo\'yicha tahlil'**
  String get subjectAnalysisByTopic;

  /// No description provided for @subjectAnalysisByUnit.
  ///
  /// In uz, this message translates to:
  /// **'Unitlar bo\'yicha tahlil'**
  String get subjectAnalysisByUnit;

  /// No description provided for @subjectAnalysisByParagraph.
  ///
  /// In uz, this message translates to:
  /// **'Paragraf bo\'yicha taqsimot'**
  String get subjectAnalysisByParagraph;

  /// No description provided for @strongAndWeakSides.
  ///
  /// In uz, this message translates to:
  /// **'Kuchli va zaif tomonlar'**
  String get strongAndWeakSides;

  /// No description provided for @strongLabel.
  ///
  /// In uz, this message translates to:
  /// **'Kuchli'**
  String get strongLabel;

  /// No description provided for @needsReinforcement.
  ///
  /// In uz, this message translates to:
  /// **'Mustahkamlash kerak'**
  String get needsReinforcement;

  /// No description provided for @weakTopicFallback.
  ///
  /// In uz, this message translates to:
  /// **'zaif mavzu'**
  String get weakTopicFallback;

  /// No description provided for @days1to3.
  ///
  /// In uz, this message translates to:
  /// **'1–3 kun'**
  String get days1to3;

  /// No description provided for @weakestTopicPlan.
  ///
  /// In uz, this message translates to:
  /// **'Eng zaif mavzu: {topic} (15 daqiqa/kun)'**
  String weakestTopicPlan(String topic);

  /// No description provided for @days4to7.
  ///
  /// In uz, this message translates to:
  /// **'4–7 kun'**
  String get days4to7;

  /// No description provided for @secondTopicPlan.
  ///
  /// In uz, this message translates to:
  /// **'Ikkinchi mavzu: {topic} (5 ta misol/kun)'**
  String secondTopicPlan(String topic);

  /// No description provided for @days8to11.
  ///
  /// In uz, this message translates to:
  /// **'8–11 kun'**
  String get days8to11;

  /// No description provided for @mixedExercisesPlan.
  ///
  /// In uz, this message translates to:
  /// **'Aralash mashqlar — barcha mavzularni takrorlash'**
  String get mixedExercisesPlan;

  /// No description provided for @days12to14.
  ///
  /// In uz, this message translates to:
  /// **'12–14 kun'**
  String get days12to14;

  /// No description provided for @controlTestPlan.
  ///
  /// In uz, this message translates to:
  /// **'Nazorat testi — natijani solishtirish'**
  String get controlTestPlan;

  /// No description provided for @plan14DaysTitle.
  ///
  /// In uz, this message translates to:
  /// **'14 kunlik reja'**
  String get plan14DaysTitle;

  /// No description provided for @sending.
  ///
  /// In uz, this message translates to:
  /// **'Yuborilmoqda...'**
  String get sending;

  /// No description provided for @savedSuccess.
  ///
  /// In uz, this message translates to:
  /// **'Saqlandi!'**
  String get savedSuccess;

  /// No description provided for @savedOfflineLater.
  ///
  /// In uz, this message translates to:
  /// **'Saqlandi (offline — keyinroq yuboriladi)'**
  String get savedOfflineLater;

  /// No description provided for @savedSending.
  ///
  /// In uz, this message translates to:
  /// **'Saqlandi, yuborilmoqda...'**
  String get savedSending;

  /// No description provided for @interhouseGrade2.
  ///
  /// In uz, this message translates to:
  /// **'Interhouse Grade 2'**
  String get interhouseGrade2;

  /// No description provided for @sectionsBreakdown.
  ///
  /// In uz, this message translates to:
  /// **'Bo\'limlar bo\'yicha'**
  String get sectionsBreakdown;

  /// No description provided for @nextStudentBtn.
  ///
  /// In uz, this message translates to:
  /// **'Keyingi o\'quvchi'**
  String get nextStudentBtn;

  /// No description provided for @finishBtn.
  ///
  /// In uz, this message translates to:
  /// **'Tugatish'**
  String get finishBtn;

  /// No description provided for @mathQuestionsNotFound.
  ///
  /// In uz, this message translates to:
  /// **'Matematika savollari topilmadi.'**
  String get mathQuestionsNotFound;

  /// No description provided for @generalTests.
  ///
  /// In uz, this message translates to:
  /// **'Umumiy testlar'**
  String get generalTests;

  /// No description provided for @loadingGroups.
  ///
  /// In uz, this message translates to:
  /// **'Guruhlar yuklanmoqda...'**
  String get loadingGroups;

  /// No description provided for @selectGroup.
  ///
  /// In uz, this message translates to:
  /// **'Guruhni tanlang'**
  String get selectGroup;

  /// No description provided for @selectStudent.
  ///
  /// In uz, this message translates to:
  /// **'O\'quvchini tanlang'**
  String get selectStudent;

  /// No description provided for @selectGrade.
  ///
  /// In uz, this message translates to:
  /// **'Sinfni tanlang'**
  String get selectGrade;

  /// No description provided for @selectSchool.
  ///
  /// In uz, this message translates to:
  /// **'Maktabni tanlang'**
  String get selectSchool;

  /// No description provided for @incorrectPin.
  ///
  /// In uz, this message translates to:
  /// **'PIN noto\'g\'ri'**
  String get incorrectPin;

  /// No description provided for @enterFourDigitPin.
  ///
  /// In uz, this message translates to:
  /// **'To\'rt xonali PIN kodni kiriting'**
  String get enterFourDigitPin;

  /// No description provided for @showPassword.
  ///
  /// In uz, this message translates to:
  /// **'Ko\'rsatish'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In uz, this message translates to:
  /// **'Yashirish'**
  String get hidePassword;

  /// No description provided for @confirmBtn.
  ///
  /// In uz, this message translates to:
  /// **'Tasdiqlash'**
  String get confirmBtn;

  /// No description provided for @nextStepStudentName.
  ///
  /// In uz, this message translates to:
  /// **'Keyingi qadam: o\'quvchi ismini kiritish'**
  String get nextStepStudentName;

  /// No description provided for @testSession.
  ///
  /// In uz, this message translates to:
  /// **'Sinov sessiyasi'**
  String get testSession;

  /// No description provided for @testSessionInstruction.
  ///
  /// In uz, this message translates to:
  /// **'Sinov sessiyasini boshlash uchun maktabni tanlang va PIN kodni kiriting.'**
  String get testSessionInstruction;

  /// No description provided for @sessionSettings.
  ///
  /// In uz, this message translates to:
  /// **'Sessiya sozlamalari'**
  String get sessionSettings;

  /// No description provided for @studentNameStep.
  ///
  /// In uz, this message translates to:
  /// **'O\'quvchi ismi'**
  String get studentNameStep;

  /// No description provided for @testLocked.
  ///
  /// In uz, this message translates to:
  /// **'Bu test hali qulflangan.'**
  String get testLocked;

  /// No description provided for @testNotInCache.
  ///
  /// In uz, this message translates to:
  /// **'Test keshda topilmadi. Qayta yuklab oling.'**
  String get testNotInCache;

  /// No description provided for @sessionConflictOtherDevice.
  ///
  /// In uz, this message translates to:
  /// **'Bu o\'quvchi boshqa qurilmada testni allaqachon boshlagan.'**
  String get sessionConflictOtherDevice;

  /// No description provided for @schools.
  ///
  /// In uz, this message translates to:
  /// **'Maktablar'**
  String get schools;

  /// No description provided for @otherSchools.
  ///
  /// In uz, this message translates to:
  /// **'Boshqa maktablar'**
  String get otherSchools;

  /// No description provided for @schoolCodeOrName.
  ///
  /// In uz, this message translates to:
  /// **'Maktab kodi / nomi'**
  String get schoolCodeOrName;

  /// No description provided for @downloaded.
  ///
  /// In uz, this message translates to:
  /// **'Yuklab olingan'**
  String get downloaded;

  /// No description provided for @enterSchoolError.
  ///
  /// In uz, this message translates to:
  /// **'Maktabni kiriting'**
  String get enterSchoolError;

  /// No description provided for @schoolPrefix.
  ///
  /// In uz, this message translates to:
  /// **'{code}-maktab'**
  String schoolPrefix(String code);

  /// No description provided for @enterNameError.
  ///
  /// In uz, this message translates to:
  /// **'Ism va familiyani kiriting'**
  String get enterNameError;

  /// No description provided for @lastName.
  ///
  /// In uz, this message translates to:
  /// **'Familiya'**
  String get lastName;

  /// No description provided for @firstName.
  ///
  /// In uz, this message translates to:
  /// **'Ism'**
  String get firstName;

  /// No description provided for @groupOptional.
  ///
  /// In uz, this message translates to:
  /// **'Guruh (ixtiyoriy)'**
  String get groupOptional;

  /// No description provided for @variant.
  ///
  /// In uz, this message translates to:
  /// **'Variant'**
  String get variant;

  /// No description provided for @start.
  ///
  /// In uz, this message translates to:
  /// **'Boshlash'**
  String get start;

  /// No description provided for @downloadError.
  ///
  /// In uz, this message translates to:
  /// **'Yuklashda xato. Qayta urinib ko\'ring.'**
  String get downloadError;

  /// No description provided for @testsNotFound.
  ///
  /// In uz, this message translates to:
  /// **'Testlar topilmadi'**
  String get testsNotFound;

  /// No description provided for @opensAt.
  ///
  /// In uz, this message translates to:
  /// **'da ochiladi'**
  String get opensAt;

  /// No description provided for @newVersionAvailable.
  ///
  /// In uz, this message translates to:
  /// **'Yangi versiya mavjud'**
  String get newVersionAvailable;

  /// No description provided for @update.
  ///
  /// In uz, this message translates to:
  /// **'Yangilash'**
  String get update;

  /// No description provided for @download.
  ///
  /// In uz, this message translates to:
  /// **'Yuklash'**
  String get download;

  /// No description provided for @confirmSessionTitle.
  ///
  /// In uz, this message translates to:
  /// **'Sessiyani\ntasdiqlang'**
  String get confirmSessionTitle;

  /// No description provided for @pinCodeRequired.
  ///
  /// In uz, this message translates to:
  /// **'PIN KOD (MAJBURIY)'**
  String get pinCodeRequired;

  /// No description provided for @enterPinCode.
  ///
  /// In uz, this message translates to:
  /// **'PIN kodni kiriting'**
  String get enterPinCode;

  /// No description provided for @enterTeacherCode.
  ///
  /// In uz, this message translates to:
  /// **'O\'qituvchi bergan kodni kiriting'**
  String get enterTeacherCode;

  /// No description provided for @otherSchoolBtn.
  ///
  /// In uz, this message translates to:
  /// **'Boshqa maktab'**
  String get otherSchoolBtn;

  /// No description provided for @groupsNotFound.
  ///
  /// In uz, this message translates to:
  /// **'Guruhlar topilmadi'**
  String get groupsNotFound;

  /// No description provided for @testsNotFoundForGroup.
  ///
  /// In uz, this message translates to:
  /// **'Bu guruh uchun test topilmadi'**
  String get testsNotFoundForGroup;

  /// No description provided for @notDownloaded.
  ///
  /// In uz, this message translates to:
  /// **'Yuklab olinmagan'**
  String get notDownloaded;

  /// No description provided for @stillLocked.
  ///
  /// In uz, this message translates to:
  /// **'Hali qulflangan'**
  String get stillLocked;

  /// No description provided for @ready.
  ///
  /// In uz, this message translates to:
  /// **'Tayyor'**
  String get ready;

  /// No description provided for @newBadge.
  ///
  /// In uz, this message translates to:
  /// **'Yangi'**
  String get newBadge;

  /// No description provided for @newBadgeAddedOn.
  ///
  /// In uz, this message translates to:
  /// **'Qo\'shildi: {date}'**
  String newBadgeAddedOn(String date);

  /// No description provided for @whoTakesTest.
  ///
  /// In uz, this message translates to:
  /// **'Testni kim\ntopshiradi?'**
  String get whoTakesTest;

  /// No description provided for @studentsInList.
  ///
  /// In uz, this message translates to:
  /// **'o\'quvchi ro\'yxatda mavjud'**
  String get studentsInList;

  /// No description provided for @gradeShort.
  ///
  /// In uz, this message translates to:
  /// **'sinf'**
  String get gradeShort;

  /// No description provided for @backBtn.
  ///
  /// In uz, this message translates to:
  /// **'Ortga'**
  String get backBtn;

  /// No description provided for @copyName.
  ///
  /// In uz, this message translates to:
  /// **'Nusxa olish'**
  String get copyName;

  /// No description provided for @nameCopied.
  ///
  /// In uz, this message translates to:
  /// **'{name} nusxalandi!'**
  String nameCopied(String name);

  /// No description provided for @searchStudents.
  ///
  /// In uz, this message translates to:
  /// **'O\'quvchini izlash (Ctrl+K)...'**
  String get searchStudents;

  /// No description provided for @back.
  ///
  /// In uz, this message translates to:
  /// **'Orqaga'**
  String get back;

  /// No description provided for @finish.
  ///
  /// In uz, this message translates to:
  /// **'Tugatish'**
  String get finish;

  /// No description provided for @errorTitle.
  ///
  /// In uz, this message translates to:
  /// **'Xatolik'**
  String get errorTitle;

  /// No description provided for @returnToHome.
  ///
  /// In uz, this message translates to:
  /// **'Bosh sahifaga qaytish'**
  String get returnToHome;

  /// No description provided for @routeNotFound.
  ///
  /// In uz, this message translates to:
  /// **'Route not found'**
  String get routeNotFound;

  /// No description provided for @reportGenerationError.
  ///
  /// In uz, this message translates to:
  /// **'Hisobot yaratishda xato'**
  String get reportGenerationError;

  /// No description provided for @printBtn.
  ///
  /// In uz, this message translates to:
  /// **'Chop etish'**
  String get printBtn;

  /// No description provided for @downloadBtn.
  ///
  /// In uz, this message translates to:
  /// **'Yuklab olish'**
  String get downloadBtn;

  /// No description provided for @exitBtn.
  ///
  /// In uz, this message translates to:
  /// **'Chiqish'**
  String get exitBtn;

  /// No description provided for @yesBtn.
  ///
  /// In uz, this message translates to:
  /// **'Ha'**
  String get yesBtn;

  /// No description provided for @updateBtn.
  ///
  /// In uz, this message translates to:
  /// **'Yangilanish'**
  String get updateBtn;

  /// No description provided for @updateDownloadFailedMsg.
  ///
  /// In uz, this message translates to:
  /// **'Yangilanishni yuklab bo\'lmadi. Internet aloqasini tekshirib, qayta urining.'**
  String get updateDownloadFailedMsg;

  /// No description provided for @okBtn.
  ///
  /// In uz, this message translates to:
  /// **'Yaxshi'**
  String get okBtn;

  /// No description provided for @yesOption.
  ///
  /// In uz, this message translates to:
  /// **'YES'**
  String get yesOption;

  /// No description provided for @noOption.
  ///
  /// In uz, this message translates to:
  /// **'NO'**
  String get noOption;

  /// No description provided for @alisherHint.
  ///
  /// In uz, this message translates to:
  /// **'Alisher'**
  String get alisherHint;

  /// No description provided for @vocabularyTopic.
  ///
  /// In uz, this message translates to:
  /// **'Vocabulary'**
  String get vocabularyTopic;

  /// No description provided for @grammarTopic.
  ///
  /// In uz, this message translates to:
  /// **'Grammar'**
  String get grammarTopic;

  /// No description provided for @spellingTopic.
  ///
  /// In uz, this message translates to:
  /// **'Spelling'**
  String get spellingTopic;

  /// No description provided for @sentencesTopic.
  ///
  /// In uz, this message translates to:
  /// **'Sentences'**
  String get sentencesTopic;

  /// No description provided for @readingTopic.
  ///
  /// In uz, this message translates to:
  /// **'Reading'**
  String get readingTopic;

  /// No description provided for @checkForUpdates.
  ///
  /// In uz, this message translates to:
  /// **'Check for Updates...'**
  String get checkForUpdates;

  /// No description provided for @appNameTitle.
  ///
  /// In uz, this message translates to:
  /// **'Alochi Monitoring'**
  String get appNameTitle;

  /// No description provided for @bobEmptySectionMsg.
  ///
  /// In uz, this message translates to:
  /// **'Bu bo\'lim bo\'sh.'**
  String get bobEmptySectionMsg;

  /// No description provided for @returnBtn.
  ///
  /// In uz, this message translates to:
  /// **'Qaytish'**
  String get returnBtn;

  /// No description provided for @sectionsResultTitle.
  ///
  /// In uz, this message translates to:
  /// **'Bo\'limlar natijasi'**
  String get sectionsResultTitle;

  /// No description provided for @vocabularyQuestionsNotFoundMsg.
  ///
  /// In uz, this message translates to:
  /// **'Vocabulary savollari topilmadi.'**
  String get vocabularyQuestionsNotFoundMsg;

  /// No description provided for @grammarQuestionsNotFoundMsg.
  ///
  /// In uz, this message translates to:
  /// **'Grammar savollari topilmadi.'**
  String get grammarQuestionsNotFoundMsg;

  /// No description provided for @spellingQuestionsNotFoundMsg.
  ///
  /// In uz, this message translates to:
  /// **'Spelling savollari topilmadi.'**
  String get spellingQuestionsNotFoundMsg;

  /// No description provided for @sentencesQuestionsNotFoundMsg.
  ///
  /// In uz, this message translates to:
  /// **'Sentences savollari topilmadi.'**
  String get sentencesQuestionsNotFoundMsg;

  /// No description provided for @readingQuestionsNotFoundMsg.
  ///
  /// In uz, this message translates to:
  /// **'Reading savollari topilmadi.'**
  String get readingQuestionsNotFoundMsg;

  /// No description provided for @variantsNotFoundMsg.
  ///
  /// In uz, this message translates to:
  /// **'Variantlar topilmadi.'**
  String get variantsNotFoundMsg;

  /// No description provided for @arrangeLettersPrompt.
  ///
  /// In uz, this message translates to:
  /// **'Harflarni to\'g\'ri joylashtiring'**
  String get arrangeLettersPrompt;

  /// No description provided for @arrangeSentencePrompt.
  ///
  /// In uz, this message translates to:
  /// **'Jumlani to\'g\'ri tartibga soling'**
  String get arrangeSentencePrompt;

  /// No description provided for @arrangeEventsPrompt.
  ///
  /// In uz, this message translates to:
  /// **'Voqealarni to\'g\'ri tartibda belgilang'**
  String get arrangeEventsPrompt;

  /// No description provided for @selectVariantsInOrderPrompt.
  ///
  /// In uz, this message translates to:
  /// **'Quyidagi variantlarni to\'g\'ri ketma-ketlikda tanlang'**
  String get selectVariantsInOrderPrompt;

  /// No description provided for @clearSelectionBtn.
  ///
  /// In uz, this message translates to:
  /// **'Tozalash'**
  String get clearSelectionBtn;

  /// No description provided for @variantsSectionHeader.
  ///
  /// In uz, this message translates to:
  /// **'VARIANTLAR'**
  String get variantsSectionHeader;

  /// No description provided for @answerHintText.
  ///
  /// In uz, this message translates to:
  /// **'Javob...'**
  String get answerHintText;

  /// No description provided for @fullSentenceHintText.
  ///
  /// In uz, this message translates to:
  /// **'To\'liq jumlani yozing...'**
  String get fullSentenceHintText;

  /// No description provided for @sessionGradeVariantLabel.
  ///
  /// In uz, this message translates to:
  /// **'{grade}-sinf · Variant {variant}'**
  String sessionGradeVariantLabel(String grade, String variant);

  /// No description provided for @reportSavedButOpenFailedMsg.
  ///
  /// In uz, this message translates to:
  /// **'Hisobot saqlandi, lekin ochib bo\'lmadi'**
  String get reportSavedButOpenFailedMsg;

  /// No description provided for @bob14ScreenTitle.
  ///
  /// In uz, this message translates to:
  /// **'2-sinf — Bob 1-4 Monitoringi'**
  String get bob14ScreenTitle;

  /// No description provided for @bob14TestInfo.
  ///
  /// In uz, this message translates to:
  /// **'30 savol · 45 daqiqa · Offline rejim'**
  String get bob14TestInfo;

  /// No description provided for @unit1ScreenTitle.
  ///
  /// In uz, this message translates to:
  /// **'1-sinf Ingliz tili — Unit 1'**
  String get unit1ScreenTitle;

  /// No description provided for @unit1TestInfo.
  ///
  /// In uz, this message translates to:
  /// **'49 savol · 49 daqiqa · Offline rejim'**
  String get unit1TestInfo;

  /// No description provided for @unit1RunnerHeaderTitle.
  ///
  /// In uz, this message translates to:
  /// **'1-sinf Unit 1 — Ingliz tili'**
  String get unit1RunnerHeaderTitle;

  /// No description provided for @correctFractionLabel.
  ///
  /// In uz, this message translates to:
  /// **'{correct} / {total} to\'g\'ri'**
  String correctFractionLabel(int correct, int total);

  /// No description provided for @hujjatlarLabel.
  ///
  /// In uz, this message translates to:
  /// **'Hujjatlar'**
  String get hujjatlarLabel;

  /// No description provided for @noDocumentsMsg.
  ///
  /// In uz, this message translates to:
  /// **'Hujjat yo\'q'**
  String get noDocumentsMsg;

  /// No description provided for @savedFileMsg.
  ///
  /// In uz, this message translates to:
  /// **'Saqlandi: {path}'**
  String savedFileMsg(String path);

  /// No description provided for @exitConfirmationMessage.
  ///
  /// In uz, this message translates to:
  /// **'Haqiqatan ham chiqmoqchimisiz? Kiritilgan ma\'lumotlar saqlanmaydi.'**
  String get exitConfirmationMessage;

  /// No description provided for @pageNotFoundTitle.
  ///
  /// In uz, this message translates to:
  /// **'Sahifa topilmadi'**
  String get pageNotFoundTitle;

  /// No description provided for @pageNotFoundMessage.
  ///
  /// In uz, this message translates to:
  /// **'Kechirasiz, siz qidirayotgan sahifa mavjud emas yoki ko\'chirilgan.'**
  String get pageNotFoundMessage;

  /// No description provided for @monitoringTestHeader.
  ///
  /// In uz, this message translates to:
  /// **'MONITORING TEST'**
  String get monitoringTestHeader;

  /// No description provided for @testDataNotFoundMsg.
  ///
  /// In uz, this message translates to:
  /// **'Test ma\'lumotlari topilmadi'**
  String get testDataNotFoundMsg;

  /// No description provided for @updateUpToDateMessage.
  ///
  /// In uz, this message translates to:
  /// **'Sizda dasturning eng so\'nggi versiyasi o\'rnatilgan.'**
  String get updateUpToDateMessage;

  /// No description provided for @shieldsProgressLabel.
  ///
  /// In uz, this message translates to:
  /// **'{count}/25 shields'**
  String shieldsProgressLabel(int count);

  /// No description provided for @diagnosticPassportHeader.
  ///
  /// In uz, this message translates to:
  /// **'A\'LOCHI — DIAGNOSTIK PASPORT'**
  String get diagnosticPassportHeader;

  /// No description provided for @totalQuestionsCountLabel.
  ///
  /// In uz, this message translates to:
  /// **'Jami savol'**
  String get totalQuestionsCountLabel;

  /// No description provided for @correctAnswerLabelPdf.
  ///
  /// In uz, this message translates to:
  /// **'To\'g\'ri javob'**
  String get correctAnswerLabelPdf;

  /// No description provided for @wrongAnswerLabelPdf.
  ///
  /// In uz, this message translates to:
  /// **'Xato javob'**
  String get wrongAnswerLabelPdf;

  /// No description provided for @topicAnalysisHeader.
  ///
  /// In uz, this message translates to:
  /// **'MAVZU BO\'YICHA TAHLIL'**
  String get topicAnalysisHeader;

  /// No description provided for @unitAnalysisHeader.
  ///
  /// In uz, this message translates to:
  /// **'UNIT BO\'YICHA TAHLIL'**
  String get unitAnalysisHeader;

  /// No description provided for @fourteenDayPlanHeader.
  ///
  /// In uz, this message translates to:
  /// **'14 KUNLIK REJA'**
  String get fourteenDayPlanHeader;

  /// No description provided for @aiSummaryHeader.
  ///
  /// In uz, this message translates to:
  /// **'AI XULOSA'**
  String get aiSummaryHeader;

  /// No description provided for @alochiAiLabel.
  ///
  /// In uz, this message translates to:
  /// **'A\'LOCHI AI'**
  String get alochiAiLabel;

  /// No description provided for @forParentsLabel.
  ///
  /// In uz, this message translates to:
  /// **'Ota-onaga'**
  String get forParentsLabel;

  /// No description provided for @parentTipsText.
  ///
  /// In uz, this message translates to:
  /// **'• Har kuni 20–30 daqiqa o\'qish vaqti\n• Zaif mavzularni birgalikda takrorlang\n• Rag\'batlantiring va sabr bilan o\'rgating'**
  String get parentTipsText;

  /// No description provided for @footerBrandTagline.
  ///
  /// In uz, this message translates to:
  /// **'A\'lochi Ta\'lim · alochi.uz'**
  String get footerBrandTagline;

  /// No description provided for @dayRange1_3.
  ///
  /// In uz, this message translates to:
  /// **'1–3 KUN'**
  String get dayRange1_3;

  /// No description provided for @dayRange4_7.
  ///
  /// In uz, this message translates to:
  /// **'4–7 KUN'**
  String get dayRange4_7;

  /// No description provided for @dayRange8_11.
  ///
  /// In uz, this message translates to:
  /// **'8–11 KUN'**
  String get dayRange8_11;

  /// No description provided for @dayRange12_14.
  ///
  /// In uz, this message translates to:
  /// **'12–14 KUN'**
  String get dayRange12_14;

  /// No description provided for @dailyPractice15MinMsg.
  ///
  /// In uz, this message translates to:
  /// **'Har kuni 15 daqiqa mashq'**
  String get dailyPractice15MinMsg;

  /// No description provided for @dailyExamples5Msg.
  ///
  /// In uz, this message translates to:
  /// **'Har kuni 5 ta misol yechish'**
  String get dailyExamples5Msg;

  /// No description provided for @mixedExercisesTopic.
  ///
  /// In uz, this message translates to:
  /// **'Aralash mashqlar'**
  String get mixedExercisesTopic;

  /// No description provided for @reviewAllTopicsMsg.
  ///
  /// In uz, this message translates to:
  /// **'Barcha mavzularni takrorlash'**
  String get reviewAllTopicsMsg;

  /// No description provided for @controlTestTopic.
  ///
  /// In uz, this message translates to:
  /// **'Nazorat testi'**
  String get controlTestTopic;

  /// No description provided for @compareResultsMsg.
  ///
  /// In uz, this message translates to:
  /// **'Natijalarni solishtirish'**
  String get compareResultsMsg;

  /// No description provided for @wellMasteredBadge.
  ///
  /// In uz, this message translates to:
  /// **'Yaxshi o\'zlashtirilgan'**
  String get wellMasteredBadge;

  /// No description provided for @needsReviewBadge.
  ///
  /// In uz, this message translates to:
  /// **'Qayta o\'rganish'**
  String get needsReviewBadge;

  /// No description provided for @aiSummaryFallbackMsg.
  ///
  /// In uz, this message translates to:
  /// **'{firstName} {pct}% natija ko\'rsatdi. O\'zlashtirish darajasiga qarab 14 kunlik reja bilan ishlash tavsiya etiladi.'**
  String aiSummaryFallbackMsg(String firstName, int pct);

  /// No description provided for @goodResultLabel.
  ///
  /// In uz, this message translates to:
  /// **'Yaxshi natija'**
  String get goodResultLabel;

  /// No description provided for @searchOrCommandHint.
  ///
  /// In uz, this message translates to:
  /// **'Izlash yoki buyruq kiriting...'**
  String get searchOrCommandHint;

  /// No description provided for @commandHistoryTitle.
  ///
  /// In uz, this message translates to:
  /// **'Oflayn tarix'**
  String get commandHistoryTitle;

  /// No description provided for @commandLocalGradeTitle.
  ///
  /// In uz, this message translates to:
  /// **'Mahalliy baholash'**
  String get commandLocalGradeTitle;

  /// No description provided for @commandCombinedTitle.
  ///
  /// In uz, this message translates to:
  /// **'Kombinatsiyalangan'**
  String get commandCombinedTitle;

  /// No description provided for @bob14FallbackLabel.
  ///
  /// In uz, this message translates to:
  /// **'Bob 1-4'**
  String get bob14FallbackLabel;

  /// No description provided for @unit1FallbackLabel.
  ///
  /// In uz, this message translates to:
  /// **'Unit 1'**
  String get unit1FallbackLabel;

  /// No description provided for @saveErrorRetryMsg.
  ///
  /// In uz, this message translates to:
  /// **'Saqlashda xato. Qayta urinib ko\'ring.'**
  String get saveErrorRetryMsg;

  /// No description provided for @unit1PillLabel.
  ///
  /// In uz, this message translates to:
  /// **'Unit 1 G1'**
  String get unit1PillLabel;

  /// No description provided for @interhousePillLabel.
  ///
  /// In uz, this message translates to:
  /// **'Interhouse G2'**
  String get interhousePillLabel;

  /// No description provided for @combinedPillLabel.
  ///
  /// In uz, this message translates to:
  /// **'Monitoring Unit 1'**
  String get combinedPillLabel;

  /// No description provided for @mathEngCountSummary.
  ///
  /// In uz, this message translates to:
  /// **'Matematika: {math} ta  Ingliz tili: {eng} ta'**
  String mathEngCountSummary(int math, int eng);

  /// No description provided for @testDataEmptyMsg.
  ///
  /// In uz, this message translates to:
  /// **'Test ma\'lumotlari bo\'sh (variants topilmadi)'**
  String get testDataEmptyMsg;

  /// No description provided for @testLoadErrorMsg.
  ///
  /// In uz, this message translates to:
  /// **'Test yuklanmadi: {error}'**
  String testLoadErrorMsg(String error);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ru', 'uz'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ru':
      return AppLocalizationsRu();
    case 'uz':
      return AppLocalizationsUz();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
