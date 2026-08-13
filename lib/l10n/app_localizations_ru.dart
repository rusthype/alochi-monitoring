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
  String get studentLoginButton => 'Войти как ученик';

  @override
  String get myTestsTitle => 'Мои тесты';

  @override
  String get myTestsEmpty => 'Для вас пока нет доступных тестов';

  @override
  String get retryCheck => 'Проверить снова';

  @override
  String get sidebarHome => 'Главная';

  @override
  String get sidebarResults => 'Результаты';

  @override
  String get sidebarMessages => 'Сообщения';

  @override
  String get sidebarCertificates => 'Сертификаты';

  @override
  String get sidebarSettings => 'Настройки';

  @override
  String get sidebarHelp => 'Помощь';

  @override
  String get kpiTestsCompleted => 'Пройдено тестов';

  @override
  String get kpiAverageScore => 'Средний балл';

  @override
  String get kpiStreakDays => 'Дней подряд';

  @override
  String get searchTestsHint => 'Поиск тестов...';

  @override
  String get filterAll => 'Все';

  @override
  String get filterInProgress => 'В процессе';

  @override
  String get filterCompleted => 'Завершено';

  @override
  String get filterLocked => 'Заблокировано';

  @override
  String get allSubjects => 'Все предметы';

  @override
  String get otherSubject => 'Другое';

  @override
  String get continueTest => 'Продолжить';

  @override
  String get viewResult => 'Посмотреть результат';

  @override
  String get viewAllResults => 'Посмотреть все результаты';

  @override
  String questionCountLabel(int count) {
    return '$count вопросов';
  }

  @override
  String durationMinutesLabel(int minutes) {
    return '$minutes минут';
  }

  @override
  String get recentResultsTitle => 'Последние результаты';

  @override
  String get noResultsYet => 'Пока нет результатов';

  @override
  String get noFilterMatches => 'Тесты по фильтру не найдены';

  @override
  String get resultsScreenTitle => 'Мои результаты';

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
  String get clearHistoryTitle => 'Очистить';

  @override
  String get clearHistoryConfirm => 'Удалить всю историю результатов?';

  @override
  String get noWord => 'Нет';

  @override
  String get yesDelete => 'Да, удалить';

  @override
  String get offlineHistoryTitle => 'История офлайн результатов';

  @override
  String get noHistoryYet => 'Истории пока нет';

  @override
  String get schoolLabel => 'Школа';

  @override
  String get dateLabel => 'Дата';

  @override
  String get mathShort => 'Мат';

  @override
  String get engShort => 'Англ';

  @override
  String syncCompleteMsg(String done) {
    return 'Синхронизация завершена! Сохранено офлайн $done изображений.';
  }

  @override
  String get errorOccurred => 'Произошла ошибка: ';

  @override
  String get offlineImagesLoading => 'Загрузка офлайн изображений...';

  @override
  String savedOutOfTotal(String done, String total) {
    return 'Сохранено $done / $total';
  }

  @override
  String get syncImagesOfflineButton => 'Подготовить офлайн изображения (Sync)';

  @override
  String get localResSending => '📤 Отправка...';

  @override
  String get localResSavedSending => '✅ Сохранено, отправка...';

  @override
  String get localResSaveError => '❌ Ошибка при сохранении. Повторите попытку.';

  @override
  String get localResBarakalla => 'Молодец!';

  @override
  String get localResYaxshi => 'Хорошо!';

  @override
  String get nextStudentButton => 'Следующий ученик';

  @override
  String get questionsUnansweredPrompt =>
      'вопрос(ов) без ответа. Всё равно завершить?';

  @override
  String get finishButtonText => 'Завершить';

  @override
  String get gradeWord => '-класс';

  @override
  String get mathSectionTimeUp => 'Время раздела «Математика» истекло!';

  @override
  String get engSectionTimeUp => 'Время раздела «Английский язык» истекло!';

  @override
  String get finishTest => 'Завершить';

  @override
  String get uploadTest => 'Отправка';

  @override
  String get resultNotSavedError =>
      'Результат не сохранён — проблема с интернетом или памятью. Повторите попытку.';

  @override
  String get testLoadFailed => 'Не удалось загрузить тест';

  @override
  String get testTitle => 'Тест';

  @override
  String get gradeExcellent => 'Отлично';

  @override
  String get gradeGood => 'Хорошо';

  @override
  String get gradeSatisfactory => 'Удовлетворительно';

  @override
  String get gradeNeedsPractice => 'Нужна дополнительная практика';

  @override
  String get pdfGenerationError => 'Ошибка при создании PDF';

  @override
  String get resultTitle => 'Результат';

  @override
  String correctAnswersWithCount(String count) {
    return 'Правильно $count';
  }

  @override
  String wrongAnswersWithCount(String count) {
    return 'Неправильно $count';
  }

  @override
  String shieldsCount(String count) {
    return '$count щит';
  }

  @override
  String get sectionsByTitle => 'ПО РАЗДЕЛАМ';

  @override
  String get noDataAvailable => 'Нет данных';

  @override
  String get reopenPdf => 'Открыть PDF заново';

  @override
  String get pdfReportButton => 'PDF-отчёт';

  @override
  String get aiAnalysisTitle => 'ИИ анализ';

  @override
  String get analysisPreparing => 'Анализ готовится…';

  @override
  String get strongSidesTitle => 'Сильные стороны';

  @override
  String get weakSidesTitle => 'Слабые стороны';

  @override
  String get recommendationsTitle => 'Рекомендации';

  @override
  String get focus14DaysTitle => 'Фокус на 14 дней';

  @override
  String get subjectAnalysisByTopic => 'Анализ по темам';

  @override
  String get subjectAnalysisByUnit => 'Анализ по юнитам';

  @override
  String get subjectAnalysisByParagraph => 'Разбивка по параграфам';

  @override
  String get strongAndWeakSides => 'Сильные и слабые стороны';

  @override
  String get strongLabel => 'Сильные';

  @override
  String get needsReinforcement => 'Нужно закрепить';

  @override
  String get weakTopicFallback => 'слабая тема';

  @override
  String get days1to3 => '1–3 день';

  @override
  String weakestTopicPlan(String topic) {
    return 'Самая слабая тема: $topic (15 минут/день)';
  }

  @override
  String get days4to7 => '4–7 день';

  @override
  String secondTopicPlan(String topic) {
    return 'Вторая тема: $topic (5 примеров/день)';
  }

  @override
  String get days8to11 => '8–11 день';

  @override
  String get mixedExercisesPlan => 'Смешанные упражнения — повторение всех тем';

  @override
  String get days12to14 => '12–14 день';

  @override
  String get controlTestPlan => 'Контрольный тест — сравнение результата';

  @override
  String get plan14DaysTitle => 'План на 14 дней';

  @override
  String get sending => 'Отправка...';

  @override
  String get savedSuccess => 'Сохранено!';

  @override
  String get savedOfflineLater => 'Сохранено (офлайн — будет отправлено позже)';

  @override
  String get savedSending => 'Сохранено, отправка...';

  @override
  String get interhouseGrade2 => 'Interhouse Grade 2';

  @override
  String get sectionsBreakdown => 'По разделам';

  @override
  String get nextStudentBtn => 'Следующий ученик';

  @override
  String get finishBtn => 'Завершить';

  @override
  String get mathQuestionsNotFound => 'Вопросы по математике не найдены.';

  @override
  String get generalTests => 'Общие тесты';

  @override
  String get loadingGroups => 'Загрузка групп...';

  @override
  String get selectGroup => 'Выберите группу';

  @override
  String get selectStudent => 'Выберите ученика';

  @override
  String get selectGrade => 'Выберите класс';

  @override
  String get selectSchool => 'Выберите школу';

  @override
  String get incorrectPin => 'Неверный PIN';

  @override
  String get enterFourDigitPin => 'Введите четырёхзначный PIN-код';

  @override
  String get showPassword => 'Показать';

  @override
  String get hidePassword => 'Скрыть';

  @override
  String get confirmBtn => 'Подтвердить';

  @override
  String get nextStepStudentName => 'Следующий шаг: ввод имени ученика';

  @override
  String get testSession => 'Сессия тестирования';

  @override
  String get testSessionInstruction =>
      'Чтобы начать сессию тестирования, выберите школу и введите PIN-код.';

  @override
  String get sessionSettings => 'Настройки сессии';

  @override
  String get studentNameStep => 'Имя ученика';

  @override
  String get testLocked => 'Этот тест пока заблокирован.';

  @override
  String get testNotInCache => 'Тест не найден в кэше. Загрузите заново.';

  @override
  String get sessionConflictOtherDevice =>
      'Этот ученик уже начал тест на другом устройстве.';

  @override
  String get schools => 'Школы';

  @override
  String get otherSchools => 'Другие школы';

  @override
  String get schoolCodeOrName => 'Код / название школы';

  @override
  String get downloaded => 'Скачано';

  @override
  String get downloading => 'Скачивается';

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
  String get newBadge => 'Новое';

  @override
  String newBadgeAddedOn(String date) {
    return 'Добавлено: $date';
  }

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

  @override
  String get back => 'Назад';

  @override
  String get finish => 'Завершить';

  @override
  String get errorTitle => 'Ошибка';

  @override
  String get returnToHome => 'Вернуться на главную';

  @override
  String get routeNotFound => 'Маршрут не найден';

  @override
  String get reportGenerationError => 'Ошибка при создании отчета';

  @override
  String get printBtn => 'Печать';

  @override
  String get downloadBtn => 'Скачать';

  @override
  String get exitBtn => 'Выход';

  @override
  String get yesBtn => 'Да';

  @override
  String get updateBtn => 'Обновление';

  @override
  String get updateDownloadFailedMsg =>
      'Не удалось загрузить обновление. Проверьте интернет-соединение и попробуйте снова.';

  @override
  String get okBtn => 'Хорошо';

  @override
  String get yesOption => 'ДА';

  @override
  String get noOption => 'НЕТ';

  @override
  String get alisherHint => 'Алишер';

  @override
  String get vocabularyTopic => 'Словарный запас';

  @override
  String get grammarTopic => 'Грамматика';

  @override
  String get spellingTopic => 'Орфография';

  @override
  String get sentencesTopic => 'Предложения';

  @override
  String get readingTopic => 'Чтение';

  @override
  String get checkForUpdates => 'Проверить обновления...';

  @override
  String get appNameTitle => 'Мониторинг Alochi';

  @override
  String get bobEmptySectionMsg => 'Этот раздел пуст.';

  @override
  String get returnBtn => 'Вернуться';

  @override
  String get sectionsResultTitle => 'Результаты по разделам';

  @override
  String get vocabularyQuestionsNotFoundMsg => 'Вопросы Vocabulary не найдены.';

  @override
  String get grammarQuestionsNotFoundMsg => 'Вопросы Grammar не найдены.';

  @override
  String get spellingQuestionsNotFoundMsg => 'Вопросы Spelling не найдены.';

  @override
  String get sentencesQuestionsNotFoundMsg => 'Вопросы Sentences не найдены.';

  @override
  String get readingQuestionsNotFoundMsg => 'Вопросы Reading не найдены.';

  @override
  String get variantsNotFoundMsg => 'Варианты не найдены.';

  @override
  String get arrangeLettersPrompt => 'Расположите буквы в правильном порядке';

  @override
  String get arrangeSentencePrompt =>
      'Расставьте предложение в правильном порядке';

  @override
  String get arrangeEventsPrompt => 'Отметьте события в правильном порядке';

  @override
  String get selectVariantsInOrderPrompt =>
      'Выберите варианты ниже в правильном порядке';

  @override
  String get clearSelectionBtn => 'Очистить';

  @override
  String get variantsSectionHeader => 'ВАРИАНТЫ';

  @override
  String get answerHintText => 'Ответ...';

  @override
  String get fullSentenceHintText => 'Напишите полное предложение...';

  @override
  String sessionGradeVariantLabel(String grade, String variant) {
    return '$grade класс · Вариант $variant';
  }

  @override
  String get reportSavedButOpenFailedMsg =>
      'Отчёт сохранён, но не удалось открыть';

  @override
  String get bob14ScreenTitle => '2 класс — Мониторинг Bob 1-4';

  @override
  String get bob14TestInfo => '30 вопросов · 45 минут · Оффлайн режим';

  @override
  String get unit1ScreenTitle => '1 класс Английский язык — Unit 1';

  @override
  String get unit1TestInfo => '49 вопросов · 49 минут · Оффлайн режим';

  @override
  String get unit1RunnerHeaderTitle => '1 класс Unit 1 — Английский язык';

  @override
  String correctFractionLabel(int correct, int total) {
    return '$correct / $total правильно';
  }

  @override
  String get hujjatlarLabel => 'Документы';

  @override
  String get noDocumentsMsg => 'Нет документов';

  @override
  String savedFileMsg(String path) {
    return 'Сохранено: $path';
  }

  @override
  String get exitConfirmationMessage =>
      'Вы действительно хотите выйти? Введённые данные не сохранятся.';

  @override
  String get pageNotFoundTitle => 'Страница не найдена';

  @override
  String get pageNotFoundMessage =>
      'Извините, страница, которую вы ищете, не существует или была перемещена.';

  @override
  String get monitoringTestHeader => 'МОНИТОРИНГ ТЕСТ';

  @override
  String get testDataNotFoundMsg => 'Данные теста не найдены';

  @override
  String get updateUpToDateMessage =>
      'У вас установлена последняя версия программы.';

  @override
  String shieldsProgressLabel(int count) {
    return '$count/25 щитов';
  }

  @override
  String get diagnosticPassportHeader => 'A\'LOCHI — ДИАГНОСТИЧЕСКИЙ ПАСПОРТ';

  @override
  String get totalQuestionsCountLabel => 'Всего вопросов';

  @override
  String get correctAnswerLabelPdf => 'Правильный ответ';

  @override
  String get wrongAnswerLabelPdf => 'Неправильный ответ';

  @override
  String get topicAnalysisHeader => 'АНАЛИЗ ПО ТЕМАМ';

  @override
  String get unitAnalysisHeader => 'АНАЛИЗ ПО UNIT';

  @override
  String get fourteenDayPlanHeader => 'ПЛАН НА 14 ДНЕЙ';

  @override
  String get aiSummaryHeader => 'AI ЗАКЛЮЧЕНИЕ';

  @override
  String get alochiAiLabel => 'A\'LOCHI AI';

  @override
  String get forParentsLabel => 'Родителям';

  @override
  String get parentTipsText =>
      '• Ежедневно уделяйте 20–30 минут чтению\n• Повторяйте слабые темы вместе\n• Поощряйте и обучайте с терпением';

  @override
  String get footerBrandTagline => 'Образование A\'lochi · alochi.uz';

  @override
  String get dayRange1_3 => '1–3 ДЕНЬ';

  @override
  String get dayRange4_7 => '4–7 ДЕНЬ';

  @override
  String get dayRange8_11 => '8–11 ДЕНЬ';

  @override
  String get dayRange12_14 => '12–14 ДЕНЬ';

  @override
  String get dailyPractice15MinMsg => 'Каждый день 15 минут практики';

  @override
  String get dailyExamples5Msg => 'Каждый день решать 5 примеров';

  @override
  String get mixedExercisesTopic => 'Смешанные упражнения';

  @override
  String get reviewAllTopicsMsg => 'Повторить все темы';

  @override
  String get controlTestTopic => 'Контрольный тест';

  @override
  String get compareResultsMsg => 'Сравнить результаты';

  @override
  String get wellMasteredBadge => 'Хорошо усвоено';

  @override
  String get needsReviewBadge => 'Нужно повторить';

  @override
  String aiSummaryFallbackMsg(String firstName, int pct) {
    return '$firstName показал(а) результат $pct%. Рекомендуется работать по 14-дневному плану в зависимости от уровня усвоения.';
  }

  @override
  String get goodResultLabel => 'Хороший результат';

  @override
  String get searchOrCommandHint => 'Введите поиск или команду...';

  @override
  String get commandHistoryTitle => 'Оффлайн история';

  @override
  String get commandLocalGradeTitle => 'Локальная оценка';

  @override
  String get commandCombinedTitle => 'Комбинированный';

  @override
  String get bob14FallbackLabel => 'Bob 1-4';

  @override
  String get unit1FallbackLabel => 'Unit 1';

  @override
  String get saveErrorRetryMsg => 'Ошибка сохранения. Попробуйте ещё раз.';

  @override
  String get unit1PillLabel => 'Unit 1 G1';

  @override
  String get interhousePillLabel => 'Interhouse G2';

  @override
  String get combinedPillLabel => 'Monitoring Unit 1';

  @override
  String mathEngCountSummary(int math, int eng) {
    return 'Математика: $math  Английский язык: $eng';
  }

  @override
  String get testDataEmptyMsg => 'Данные теста пусты (варианты не найдены)';

  @override
  String testLoadErrorMsg(String error) {
    return 'Тест не загружен: $error';
  }

  @override
  String get reportQuestionSheetTitle => 'Сообщить о проблеме с вопросом';

  @override
  String get reportReasonQuestionError => 'В вопросе есть ошибка';

  @override
  String get reportReasonWrongOptions => 'Варианты ответов неверны';

  @override
  String get reportReasonImageTextMissing =>
      'Изображение/текст не отображается';

  @override
  String get reportReasonOther => 'Другое';

  @override
  String get reportCommentHint => 'Опишите проблему...';

  @override
  String get reportSubmitBtn => 'Отправить';

  @override
  String get questionReportSentMsg => 'Ваше сообщение отправлено';

  @override
  String get questionReportFailedMsg => 'Ошибка отправки. Попробуйте ещё раз.';

  @override
  String get loadStudentsError =>
      'Не удалось загрузить список учеников. Проверьте интернет и попробуйте снова.';

  @override
  String get noStudentsInGroup => 'В этой группе нет активных учеников.';
}
