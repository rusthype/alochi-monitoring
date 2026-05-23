// lib/core/services/pdf_tips.dart
// Online va offline PDF lar uchun umumiy tavsiya matnlari.

class PdfTips {
  static List<String> mathTips(double pct) {
    if (pct < 0.5) {
      return [
        "Asosiy amallar (qo'shish, ayirish, ko'paytirish, bo'lish)ni qayta o'rganing.",
        'Har kuni 20 daqiqa misollar yeching.',
        '2-sinf dasturidan boshlang.',
      ];
    }
    if (pct < 0.75) {
      return [
        'Jadval va kasr sonlarni mustahkamlang.',
        "Xato qilgan savollar turini aniqlang va shu mavzuga e'tibor bering.",
        'Har kuni 2-3 ta test masala yeching.',
      ];
    }
    if (pct < 0.9) {
      return [
        'Qiyin masalalar (muammo masalalar) ustida ishlang.',
        'Vaqtni boshqarishni mashq qiling.',
        'Har savolga 1-2 daqiqa ajrating.',
      ];
    }
    return [
      'Ajoyib!',
      "Murakkab olimpiada masalalarini hal qilishga o'ting.",
      'Natijani barqaror saqlash uchun muntazam mashq qiling.',
    ];
  }

  static List<String> englishTips(double pct) {
    if (pct < 0.5) {
      return [
        "Kunlik 10 ta yangi so'z yodlang (flashcard usuli).",
        'Asosiy grammatika: to be, present simple, plural nouns.',
        'BBC Learning English, Duolingo ilovalaridan foydalaning.',
      ];
    }
    if (pct < 0.75) {
      return [
        "Past simple va present continuous grammatikasini o'rganing.",
        "Har kuni inglizcha 1 ta qisqa matn o'qing.",
        "So'z boyligini mavzu bo'yicha guruhlab yodlang.",
      ];
    }
    if (pct < 0.9) {
      return [
        "Tinglash ko'nikmalarini rivojlantiring.",
        'YouTube ingliz kontentidan foydalaning.',
        'Esselar va qisqa hikoyalar yozing.',
      ];
    }
    return [
      'Ajoyib!',
      'IELTS/Cambridge sertifikati uchun tayyorlaning.',
      "Murakkab matnlarni o'qish va tinglashni davom ettiring.",
    ];
  }

  static String overallStatus(int totalPct) {
    if (totalPct >= 90) return 'Oltin medal darajasi! Davom eting!';
    if (totalPct >= 75) return 'Yaxshi natija! Yana bir oz harakat kerak.';
    if (totalPct >= 60) {
      return "Qoniqarli. Tavsiyalarga amal qiling va qayta sinab ko'ring.";
    }
    return "Xafa bo'lmang! Har bir muvaffaqiyatsizlik yangi boshlang'ich.";
  }
}
