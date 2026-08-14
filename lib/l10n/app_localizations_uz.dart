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
  String get onlineStatus => 'Onlayn';

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
  String get studentLoginButton => 'O\'quvchi sifatida kirish';

  @override
  String get myTestsTitle => 'Mening testlarim';

  @override
  String get myTestsEmpty => 'Sizga tegishli testlar topilmadi';

  @override
  String get retryCheck => 'Qayta tekshirish';

  @override
  String get sidebarHome => 'Bosh sahifa';

  @override
  String get sidebarResults => 'Natijalar';

  @override
  String get sidebarMessages => 'Xabarlar';

  @override
  String get sidebarCertificates => 'Sertifikatlar';

  @override
  String get sidebarSettings => 'Sozlamalar';

  @override
  String get sidebarHelp => 'Yordam';

  @override
  String get kpiTestsCompleted => 'Topshirilgan testlar';

  @override
  String get kpiAverageScore => 'O\'rtacha ball';

  @override
  String get kpiStreakDays => 'Ketma-ket kunlar';

  @override
  String get searchTestsHint => 'Testlarni qidirish...';

  @override
  String get filterAll => 'Barchasi';

  @override
  String get filterInProgress => 'Davom etyapti';

  @override
  String get filterCompleted => 'Tugallangan';

  @override
  String get filterLocked => 'Qulflangan';

  @override
  String get allSubjects => 'Barcha fanlar';

  @override
  String get otherSubject => 'Boshqa';

  @override
  String get continueTest => 'Davom ettirish';

  @override
  String get viewResult => 'Natijani ko\'rish';

  @override
  String get viewAllResults => 'Barcha natijalarni ko\'rish';

  @override
  String questionCountLabel(int count) {
    return '$count ta savol';
  }

  @override
  String durationMinutesLabel(int minutes) {
    return '$minutes daqiqa';
  }

  @override
  String get recentResultsTitle => 'So\'nggi natijalar';

  @override
  String get noResultsYet => 'Hali natijalar yo\'q';

  @override
  String get noFilterMatches => 'Filtrga mos test topilmadi';

  @override
  String get resultsScreenTitle => 'Mening natijalarim';

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
  String get selectTest => 'Testni tanlang';

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
  String get finishConfirmAllAnsweredPrompt =>
      'Barcha javoblar belgilandi. Testni yakunlaysizmi?';

  @override
  String get testAutoSubmittedNotice =>
      'Test vaqti tugadi, saqlangan javoblaringiz avtomatik yuborildi.';

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

  @override
  String get clearHistoryTitle => 'Tozalash';

  @override
  String get clearHistoryConfirm =>
      'Barcha natijalar tarixi o\'chirib yuborilsinmi?';

  @override
  String get noWord => 'Yo\'q';

  @override
  String get yesDelete => 'Ha, o\'chirish';

  @override
  String get offlineHistoryTitle => 'Oflayn Natijalar Tarixi';

  @override
  String get noHistoryYet => 'Hozircha tarix yo\'q';

  @override
  String get schoolLabel => 'Maktab';

  @override
  String get dateLabel => 'Sana';

  @override
  String get mathShort => 'Mat';

  @override
  String get engShort => 'Ing';

  @override
  String syncCompleteMsg(String done) {
    return 'Sinxronizatsiya yakunlandi! $done ta rasm oflayn saqlandi.';
  }

  @override
  String get errorOccurred => 'Xato yuz berdi: ';

  @override
  String get offlineImagesLoading => 'Oflayn rasmlar yuklanmoqda...';

  @override
  String savedOutOfTotal(String done, String total) {
    return '$done / $total ta saqlandi';
  }

  @override
  String get syncImagesOfflineButton => 'Oflayn rasmlarni tayyorlash (Sync)';

  @override
  String get localResSending => '📤 Yuborilmoqda...';

  @override
  String get localResSavedSending => '✅ Saqlandi, yuborilmoqda...';

  @override
  String get localResSaveError => '❌ Saqlashda xato. Qayta urinib ko\'ring.';

  @override
  String get localResBarakalla => 'Barakalla!';

  @override
  String get localResYaxshi => 'Yaxshi!';

  @override
  String get nextStudentButton => 'Keyingi o\'quvchi';

  @override
  String get questionsUnansweredPrompt =>
      'ta savol javobsiz. Tugatmoqchimisiz?';

  @override
  String get finishButtonText => 'Tugatish';

  @override
  String get gradeWord => '-sinf';

  @override
  String get mathSectionTimeUp => 'Matematika bo\'limi vaqti tugagan!';

  @override
  String get engSectionTimeUp => 'Ingliz tili bo\'limi vaqti tugagan!';

  @override
  String get finishTest => 'Tugatish';

  @override
  String get uploadTest => 'Yuklash';

  @override
  String get resultNotSavedError =>
      'Natija saqlanmadi — internet yoki xotira muammosi. Qayta urinib ko\'ring.';

  @override
  String get testLoadFailed => 'Test yuklanmadi';

  @override
  String get testTitle => 'Test';

  @override
  String get gradeExcellent => 'A\'lo';

  @override
  String get gradeGood => 'Yaxshi';

  @override
  String get gradeSatisfactory => 'Qoniqarli';

  @override
  String get gradeNeedsPractice => 'Qo\'shimcha mashq kerak';

  @override
  String get pdfGenerationError => 'PDF yaratishda xato';

  @override
  String get resultTitle => 'Natija';

  @override
  String correctAnswersWithCount(String count) {
    return 'To\'g\'ri $count';
  }

  @override
  String wrongAnswersWithCount(String count) {
    return 'Xato $count';
  }

  @override
  String shieldsCount(String count) {
    return '$count qalqon';
  }

  @override
  String get sectionsByTitle => 'BO\'LIMLAR BO\'YICHA';

  @override
  String get noDataAvailable => 'Ma\'lumot yo\'q';

  @override
  String get reopenPdf => 'PDF qayta ochish';

  @override
  String get pdfReportButton => 'PDF hisobot';

  @override
  String get aiAnalysisTitle => 'AI tahlil';

  @override
  String get analysisPreparing => 'Tahlil tayyorlanmoqda…';

  @override
  String get strongSidesTitle => 'Kuchli tomonlar';

  @override
  String get weakSidesTitle => 'Zaif tomonlar';

  @override
  String get recommendationsTitle => 'Tavsiyalar';

  @override
  String get focus14DaysTitle => '14 kunlik e\'tibor';

  @override
  String get subjectAnalysisByTopic => 'Mavzu bo\'yicha tahlil';

  @override
  String get subjectAnalysisByUnit => 'Unitlar bo\'yicha tahlil';

  @override
  String get subjectAnalysisByParagraph => 'Paragraf bo\'yicha taqsimot';

  @override
  String get strongAndWeakSides => 'Kuchli va zaif tomonlar';

  @override
  String get strongLabel => 'Kuchli';

  @override
  String get needsReinforcement => 'Mustahkamlash kerak';

  @override
  String get weakTopicFallback => 'zaif mavzu';

  @override
  String get days1to3 => '1–3 kun';

  @override
  String weakestTopicPlan(String topic) {
    return 'Eng zaif mavzu: $topic (15 daqiqa/kun)';
  }

  @override
  String get days4to7 => '4–7 kun';

  @override
  String secondTopicPlan(String topic) {
    return 'Ikkinchi mavzu: $topic (5 ta misol/kun)';
  }

  @override
  String get days8to11 => '8–11 kun';

  @override
  String get mixedExercisesPlan =>
      'Aralash mashqlar — barcha mavzularni takrorlash';

  @override
  String get days12to14 => '12–14 kun';

  @override
  String get controlTestPlan => 'Nazorat testi — natijani solishtirish';

  @override
  String get plan14DaysTitle => '14 kunlik reja';

  @override
  String get sending => 'Yuborilmoqda...';

  @override
  String get savedSuccess => 'Saqlandi!';

  @override
  String get savedOfflineLater => 'Saqlandi (offline — keyinroq yuboriladi)';

  @override
  String get savedSending => 'Saqlandi, yuborilmoqda...';

  @override
  String get interhouseGrade2 => 'Interhouse Grade 2';

  @override
  String get sectionsBreakdown => 'Bo\'limlar bo\'yicha';

  @override
  String get nextStudentBtn => 'Keyingi o\'quvchi';

  @override
  String get finishBtn => 'Tugatish';

  @override
  String get mathQuestionsNotFound => 'Matematika savollari topilmadi.';

  @override
  String get generalTests => 'Umumiy testlar';

  @override
  String get loadingGroups => 'Guruhlar yuklanmoqda...';

  @override
  String get selectGroup => 'Guruhni tanlang';

  @override
  String get selectStudent => 'O\'quvchini tanlang';

  @override
  String get selectGrade => 'Sinfni tanlang';

  @override
  String get selectSchool => 'Maktabni tanlang';

  @override
  String get incorrectPin => 'PIN noto\'g\'ri';

  @override
  String get enterFourDigitPin => 'To\'rt xonali PIN kodni kiriting';

  @override
  String get showPassword => 'Ko\'rsatish';

  @override
  String get hidePassword => 'Yashirish';

  @override
  String get confirmBtn => 'Tasdiqlash';

  @override
  String get nextStepStudentName => 'Keyingi qadam: o\'quvchi ismini kiritish';

  @override
  String get testSession => 'Sinov sessiyasi';

  @override
  String get testSessionInstruction =>
      'Sinov sessiyasini boshlash uchun maktabni tanlang va PIN kodni kiriting.';

  @override
  String get sessionSettings => 'Sessiya sozlamalari';

  @override
  String get studentNameStep => 'O\'quvchi ismi';

  @override
  String get testLocked => 'Bu test hali qulflangan.';

  @override
  String get testNotInCache => 'Test keshda topilmadi. Qayta yuklab oling.';

  @override
  String get sessionConflictOtherDevice =>
      'Bu o\'quvchi boshqa qurilmada testni allaqachon boshlagan.';

  @override
  String get schools => 'Maktablar';

  @override
  String get otherSchools => 'Boshqa maktablar';

  @override
  String get schoolCodeOrName => 'Maktab kodi / nomi';

  @override
  String get downloaded => 'Yuklab olingan';

  @override
  String get downloading => 'Yuklab olinmoqda';

  @override
  String get enterSchoolError => 'Maktabni kiriting';

  @override
  String schoolPrefix(String code) {
    return '$code-maktab';
  }

  @override
  String get enterNameError => 'Ism va familiyani kiriting';

  @override
  String get lastName => 'Familiya';

  @override
  String get firstName => 'Ism';

  @override
  String get groupOptional => 'Guruh (ixtiyoriy)';

  @override
  String get variant => 'Variant';

  @override
  String get start => 'Boshlash';

  @override
  String get downloadError => 'Yuklashda xato. Qayta urinib ko\'ring.';

  @override
  String get testsNotFound => 'Testlar topilmadi';

  @override
  String get opensAt => 'da ochiladi';

  @override
  String get newVersionAvailable => 'Yangi versiya mavjud';

  @override
  String get update => 'Yangilash';

  @override
  String get download => 'Yuklash';

  @override
  String get confirmSessionTitle => 'Sessiyani\ntasdiqlang';

  @override
  String get pinCodeRequired => 'PIN KOD (MAJBURIY)';

  @override
  String get enterPinCode => 'PIN kodni kiriting';

  @override
  String get enterTeacherCode => 'O\'qituvchi bergan kodni kiriting';

  @override
  String get otherSchoolBtn => 'Boshqa maktab';

  @override
  String get groupsNotFound => 'Guruhlar topilmadi';

  @override
  String get testsNotFoundForGroup => 'Bu guruh uchun test topilmadi';

  @override
  String get notDownloaded => 'Yuklab olinmagan';

  @override
  String get stillLocked => 'Hali qulflangan';

  @override
  String get ready => 'Tayyor';

  @override
  String get newBadge => 'Yangi';

  @override
  String newBadgeAddedOn(String date) {
    return 'Qo\'shildi: $date';
  }

  @override
  String get whoTakesTest => 'Testni kim\ntopshiradi?';

  @override
  String get studentsInList => 'o\'quvchi ro\'yxatda mavjud';

  @override
  String get gradeShort => 'sinf';

  @override
  String get backBtn => 'Ortga';

  @override
  String get copyName => 'Nusxa olish';

  @override
  String nameCopied(String name) {
    return '$name nusxalandi!';
  }

  @override
  String get searchStudents => 'O\'quvchini izlash (Ctrl+K)...';

  @override
  String get back => 'Orqaga';

  @override
  String get finish => 'Tugatish';

  @override
  String get errorTitle => 'Xatolik';

  @override
  String get returnToHome => 'Bosh sahifaga qaytish';

  @override
  String get routeNotFound => 'Route not found';

  @override
  String get reportGenerationError => 'Hisobot yaratishda xato';

  @override
  String get printBtn => 'Chop etish';

  @override
  String get downloadBtn => 'Yuklab olish';

  @override
  String get exitBtn => 'Chiqish';

  @override
  String get yesBtn => 'Ha';

  @override
  String get updateBtn => 'Yangilanish';

  @override
  String get updateDownloadFailedMsg =>
      'Yangilanishni yuklab bo\'lmadi. Internet aloqasini tekshirib, qayta urining.';

  @override
  String get okBtn => 'Yaxshi';

  @override
  String get yesOption => 'YES';

  @override
  String get noOption => 'NO';

  @override
  String get alisherHint => 'Alisher';

  @override
  String get vocabularyTopic => 'Vocabulary';

  @override
  String get grammarTopic => 'Grammar';

  @override
  String get spellingTopic => 'Spelling';

  @override
  String get sentencesTopic => 'Sentences';

  @override
  String get readingTopic => 'Reading';

  @override
  String get checkForUpdates => 'Check for Updates...';

  @override
  String get appNameTitle => 'Alochi Monitoring';

  @override
  String get bobEmptySectionMsg => 'Bu bo\'lim bo\'sh.';

  @override
  String get returnBtn => 'Qaytish';

  @override
  String get sectionsResultTitle => 'Bo\'limlar natijasi';

  @override
  String get vocabularyQuestionsNotFoundMsg =>
      'Vocabulary savollari topilmadi.';

  @override
  String get grammarQuestionsNotFoundMsg => 'Grammar savollari topilmadi.';

  @override
  String get spellingQuestionsNotFoundMsg => 'Spelling savollari topilmadi.';

  @override
  String get sentencesQuestionsNotFoundMsg => 'Sentences savollari topilmadi.';

  @override
  String get readingQuestionsNotFoundMsg => 'Reading savollari topilmadi.';

  @override
  String get variantsNotFoundMsg => 'Variantlar topilmadi.';

  @override
  String get arrangeLettersPrompt => 'Harflarni to\'g\'ri joylashtiring';

  @override
  String get arrangeSentencePrompt => 'Jumlani to\'g\'ri tartibga soling';

  @override
  String get arrangeEventsPrompt => 'Voqealarni to\'g\'ri tartibda belgilang';

  @override
  String get selectVariantsInOrderPrompt =>
      'Quyidagi variantlarni to\'g\'ri ketma-ketlikda tanlang';

  @override
  String get clearSelectionBtn => 'Tozalash';

  @override
  String get variantsSectionHeader => 'VARIANTLAR';

  @override
  String get answerHintText => 'Javob...';

  @override
  String get fullSentenceHintText => 'To\'liq jumlani yozing...';

  @override
  String sessionGradeVariantLabel(String grade, String variant) {
    return '$grade-sinf · Variant $variant';
  }

  @override
  String get reportSavedButOpenFailedMsg =>
      'Hisobot saqlandi, lekin ochib bo\'lmadi';

  @override
  String get bob14ScreenTitle => '2-sinf — Bob 1-4 Monitoringi';

  @override
  String get bob14TestInfo => '30 savol · 45 daqiqa · Offline rejim';

  @override
  String get unit1ScreenTitle => '1-sinf Ingliz tili — Unit 1';

  @override
  String get unit1TestInfo => '49 savol · 49 daqiqa · Offline rejim';

  @override
  String get unit1RunnerHeaderTitle => '1-sinf Unit 1 — Ingliz tili';

  @override
  String correctFractionLabel(int correct, int total) {
    return '$correct / $total to\'g\'ri';
  }

  @override
  String get hujjatlarLabel => 'Hujjatlar';

  @override
  String get noDocumentsMsg => 'Hujjat yo\'q';

  @override
  String savedFileMsg(String path) {
    return 'Saqlandi: $path';
  }

  @override
  String get exitConfirmationMessage =>
      'Haqiqatan ham chiqmoqchimisiz? Kiritilgan ma\'lumotlar saqlanmaydi.';

  @override
  String get pageNotFoundTitle => 'Sahifa topilmadi';

  @override
  String get pageNotFoundMessage =>
      'Kechirasiz, siz qidirayotgan sahifa mavjud emas yoki ko\'chirilgan.';

  @override
  String get monitoringTestHeader => 'MONITORING TEST';

  @override
  String get testDataNotFoundMsg => 'Test ma\'lumotlari topilmadi';

  @override
  String get updateUpToDateMessage =>
      'Sizda dasturning eng so\'nggi versiyasi o\'rnatilgan.';

  @override
  String shieldsProgressLabel(int count) {
    return '$count/25 shields';
  }

  @override
  String get diagnosticPassportHeader => 'A\'LOCHI — DIAGNOSTIK PASPORT';

  @override
  String get totalQuestionsCountLabel => 'Jami savol';

  @override
  String get correctAnswerLabelPdf => 'To\'g\'ri javob';

  @override
  String get wrongAnswerLabelPdf => 'Xato javob';

  @override
  String get topicAnalysisHeader => 'MAVZU BO\'YICHA TAHLIL';

  @override
  String get unitAnalysisHeader => 'UNIT BO\'YICHA TAHLIL';

  @override
  String get fourteenDayPlanHeader => '14 KUNLIK REJA';

  @override
  String get aiSummaryHeader => 'AI XULOSA';

  @override
  String get alochiAiLabel => 'A\'LOCHI AI';

  @override
  String get forParentsLabel => 'Ota-onaga';

  @override
  String get parentTipsText =>
      '• Har kuni 20–30 daqiqa o\'qish vaqti\n• Zaif mavzularni birgalikda takrorlang\n• Rag\'batlantiring va sabr bilan o\'rgating';

  @override
  String get footerBrandTagline => 'A\'lochi Ta\'lim · alochi.uz';

  @override
  String get dayRange1_3 => '1–3 KUN';

  @override
  String get dayRange4_7 => '4–7 KUN';

  @override
  String get dayRange8_11 => '8–11 KUN';

  @override
  String get dayRange12_14 => '12–14 KUN';

  @override
  String get dailyPractice15MinMsg => 'Har kuni 15 daqiqa mashq';

  @override
  String get dailyExamples5Msg => 'Har kuni 5 ta misol yechish';

  @override
  String get mixedExercisesTopic => 'Aralash mashqlar';

  @override
  String get reviewAllTopicsMsg => 'Barcha mavzularni takrorlash';

  @override
  String get controlTestTopic => 'Nazorat testi';

  @override
  String get compareResultsMsg => 'Natijalarni solishtirish';

  @override
  String get wellMasteredBadge => 'Yaxshi o\'zlashtirilgan';

  @override
  String get needsReviewBadge => 'Qayta o\'rganish';

  @override
  String aiSummaryFallbackMsg(String firstName, int pct) {
    return '$firstName $pct% natija ko\'rsatdi. O\'zlashtirish darajasiga qarab 14 kunlik reja bilan ishlash tavsiya etiladi.';
  }

  @override
  String get goodResultLabel => 'Yaxshi natija';

  @override
  String get searchOrCommandHint => 'Izlash yoki buyruq kiriting...';

  @override
  String get commandHistoryTitle => 'Oflayn tarix';

  @override
  String get commandLocalGradeTitle => 'Mahalliy baholash';

  @override
  String get commandCombinedTitle => 'Kombinatsiyalangan';

  @override
  String get bob14FallbackLabel => 'Bob 1-4';

  @override
  String get unit1FallbackLabel => 'Unit 1';

  @override
  String get saveErrorRetryMsg => 'Saqlashda xato. Qayta urinib ko\'ring.';

  @override
  String get unit1PillLabel => 'Unit 1 G1';

  @override
  String get interhousePillLabel => 'Interhouse G2';

  @override
  String get combinedPillLabel => 'Monitoring Unit 1';

  @override
  String mathEngCountSummary(int math, int eng) {
    return 'Matematika: $math ta  Ingliz tili: $eng ta';
  }

  @override
  String get testDataEmptyMsg =>
      'Test ma\'lumotlari bo\'sh (variants topilmadi)';

  @override
  String testLoadErrorMsg(String error) {
    return 'Test yuklanmadi: $error';
  }

  @override
  String get reportQuestionSheetTitle => 'Savol haqida xabar berish';

  @override
  String get reportReasonQuestionError => 'Savolda xatolik bor';

  @override
  String get reportReasonWrongOptions => 'Javob variantlari noto\'g\'ri';

  @override
  String get reportReasonImageTextMissing => 'Rasm/matn ko\'rinmayapti';

  @override
  String get reportReasonOther => 'Boshqa';

  @override
  String get reportCommentHint => 'Muammoni tavsiflang...';

  @override
  String get reportSubmitBtn => 'Yuborish';

  @override
  String get questionReportSentMsg => 'Xabaringiz yuborildi';

  @override
  String get questionReportFailedMsg =>
      'Yuborishda xato. Qayta urinib ko\'ring.';

  @override
  String get loadStudentsError =>
      'O\'quvchilar ro\'yxatini yuklab bo\'lmadi. Internetni tekshirib, qayta urinib ko\'ring.';

  @override
  String get noStudentsInGroup => 'Bu guruhda faol o\'quvchi topilmadi.';

  @override
  String get helpScreenTitle => 'Yordam va qo\'llab-quvvatlash';

  @override
  String get helpBannerTitle => 'Yordam kerak bo\'lsa, biz yoningizdamiz';

  @override
  String get helpBannerSubtitle =>
      'Tez-tez so\'raladigan savollarga javob toping, yo\'riqnomalarni ko\'ring va bir necha bosishda qo\'llab-quvvatlash bilan bog\'laning.';

  @override
  String get helpKpiFaqLabel => 'FAQ';

  @override
  String helpKpiFaqValue(int count) {
    return '$count ta maqola';
  }

  @override
  String get helpKpiSupportLabel => 'Qo\'llab-quvvatlash';

  @override
  String get helpKpiVersionLabel => 'Versiya';

  @override
  String get helpFaqSectionTitle => 'Tez-tez so\'raladigan savollar';

  @override
  String get helpFaqSearchHint => 'Savollar bo\'yicha qidirish...';

  @override
  String get helpFaqNoResults => 'Hech narsa topilmadi';

  @override
  String get helpFaqQ1 => 'Testni qanday boshlash mumkin?';

  @override
  String get helpFaqA1 =>
      '«Mening testlarim» bo\'limiga o\'ting, kerakli testni tanlang va «Boshlash» tugmasini bosing. Boshlashdan oldin internet aloqasi barqaror ekanligiga ishonch hosil qiling.';

  @override
  String get helpFaqQ2 => 'Internet uzilib qolsa nima qilish kerak?';

  @override
  String get helpFaqA2 =>
      'Xavotir olmang — javoblaringiz qurilmada saqlanadi. Internet tiklangach, dastur avtomatik ravishda serverga ulanadi va testni davom ettirishingiz mumkin.';

  @override
  String get helpFaqQ3 => 'O\'z natijalarimni qanday ko\'raman?';

  @override
  String get helpFaqA3 =>
      'Chap menyudagi «Natijalar» bo\'limiga o\'ting — u yerda barcha topshirilgan testlar bo\'yicha ball va statistikangizni ko\'rishingiz mumkin.';

  @override
  String get helpFaqQ4 => 'Parolni unutib qo\'ydim, nima qilaman?';

  @override
  String get helpFaqA4 =>
      'O\'quvchi login-parolini sinf rahbari yoki maktab administratori beradi. Parolni unutgan bo\'lsangiz, o\'qituvchingizga murojaat qiling — u sizga yangi ma\'lumotlarni tiklab beradi.';

  @override
  String get helpFaqQ5 => 'Sertifikatni qanday olsam bo\'ladi?';

  @override
  String get helpFaqA5 =>
      'Sertifikatlar bo\'limi tez orada ishga tushiriladi. Test natijalaringiz saqlanib boryapti — sertifikat funksiyasi qo\'shilgach, ular avtomatik hisoblab chiqiladi.';

  @override
  String get helpVideoSectionTitle => 'Video-yo\'riqnomalar';

  @override
  String get helpVideoComingSoonDesc =>
      'Video-qo\'llanmalar hozircha mavjud emas. Ular platformaga qo\'shilgach, bu yerda paydo bo\'ladi.';

  @override
  String get helpTroubleshootSectionTitle => 'Muammo yuzaga kelsa';

  @override
  String get helpTroubleshootInternetTitle => 'Internetni tekshiring';

  @override
  String get helpTroubleshootInternetDesc =>
      'Qurilma barqaror tarmoqqa ulanganiga ishonch hosil qiling.';

  @override
  String get helpTroubleshootRestartTitle => 'Dasturni qayta ishga tushiring';

  @override
  String get helpTroubleshootRestartDesc =>
      'Muammo davom etsa, dasturni yoping va qaytadan oching.';

  @override
  String get helpTroubleshootTeacherTitle =>
      'O\'qituvchingizga murojaat qiling';

  @override
  String get helpTroubleshootTeacherDesc =>
      'Muammo hal bo\'lmasa, tezroq yechim uchun o\'qituvchingizga xabar bering.';

  @override
  String get helpAboutSectionTitle => 'Ilova haqida';

  @override
  String get helpAboutVersionLabel => 'Ilova versiyasi';

  @override
  String get helpAboutServerLabel => 'Server';

  @override
  String get helpContactSectionTitle => 'Qo\'llab-quvvatlash bilan bog\'lanish';

  @override
  String get helpOpenTelegramBot => 'Telegram Botni ochish';

  @override
  String get helpSupportContactLabel => 'Alochi Support';

  @override
  String get helpSupportContactHandle => '@AlochiSupport';

  @override
  String get helpLinkOpenError => 'Havolani ochib bo\'lmadi';

  @override
  String get helpNoAnswerTitle => 'Javob topa olmadingizmi?';

  @override
  String get helpNoAnswerDesc =>
      'O\'qituvchingiz yoki maktab administratoriga murojaat qiling — ular sizga yordam berishadi.';

  @override
  String get kpiBestScore => 'Eng yuqori natija';

  @override
  String get resultsTrendTitle => 'Natijalar dinamikasi';

  @override
  String resultsTrendSubtitle(Object count) {
    return 'Oxirgi $count ta natija';
  }

  @override
  String get subjectPerformanceTitle => 'Fanlar bo\'yicha natija';

  @override
  String get searchResultsHint => 'Test nomi bo\'yicha qidirish...';

  @override
  String get sortNewestFirst => 'Avval yangi';

  @override
  String get sortOldestFirst => 'Avval eski';

  @override
  String get sortHighestScore => 'Yuqori ball bo\'yicha';

  @override
  String get gradeWeak => 'Past';

  @override
  String get downloadPdfButton => 'PDF hisobot';

  @override
  String get viewBreakdownButton => 'Batafsil tahlil';

  @override
  String get kpiAverageTime => 'O\'rtacha vaqt';

  @override
  String kpiAverageTimeHoursMinutes(int hours, int minutes) {
    return '$hours soat $minutes daq';
  }

  @override
  String get breakdownNoDataMessage =>
      'Bu natija uchun batafsil ma\'lumot mavjud emas';

  @override
  String get breakdownBobsTitle => 'Boblar bo\'yicha';

  @override
  String get breakdownTopicsTitle => 'Mavzular bo\'yicha';

  @override
  String get breakdownUnitsTitle => 'Yunitlar bo\'yicha';

  @override
  String get breakdownPartsTitle => 'Boshqa';

  @override
  String get breakdownQuestionsTitle => 'Savollar';

  @override
  String get breakdownNoQuestionDetailNote =>
      'Bu natija uchun savol-savol tafsiloti mavjud emas.';

  @override
  String get breakdownNoAnswer => 'Javob berilmagan';

  @override
  String get breakdownYourAnswer => 'Sizning javobingiz';

  @override
  String get breakdownCorrectAnswer => 'To\'g\'ri javob';

  @override
  String get quickActionsTitle => 'Tezkor amallar';

  @override
  String get refreshResultsAction => 'Yangilash';

  @override
  String get refreshResultsActionDesc => 'Ro\'yxatni qayta yuklash';

  @override
  String get settingsHeroTitle => 'Ilovani o\'zingizga moslang';

  @override
  String get settingsHeroSubtitle =>
      'Ko\'rinish, til, bildirishnomalar va hisob xavfsizligini boshqaring.';

  @override
  String get settingsHeroCurrentLanguage => 'Joriy til';

  @override
  String get themeLabel => 'Mavzu';

  @override
  String get themeLight => 'Yorug\'';

  @override
  String get themeDark => 'Qorong\'i';

  @override
  String get notificationsStatusOn => 'Yoqilgan';

  @override
  String get notificationsStatusOff => 'O\'chirilgan';

  @override
  String get accountSectionTitle => 'Hisob';

  @override
  String get classLabelCaption => 'Sinf';

  @override
  String get groupLabelCaption => 'Guruh';

  @override
  String get personalizationSectionTitle => 'Shaxsiylashtirish';

  @override
  String get fontSizeLabel => 'Shrift o\'lchami';

  @override
  String get fontSizeNormal => 'Oddiy';

  @override
  String get fontSizeLarge => 'Katta';

  @override
  String get languageRegionSectionTitle => 'Til va hudud';

  @override
  String get interfaceLanguageLabel => 'Interfeys tili';

  @override
  String get notificationsSectionTitle => 'Bildirishnomalar';

  @override
  String get notifSoundOnComplete => 'Test tugaganda tovush';

  @override
  String get notifRemindersNewTests => 'Yangi testlar haqida eslatmalar';

  @override
  String get notifHelperText =>
      'Bildirishnomalar muhim testlar va muddatlarni o\'tkazib yubormasligingizga yordam beradi.';

  @override
  String get securitySectionTitle => 'Xavfsizlik va sessiya';

  @override
  String get resetPasswordLabel => 'Parolni tiklash';

  @override
  String get resetPasswordHint =>
      'Parolni tiklash uchun o\'qituvchingiz yoki maktab administratoriga murojaat qiling.';

  @override
  String get logoutAllDevicesLabel => 'Barcha qurilmalardan chiqish';

  @override
  String get logoutAllDevicesHint => 'Bu turdagi kirish uchun mavjud emas';

  @override
  String get logoutAccountLabel => 'Hisobdan chiqish';

  @override
  String get logoutAccountHint => 'Joriy hisobdan chiqishni amalga oshiring';

  @override
  String get summarySectionTitle => 'Qisqacha ko\'rinish';

  @override
  String get tipsSectionTitle => 'Maslahatlar';

  @override
  String get tipsBody =>
      'O\'zgarishlar darhol qo\'llaniladi. Sozlamalar shu qurilmada saqlanadi.';

  @override
  String get certificatesScreenTitle => 'Sertifikatlar va yutuqlar';

  @override
  String get certificatesHeroTitle => 'Sizning yutuqlaringiz mukofotga loyiq!';

  @override
  String get certificatesHeroSubtitle =>
      'O\'qishda davom eting, nishonlar to\'plang va a\'lo natijalar uchun sertifikat qo\'lga kiriting.';

  @override
  String get certificatesKpiCountLabel => 'Olingan sertifikatlar';

  @override
  String get certificatesKpiBadgesLabel => 'Ochilgan nishonlar';

  @override
  String get badgeMathMasterTitle => 'Matematika ustasi';

  @override
  String get badgePerfectScoreTitle => '100% natija';

  @override
  String badgeStreakCount(int count) {
    return '$count kun ketma-ket';
  }

  @override
  String get badgeEnglishMasterTitle => 'Ingliz tili ustasi';

  @override
  String get badgeActiveStudentTitle => 'Faol o\'quvchi';

  @override
  String get badgeUnlockedLabel => 'Ochilgan';

  @override
  String get badgesAndAchievementsTitle => 'Nishonlar va yutuqlar';

  @override
  String get progressPanelTitle => 'Yutuqlar jarayoni';

  @override
  String get progressNoSubjectData => 'Fanlar bo\'yicha ma\'lumot hali yo\'q';

  @override
  String progressClosestBadge(String title, int pct) {
    return 'Eng yaqin: «$title» — $pct%';
  }

  @override
  String get certificatesSearchHint => 'Sertifikatlar bo\'yicha qidirish...';

  @override
  String get filterBadgesLabel => 'Nishonlar';

  @override
  String certificatesEmptyPrompt(int minScore) {
    return 'Birinchi sertifikatingizni olish uchun testni $minScore%+ natija bilan yakunlang';
  }

  @override
  String certificateIssuedOn(String date) {
    return '$date sanasida berilgan';
  }

  @override
  String get certificateGeneratingLabel => 'Tayyorlanmoqda...';

  @override
  String get certificateThumbnailLabel => 'SERTIFIKAT';

  @override
  String get diplomaIssuedToLabel => 'berildi';

  @override
  String diplomaForTestResultLabel(String title) {
    return '\"$title\" testidagi natija uchun';
  }

  @override
  String get messagesBannerTitle =>
      'Muhim yangiliklardan xabardor bo\'ling! 👋';

  @override
  String get messagesBannerSubtitle =>
      'Bu yerda o\'qituvchilardan xabarlar, testlar haqida bildirishnomalar va tizim ogohlantirishlarini topasiz.';

  @override
  String get messagesKpiUnreadLabel => 'O\'qilmagan';

  @override
  String get messagesKpiNewTestsLabel => 'Yangi testlar';

  @override
  String get messagesKpiReviewedLabel => 'Tekshirilgan natijalar';

  @override
  String get messagesFilterAll => 'Barchasi';

  @override
  String get messagesFilterTeacher => 'O\'qituvchilardan';

  @override
  String get messagesFilterTests => 'Testlar haqida bildirishnomalar';

  @override
  String get messagesFilterSystem => 'Tizim xabarlari';

  @override
  String get messagesSearchHint => 'Xabarlar bo\'yicha qidiruv...';

  @override
  String get messagesEmptyListTitle => 'Xabarlar topilmadi';

  @override
  String get messagesNoSelectionTitle => 'Xabarni tanlang';

  @override
  String get messagesNoSelectionSubtitle =>
      'Tafsilotlarni ko\'rish uchun chapdagi xabarni bosing.';

  @override
  String get messagesTypeTeacher => 'O\'qituvchi';

  @override
  String get messagesTypeTest => 'Test';

  @override
  String get messagesTypeSystem => 'Tizim';

  @override
  String get messagesSenderLabel => 'Kimdan';

  @override
  String get messagesSenderTeacher => 'O\'qituvchi';

  @override
  String get messagesSenderTestSystem => 'Test tizimi';

  @override
  String get messagesSenderSystem => 'Tizim';

  @override
  String get messagesGoToTestButton => 'Testga o\'tish';

  @override
  String get messagesMarkReadButton => 'O\'qilgan deb belgilash';

  @override
  String get messagesMarkAllReadTitle => 'Barchasini o\'qilgan qilish';

  @override
  String get messagesMarkAllReadSubtitle =>
      'Barcha xabarlarni o\'qilgan deb belgilash';

  @override
  String get messagesNotificationSettingsTitle => 'Bildirishnoma sozlamalari';

  @override
  String get messagesNotificationSettingsSubtitle =>
      'Bildirishnoma olish usullarini boshqaring';

  @override
  String get messagesArchiveTitle => 'Xabarlar arxivi';

  @override
  String get messagesArchiveSubtitle => 'Arxivlangan xabarlarni ko\'rish';

  @override
  String get messagesQuickActionsTitle => 'Tezkor amallar';

  @override
  String get messagesSystemEmptyTitle => 'Yangi tizim xabarlari yo\'q';

  @override
  String get messagesSystemEmptySubtitle =>
      'Yangi bildirishnomalar paydo bo\'lganda, ular shu yerda ko\'rinadi.';

  @override
  String messagesSystemUnreadCount(int count) {
    return 'Yangi tizim xabarlari: $count';
  }

  @override
  String get messagesTipAssigned =>
      'Omad! Eng yaxshi bilimingizni ko\'rsating va zo\'r natija oling.';

  @override
  String get messagesToday => 'Bugun';

  @override
  String get messagesYesterday => 'Kecha';

  @override
  String get messagesMarkReadError => 'O\'qilgan deb belgilab bo\'lmadi';

  @override
  String homeHeroWelcome(String name) {
    return 'Xush kelibsiz, $name!';
  }

  @override
  String get homeHeroSubtitle =>
      'Har kungi kichik ilg\'or qadam katta natijalarga olib keladi.';

  @override
  String get homeUrgentTestsTitle => 'Shoshilinch va yaqinlashayotgan testlar';

  @override
  String get homeViewAllTests => 'Barchasini ko\'rish';

  @override
  String homeDeadlineHours(int hours) {
    return '$hours soatdan keyin';
  }

  @override
  String get homeDeadlineTomorrow => 'Ertagacha';

  @override
  String homeDeadlineDaysLeft(int days) {
    return '$days kun qoldi';
  }

  @override
  String get homeAnnouncementsTitle => 'E\'lonlar va yangiliklar';

  @override
  String get homeAnnouncementsEmpty => 'Hozircha e\'lonlar yo\'q';

  @override
  String get homeActivityStreakTitle => 'Faollik va seriya';

  @override
  String get homeAttendanceLabel => 'Davomat';

  @override
  String homeWeekProgressTitle(int completed, int assigned, int pct) {
    return 'Haftalik progress: $assigned tadan $completed tasi ($pct%)';
  }

  @override
  String get homeWeekProgressCompleted => 'Bajarildi';

  @override
  String get homeWeekProgressInProgress => 'Jarayonda';

  @override
  String get homeWeekProgressRemaining => 'Qoldi';

  @override
  String get homeNextLessonTitle => 'Yaqin dars';

  @override
  String get homeLastResultTitle => 'Oxirgi natija';

  @override
  String get homeQuickActionTestsDesc => 'Testni tanlang va hoziroq boshlang';

  @override
  String get homeQuickActionResultsDesc => 'O\'z natijalaringizni ko\'ring';

  @override
  String get homeQuickActionContactTeacher => 'O\'qituvchi bilan bog\'lanish';

  @override
  String get homeQuickActionContactTeacherDesc =>
      'Savol bering yoki xabar yuboring';

  @override
  String get homeToResultsLink => 'Natijalarga';

  @override
  String get weekdayMonShort => 'Du';

  @override
  String get weekdayTueShort => 'Se';

  @override
  String get weekdayWedShort => 'Ch';

  @override
  String get weekdayThuShort => 'Pa';

  @override
  String get weekdayFriShort => 'Ju';

  @override
  String get weekdaySatShort => 'Sh';

  @override
  String get weekdaySunShort => 'Ya';
}
