// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Uzbek (`uz`).
class AppLocalizationsUz extends AppLocalizations {
  AppLocalizationsUz([String locale = 'uz']) : super(locale);

  @override
  String get appTitle => 'Alochi Monitoring';

  @override
  String get loginTitle => 'Kirish';

  @override
  String get languageUzbek => 'O\'zbek';

  @override
  String get languageRussian => 'Русский';

  @override
  String get bossCreateTitle => 'Kitobdan test yaratish';

  @override
  String get logout => 'Chiqish';

  @override
  String get serverChecking => 'Server tekshirilmoqda...';

  @override
  String get serverConnected => 'Server bilan ulandi';

  @override
  String get offlineMode => 'Offline rejim';

  @override
  String get invalidCredentials => 'Login yoki parol noto\'g\'ri';

  @override
  String get tooManyAttempts => 'Ko\'p urinish. Biroz kuting.';

  @override
  String get serverErrorRetry => 'Server xatosi. Qayta urinib ko\'ring.';

  @override
  String get offlineNoSavedLogin =>
      'Internet yo\'q va bu login ilgari saqlanmagan.';

  @override
  String get connectionError => 'Ulanishda xatolik';

  @override
  String get loggingIn => 'Kirish...';

  @override
  String get appSubtitle => 'Ta\'lim monitoring platformasi';

  @override
  String get testsRoute => 'Testlar';

  @override
  String get comingSoon => 'Tez kunda';

  @override
  String get retryCheck => 'Qayta tekshirish';

  @override
  String get loginInstruction => 'Login va parolni o\'qituvchingizdan oling';

  @override
  String get usernameLabel => 'Login';

  @override
  String get passwordLabel => 'Parol';

  @override
  String get usernameRequired => 'Login kiriting';

  @override
  String get passwordRequired => 'Parol kiriting';

  @override
  String get offlineLogin => 'Offline kirish';

  @override
  String get localGradeEntry => 'Oddiy kirish (Internet kerak emas)';

  @override
  String get monitoringTestUnit1 => 'Monitoring Test Unit 1';

  @override
  String get offlineHistory => 'Oflayn Tarix';

  @override
  String get selectPdfFirst => 'Avval PDF fayl tanlang';

  @override
  String get aiGeneratingMessage =>
      'AI savollar yaratmoqda...\nBu 1-2 daqiqa olishi mumkin';

  @override
  String get enterPackageTitle => 'Paket sarlavhasini kiriting';

  @override
  String get savingMessage => 'Saqlanyapti...';

  @override
  String get backButton => 'Orqaga';

  @override
  String get packageTitleLabel => 'Paket sarlavhasi';

  @override
  String saveAndPublish(int grade, int variantCount) {
    return 'Saqlash va nashr etish ($grade-sinf, $variantCount variant)';
  }

  @override
  String get questionTextLabel => 'Savol matni';

  @override
  String variantLetterLabel(String letter) {
    return 'Variant $letter';
  }

  @override
  String get aiImagePromptHint => 'AI rasm taklifi (saqlanmaydi):';

  @override
  String get mathSubject => 'Math';

  @override
  String get englishSubject => 'Ingliz';

  @override
  String get selectPdfBook => 'PDF kitob tanlang';

  @override
  String get pdfFileHint => '.pdf fayl, max 10MB, 50 bet';

  @override
  String get subjectLabel => 'Fan';

  @override
  String get gradeLabel => 'Sinf';

  @override
  String get questionCountLabel => 'Savollar soni';

  @override
  String get variantCountLabel => 'Variant soni';

  @override
  String get generateWithAi => 'AI bilan savollar yaratish';

  @override
  String gradeN(int n) {
    return '$n-sinf';
  }

  @override
  String nQuestions(int n) {
    return '$n ta savol';
  }

  @override
  String nVariants(int n) {
    return '$n variant';
  }

  @override
  String questionIndex(int index) {
    return '$index-savol';
  }

  @override
  String get enterFirstAndLastName => 'Ism va familiyani kiriting';

  @override
  String get incorrectSecretPassword =>
      'Maxfiy parol noto\'g\'ri (Maslahat: 1234)';

  @override
  String errorPrefix(String error) {
    return 'Xato: $error';
  }

  @override
  String get selectVariant => 'Variantni tanlang';

  @override
  String get studentInfoTitle => 'O\'quvchi ma\'lumotlari';

  @override
  String get localTestInfo =>
      '2-sinf Ingliz tili — Interhouse testi\n10 variant · 30 savol · Offline rejim';

  @override
  String get continueButton => 'Davom etish';

  @override
  String get firstNameLabel => 'Ism';

  @override
  String get firstNameHint => 'Alisher';

  @override
  String get lastNameLabel => 'Familiya';

  @override
  String get lastNameHint => 'Karimov';

  @override
  String get groupGradeLabel => 'Guruh / Sinf';

  @override
  String get groupGradeHint => '3-A';

  @override
  String get schoolNameLabel => 'Maktab nomi';

  @override
  String get schoolNameHint => '12-maktab';

  @override
  String get pinCodeLabel => 'Parol (PIN kod)';

  @override
  String get startTest => 'Testni boshlash';

  @override
  String get combinedTestInfo => '79 savol · 75 daqiqa · Offline rejim';

  @override
  String get combinedTestSubjects => '30 matematika + 49 ingliz tili';

  @override
  String get incorrectPassword => 'Maxfiy parol noto\'g\'ri';

  @override
  String get confirmLogout => 'Hisobdan chiqmoqchimisiz?';

  @override
  String get cancel => 'Bekor qilish';

  @override
  String get noActiveExamOrExpired =>
      'Faol imtihon topilmadi yoki muddati tugagan';

  @override
  String get loadFailed => 'Yuklanmadi. Qayta urinib ko\'ring.';

  @override
  String gradeClass(int grade) {
    return '$grade-sinf';
  }

  @override
  String variantBadge(int variant) {
    return 'Variant $variant';
  }

  @override
  String get selectTest => 'Test tanlang';

  @override
  String get selectMonitoringTest =>
      'Mavjud monitoring testlaridan birini tanlang';

  @override
  String get retry => 'Qayta urinish';

  @override
  String get noActiveExam => 'Aktiv imtihon yo\'q';

  @override
  String get noExamAssignedOrExpired =>
      'Sizga hali imtihon biriktirilmagan\nyoki muddati tugagan';

  @override
  String get testsNotLoadedYet => 'Testlar hali yuklanmagan';

  @override
  String get tryAgainAfterTeacherUploads =>
      'O\'qituvchingiz test yuklagandan so\'ng\nqayta urinib ko\'ring';

  @override
  String get refresh => 'Yangilash';

  @override
  String get totalLabel => 'Jami';

  @override
  String get helloGreeting => 'Salom!';

  @override
  String get mathSubjectFull => 'Matematika';

  @override
  String get englishSubjectFull => 'Ingliz tili';

  @override
  String get finishConfirmTitle => 'Tugatish?';

  @override
  String unansweredWarning(int unanswered) {
    return '$unanswered ta savol javobsiz qoldi. Shunga qaramay tugatmoqchimisiz?';
  }

  @override
  String get mathSectionLabel => 'Matematika bo\'limi';

  @override
  String get engSectionLabel => 'Ingliz tili bo\'limi';

  @override
  String get keyboardButtons => 'tugmalar';

  @override
  String get previousButton => 'Oldingi';

  @override
  String get nextButton => 'Keyingi';

  @override
  String get answeredLabel => 'javoblandi';

  @override
  String get uploadingLabel => 'Yuklanmoqda';

  @override
  String get timeLeftLabel => 'qoldi';

  @override
  String get engSectionTransitionTitle => 'Ingliz tili bo\'limiga o\'tildi';

  @override
  String get engSectionTransitionDesc =>
      '40 daqiqa · Keyingi savollar ingliz tilida';

  @override
  String get imageLoadFailed => 'Rasm yuklanmadi';

  @override
  String pdfError(String error) {
    return 'PDF xatosi: $error';
  }

  @override
  String get congratsTitle => 'Tabriklaymiz!';

  @override
  String get goodEffortTitle => 'Yaxshi harakat!';

  @override
  String get testFinishedSuccess => 'Test muvaffaqiyatli yakunlandi';

  @override
  String get betterNextTime => 'Keyingi safarida yaxshiroq bo\'ladi!';

  @override
  String get scorePoint => 'ball';

  @override
  String get passedMessage => 'Tabriklaymiz! O\'tdingiz!';

  @override
  String get failedMessage => 'O\'tmadi. Harakat qiling!';

  @override
  String get totalScoreLabel => 'Jami ball';

  @override
  String get syncedSuccess => 'Natija serverga muvaffaqiyatli yuborildi';

  @override
  String get savedOffline =>
      'Offline saqlandi. Internet bo\'lganda avtomatik yuboriladi';

  @override
  String get pdfReady => 'PDF tayyor';

  @override
  String get downloadPdf => 'PDF yuklab olish';

  @override
  String get nextStudent => 'Keyingi talaba';

  @override
  String wrongAnswersCount(int count) {
    return 'Xato javoblar — $count ta';
  }

  @override
  String wrongAnswersBreakdown(int math, int eng) {
    return 'Mat: $math  ·  Ing: $eng';
  }

  @override
  String get statusGood => 'Yaxshi ✓';

  @override
  String get statusAverage => 'O\'rtacha';

  @override
  String get statusWeak => 'Zaif — mashq kerak';

  @override
  String get subjectAnalysisTitle => 'Mavzu tahlili';

  @override
  String get mathTipLow1 =>
      'Asosiy amallar (qo\'shish, ayirish, ko\'paytirish, bo\'lish)ni qayta o\'rganing.';

  @override
  String get mathTipLow2 => 'Har kuni 20 daqiqa misollar yeching.';

  @override
  String get mathTipLow3 => '2-sinf dasturidan boshlang.';

  @override
  String get mathTipMed1 => 'Jadval va kasr sonlarni mustahkamlang.';

  @override
  String get mathTipMed2 =>
      'Xato qilgan savollar turini aniqlang va shu mavzuga e\'tibor bering.';

  @override
  String get mathTipMed3 => 'Har kuni 2-3 ta test masala yeching.';

  @override
  String get mathTipHigh1 =>
      'Qiyin masalalar (muammo masalalar) ustida ishlang.';

  @override
  String get mathTipHigh2 => 'Vaqtni boshqarishni mashq qiling.';

  @override
  String get mathTipHigh3 => 'Har savolga 1-2 daqiqa ajrating.';

  @override
  String get mathTipExc1 => 'Ajoyib!';

  @override
  String get mathTipExc2 =>
      'Murakkab olimpiada masalalarini hal qilishga o\'ting.';

  @override
  String get mathTipExc3 =>
      'Natijani barqaror saqlash uchun muntazam mashq qiling.';

  @override
  String get engTipLow1 =>
      'Kunlik 10 ta yangi so\'z yodlang (flashcard usuli).';

  @override
  String get engTipLow2 =>
      'Asosiy grammatika: to be, present simple, plural nouns.';

  @override
  String get engTipLow3 =>
      'BBC Learning English, Duolingo ilovalaridan foydalaning.';

  @override
  String get engTipMed1 =>
      'Past simple va present continuous grammatikasini o\'rganing.';

  @override
  String get engTipMed2 => 'Har kuni inglizcha 1 ta qisqa matn o\'qing.';

  @override
  String get engTipMed3 => 'So\'z boyligini mavzu bo\'yicha guruhlab yodlang.';

  @override
  String get engTipHigh1 => 'Tinglash ko\'nikmalarini rivojlantiring.';

  @override
  String get engTipHigh2 => 'YouTube ingliz kontentidan foydalaning.';

  @override
  String get engTipHigh3 => 'Esselar va qisqa hikoyalar yozing.';

  @override
  String get engTipExc1 => 'Ajoyib!';

  @override
  String get engTipExc2 => 'IELTS/Cambridge sertifikati uchun tayyorlaning.';

  @override
  String get engTipExc3 =>
      'Murakkab matnlarni o\'qish va tinglashni davom ettiring.';

  @override
  String get statusGold => 'Oltin medal darajasi! Davom eting!';

  @override
  String get statusGoodMsg => 'Yaxshi natija! Yana bir oz harakat kerak.';

  @override
  String get statusSatisfactory =>
      'Qoniqarli. Tavsiyalarga amal qiling va qayta sinab ko\'ring.';

  @override
  String get statusKeepTrying =>
      'Xafa bo\'lmang! Har bir muvaffaqiyatsizlik yangi boshlang\'ich.';

  @override
  String pdfTitle(String name) {
    return 'Natija - $name';
  }

  @override
  String get subjectsResultTitle => 'Fanlar bo\'yicha natija';

  @override
  String get totalCorrectAnswers => 'Jami to\'g\'ri javoblar:';

  @override
  String get howToImprove => 'Qanday yaxshilash mumkin?';

  @override
  String get mathRecommendations => 'Matematika tavsiyalari';

  @override
  String get englishRecommendations => 'Ingliz tili tavsiyalari';

  @override
  String get wrongAnswersTitle => 'Xato javoblar';

  @override
  String get wrongAnswersAnalysis => 'Xato javoblar tahlili';

  @override
  String get studentLabel => 'O\'quvchi';

  @override
  String get passed => 'O\'tdi';

  @override
  String get failed => 'O\'tmadi';

  @override
  String get keepTrying => 'Harakat qiling!';

  @override
  String get monitoringTestResult => 'Monitoring test natijasi';

  @override
  String get alochiMonitoringSystem => 'Alochi Monitoring tizimi';

  @override
  String get homePage => 'Bosh sahifa';

  @override
  String get savePdf => 'PDF Saqlash';

  @override
  String get printPdf => 'Chop etish';

  @override
  String get sharePdf => 'Ulashish';

  @override
  String get loadingLabelDots => 'Yuklanmoqda...';

  @override
  String get errorLater => 'Xatolik. Keyinroq yuboriladi.';

  @override
  String get gradeAndVariant => 'Sinf va Variant';

  @override
  String get overallResult => 'Umumiy Natija';

  @override
  String get topicAnalysisTitle => 'Mavzular bo\'yicha tahlil';

  @override
  String get topicName => 'Mavzu nomi';

  @override
  String get correctAnswersCount => 'To\'g\'ri javoblar';

  @override
  String get percentage => 'Foiz';

  @override
  String get offlineTestResult => 'Oflayn Test Natijasi';
}
