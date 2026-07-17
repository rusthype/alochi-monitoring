// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Мониторинг Alochi';

  @override
  String get loginTitle => 'Вход';

  @override
  String get languageUzbek => 'O\'zbek';

  @override
  String get languageRussian => 'Русский';

  @override
  String get bossCreateTitle => 'Создание теста из книги';

  @override
  String get logout => 'Выйти';

  @override
  String get serverChecking => 'Проверка сервера...';

  @override
  String get serverConnected => 'Подключено к серверу';

  @override
  String get offlineMode => 'Оффлайн режим';

  @override
  String get invalidCredentials => 'Логин или пароль неверный';

  @override
  String get tooManyAttempts => 'Слишком много попыток. Подождите немного.';

  @override
  String get serverErrorRetry => 'Ошибка сервера. Попробуйте еще раз.';

  @override
  String get offlineNoSavedLogin => 'Нет интернета и логин не сохранен.';

  @override
  String get connectionError => 'Ошибка подключения';

  @override
  String get loggingIn => 'Вход...';

  @override
  String get appSubtitle => 'Платформа образовательного мониторинга';

  @override
  String get testsRoute => 'Тесты';

  @override
  String get comingSoon => 'Скоро';

  @override
  String get retryCheck => 'Проверить снова';

  @override
  String get loginInstruction => 'Получите логин и пароль у вашего учителя';

  @override
  String get usernameLabel => 'Логин';

  @override
  String get passwordLabel => 'Пароль';

  @override
  String get usernameRequired => 'Введите логин';

  @override
  String get passwordRequired => 'Введите пароль';

  @override
  String get offlineLogin => 'Оффлайн вход';

  @override
  String get localGradeEntry => 'Обычный вход (Без интернета)';

  @override
  String get monitoringTestUnit1 => 'Мониторинг тест Unit 1';

  @override
  String get offlineHistory => 'Оффлайн история';

  @override
  String get selectPdfFirst => 'Сначала выберите PDF файл';

  @override
  String get aiGeneratingMessage =>
      'ИИ генерирует вопросы...\nЭто может занять 1-2 минуты';

  @override
  String get enterPackageTitle => 'Введите название пакета';

  @override
  String get savingMessage => 'Сохранение...';

  @override
  String get backButton => 'Назад';

  @override
  String get packageTitleLabel => 'Заголовок пакета';

  @override
  String saveAndPublish(int grade, int variantCount) {
    return 'Сохранить и опубликовать ($grade-класс, $variantCount вариантов)';
  }

  @override
  String get questionTextLabel => 'Текст вопроса';

  @override
  String variantLetterLabel(String letter) {
    return 'Вариант $letter';
  }

  @override
  String get aiImagePromptHint => 'Подсказка ИИ (не сохраняется):';

  @override
  String get mathSubject => 'Мат.';

  @override
  String get englishSubject => 'Англ.';

  @override
  String get selectPdfBook => 'Выберите PDF книгу';

  @override
  String get pdfFileHint => '.pdf файл, макс 10МБ, 50 страниц';

  @override
  String get subjectLabel => 'Предмет';

  @override
  String get gradeLabel => 'Класс';

  @override
  String get questionCountLabel => 'Количество вопросов';

  @override
  String get variantCountLabel => 'Количество вариантов';

  @override
  String get generateWithAi => 'Создать вопросы с помощью ИИ';

  @override
  String gradeN(int n) {
    return '$n-класс';
  }

  @override
  String nQuestions(int n) {
    return '$n вопросов';
  }

  @override
  String nVariants(int n) {
    return '$n вариантов';
  }

  @override
  String questionIndex(int index) {
    return 'Вопрос $index';
  }

  @override
  String get enterFirstAndLastName => 'Введите имя и фамилию';

  @override
  String get incorrectSecretPassword =>
      'Неверный секретный пароль (Подсказка: 1234)';

  @override
  String errorPrefix(String error) {
    return 'Ошибка: $error';
  }

  @override
  String get selectVariant => 'Выберите вариант';

  @override
  String get studentInfoTitle => 'Данные ученика';

  @override
  String get localTestInfo =>
      '2-й класс Английский язык — Тест Interhouse\n10 вариантов · 30 вопросов · Оффлайн режим';

  @override
  String get continueButton => 'Продолжить';

  @override
  String get firstNameLabel => 'Имя';

  @override
  String get firstNameHint => 'Алишер';

  @override
  String get lastNameLabel => 'Фамилия';

  @override
  String get lastNameHint => 'Каримов';

  @override
  String get groupGradeLabel => 'Группа / Класс';

  @override
  String get groupGradeHint => '3-А';

  @override
  String get schoolNameLabel => 'Название школы';

  @override
  String get schoolNameHint => '12-школа';

  @override
  String get pinCodeLabel => 'Пароль (PIN-код)';

  @override
  String get startTest => 'Начать тест';

  @override
  String get combinedTestInfo => '79 вопросов · 75 минут · Оффлайн режим';

  @override
  String get combinedTestSubjects => '30 математика + 49 английский язык';

  @override
  String get incorrectPassword => 'Неверный секретный пароль';

  @override
  String get confirmLogout => 'Вы хотите выйти из аккаунта?';

  @override
  String get cancel => 'Отмена';

  @override
  String get noActiveExamOrExpired =>
      'Активный экзамен не найден или срок его действия истек';

  @override
  String get loadFailed => 'Не удалось загрузить. Повторите попытку.';

  @override
  String gradeClass(int grade) {
    return '$grade-класс';
  }

  @override
  String variantBadge(int variant) {
    return 'Вариант $variant';
  }

  @override
  String get selectTest => 'Выберите тест';

  @override
  String get selectMonitoringTest =>
      'Выберите один из доступных тестов мониторинга';

  @override
  String get retry => 'Повторить';

  @override
  String get noActiveExam => 'Нет активного экзамена';

  @override
  String get noExamAssignedOrExpired =>
      'Экзамен еще не назначен\nили срок его действия истек';

  @override
  String get testsNotLoadedYet => 'Тесты еще не загружены';

  @override
  String get tryAgainAfterTeacherUploads =>
      'Пожалуйста, повторите попытку после того,\nкак ваш учитель загрузит тесты';

  @override
  String get refresh => 'Обновить';

  @override
  String get totalLabel => 'Всего';

  @override
  String get helloGreeting => 'Привет!';

  @override
  String get mathSubjectFull => 'Математика';

  @override
  String get englishSubjectFull => 'Английский язык';

  @override
  String get finishConfirmTitle => 'Завершить?';

  @override
  String unansweredWarning(int unanswered) {
    return 'Без ответа: $unanswered. Все равно завершить?';
  }

  @override
  String get mathSectionLabel => 'Раздел: Математика';

  @override
  String get engSectionLabel => 'Раздел: Английский';

  @override
  String get keyboardButtons => 'клавиши';

  @override
  String get previousButton => 'Назад';

  @override
  String get nextButton => 'Вперёд';

  @override
  String get answeredLabel => 'отвечено';

  @override
  String get uploadingLabel => 'Загрузка';

  @override
  String get timeLeftLabel => 'осталось';

  @override
  String get engSectionTransitionTitle => 'Переход к английскому языку';

  @override
  String get engSectionTransitionDesc =>
      '40 минут · Следующие вопросы на английском';

  @override
  String get imageLoadFailed => 'Ошибка загрузки';

  @override
  String pdfError(String error) {
    return 'Ошибка PDF: $error';
  }

  @override
  String get congratsTitle => 'Поздравляем!';

  @override
  String get goodEffortTitle => 'Хорошая попытка!';

  @override
  String get testFinishedSuccess => 'Тест успешно завершен';

  @override
  String get betterNextTime => 'В следующий раз получится лучше!';

  @override
  String get scorePoint => 'балл';

  @override
  String get passedMessage => 'Поздравляем! Вы сдали!';

  @override
  String get failedMessage => 'Не сдал. Попробуйте еще!';

  @override
  String get totalScoreLabel => 'Общий балл';

  @override
  String get syncedSuccess => 'Результат успешно отправлен на сервер';

  @override
  String get savedOffline =>
      'Сохранено офлайн. Будет отправлено при наличии интернета';

  @override
  String get pdfReady => 'PDF готов';

  @override
  String get downloadPdf => 'Скачать PDF';

  @override
  String get nextStudent => 'Следующий ученик';

  @override
  String wrongAnswersCount(int count) {
    return 'Неправильные ответы — $count';
  }

  @override
  String wrongAnswersBreakdown(int math, int eng) {
    return 'Мат: $math  ·  Англ: $eng';
  }

  @override
  String get statusGood => 'Хорошо ✓';

  @override
  String get statusAverage => 'Средне';

  @override
  String get statusWeak => 'Слабо — нужна практика';

  @override
  String get subjectAnalysisTitle => 'Анализ предметов';

  @override
  String get mathTipLow1 =>
      'Повторите базовые операции (сложение, вычитание, умножение, деление).';

  @override
  String get mathTipLow2 => 'Решайте примеры по 20 минут каждый день.';

  @override
  String get mathTipLow3 => 'Начните с программы 2-го класса.';

  @override
  String get mathTipMed1 => 'Закрепите таблицу умножения и дроби.';

  @override
  String get mathTipMed2 =>
      'Определите типы вопросов, в которых вы ошиблись, и обратите на них внимание.';

  @override
  String get mathTipMed3 => 'Решайте по 2-3 тестовые задачи каждый день.';

  @override
  String get mathTipHigh1 => 'Работайте над сложными (проблемными) задачами.';

  @override
  String get mathTipHigh2 => 'Практикуйте управление временем.';

  @override
  String get mathTipHigh3 => 'Уделяйте по 1-2 минуты на каждый вопрос.';

  @override
  String get mathTipExc1 => 'Отлично!';

  @override
  String get mathTipExc2 => 'Переходите к решению сложных олимпиадных задач.';

  @override
  String get mathTipExc3 =>
      'Регулярно тренируйтесь, чтобы поддерживать результат.';

  @override
  String get engTipLow1 =>
      'Учите по 10 новых слов каждый день (метод карточек).';

  @override
  String get engTipLow2 =>
      'Базовая грамматика: to be, present simple, множественное число.';

  @override
  String get engTipLow3 => 'Используйте BBC Learning English, Duolingo.';

  @override
  String get engTipMed1 =>
      'Изучите грамматику past simple и present continuous.';

  @override
  String get engTipMed2 =>
      'Каждый день читайте 1 короткий текст на английском.';

  @override
  String get engTipMed3 => 'Учите словарный запас, группируя его по темам.';

  @override
  String get engTipHigh1 => 'Развивайте навыки аудирования.';

  @override
  String get engTipHigh2 => 'Используйте англоязычный контент на YouTube.';

  @override
  String get engTipHigh3 => 'Пишите эссе и короткие рассказы.';

  @override
  String get engTipExc1 => 'Отлично!';

  @override
  String get engTipExc2 => 'Готовьтесь к сертификату IELTS/Cambridge.';

  @override
  String get engTipExc3 => 'Продолжайте читать и слушать сложные тексты.';

  @override
  String get statusGold => 'Уровень золотой медали! Так держать!';

  @override
  String get statusGoodMsg => 'Хороший результат! Нужно еще немного усилий.';

  @override
  String get statusSatisfactory =>
      'Удовлетворительно. Следуйте рекомендациям и попробуйте снова.';

  @override
  String get statusKeepTrying =>
      'Не расстраивайтесь! Каждая неудача — это новое начало.';

  @override
  String pdfTitle(String name) {
    return 'Результат - $name';
  }

  @override
  String get subjectsResultTitle => 'Результаты по предметам';

  @override
  String get totalCorrectAnswers => 'Всего правильных ответов:';

  @override
  String get howToImprove => 'Как улучшить результат?';

  @override
  String get mathRecommendations => 'Рекомендации по математике';

  @override
  String get englishRecommendations => 'Рекомендации по английскому языку';

  @override
  String get wrongAnswersTitle => 'Неправильные ответы';

  @override
  String get wrongAnswersAnalysis => 'Анализ неправильных ответов';

  @override
  String get studentLabel => 'Ученик';

  @override
  String get passed => 'Сдал';

  @override
  String get failed => 'Не сдал';

  @override
  String get keepTrying => 'Продолжайте стараться!';

  @override
  String get monitoringTestResult => 'Результат мониторингового теста';

  @override
  String get alochiMonitoringSystem => 'Система Alochi Monitoring';

  @override
  String get homePage => 'Главная';

  @override
  String get savePdf => 'Сохранить PDF';

  @override
  String get printPdf => 'Распечатать';

  @override
  String get sharePdf => 'Поделиться';

  @override
  String get loadingLabelDots => 'Загрузка...';

  @override
  String get errorLater => 'Ошибка. Будет отправлено позже.';

  @override
  String get gradeAndVariant => 'Класс и Вариант';

  @override
  String get overallResult => 'Общий результат';

  @override
  String get topicAnalysisTitle => 'Анализ по темам';

  @override
  String get topicName => 'Название темы';

  @override
  String get correctAnswersCount => 'Правильные ответы';

  @override
  String get percentage => 'Процент';

  @override
  String get offlineTestResult => 'Офлайн тест';

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
  String get schools => 'Школы';

  @override
  String get otherSchools => 'Другие школы';

  @override
  String get schoolCodeOrName => 'Код / название школы';

  @override
  String get downloaded => 'Скачано';

  @override
  String get enterSchoolError => 'Введите школу';

  @override
  String schoolPrefix(String code) {
    return 'Школа №$code';
  }

  @override
  String get enterNameError => 'Введите имя и фамилию';

  @override
  String get lastName => 'Фамилия';

  @override
  String get firstName => 'Имя';

  @override
  String get groupOptional => 'Группа (необязательно)';

  @override
  String get variant => 'Вариант';

  @override
  String get start => 'Начать';

  @override
  String get downloadError => 'Ошибка загрузки. Попробуйте снова.';

  @override
  String get testsNotFound => 'Тесты не найдены';

  @override
  String get opensAt => 'откроется в';

  @override
  String get newVersionAvailable => 'Доступна новая версия';

  @override
  String get update => 'Обновить';

  @override
  String get download => 'Скачать';

  @override
  String get confirmSessionTitle => 'Подтвердите\nсессию';

  @override
  String get pinCodeRequired => 'PIN-КОД (ОБЯЗАТЕЛЬНО)';

  @override
  String get enterPinCode => 'Введите PIN-код';

  @override
  String get enterTeacherCode => 'Введите код, выданный учителем';

  @override
  String get otherSchoolBtn => 'Другая школа';

  @override
  String get groupsNotFound => 'Группы не найдены';

  @override
  String get testsNotFoundForGroup => 'Для этой группы тесты не найдены';

  @override
  String get notDownloaded => 'Не скачано';

  @override
  String get stillLocked => 'Всё ещё закрыто';

  @override
  String get ready => 'Готово';

  @override
  String get whoTakesTest => 'Кто сдает\nтест?';

  @override
  String get studentsInList => 'учеников в списке';

  @override
  String get gradeShort => 'класс';

  @override
  String get backBtn => 'Назад';

  @override
  String get copyName => 'Скопировать';

  @override
  String nameCopied(String name) {
    return 'Имя $name скопировано!';
  }

  @override
  String get searchStudents => 'Поиск ученика (Ctrl+K)...';
}
