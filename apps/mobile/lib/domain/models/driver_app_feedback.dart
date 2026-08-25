class DriverFeedbackQuestion {
  const DriverFeedbackQuestion({
    required this.key,
    required this.english,
    required this.filipino,
  });

  final String key;
  final String english;
  final String filipino;
}

abstract final class DriverAppFeedback {
  static const questions = <DriverFeedbackQuestion>[
    DriverFeedbackQuestion(
      key: 'ease_of_use',
      english: 'ArangCada was easy to use.',
      filipino: 'Madaling gamitin ang ArangCada.',
    ),
    DriverFeedbackQuestion(
      key: 'booking_clarity',
      english: 'The ride request and passenger details were clear.',
      filipino: 'Malinaw ang kahilingan sa biyahe at detalye ng pasahero.',
    ),
    DriverFeedbackQuestion(
      key: 'navigation_clarity',
      english: 'The map, pickup, and destination were easy to understand.',
      filipino: 'Madaling unawain ang mapa, sakayan, at babaan.',
    ),
    DriverFeedbackQuestion(
      key: 'fare_fairness',
      english: 'The fare shown was clear and trustworthy.',
      filipino: 'Malinaw at mapagkakatiwalaan ang ipinakitang pamasahe.',
    ),
    DriverFeedbackQuestion(
      key: 'reliability',
      english: 'The app worked reliably throughout the trip.',
      filipino: 'Maayos at tuloy-tuloy na gumana ang app sa buong biyahe.',
    ),
    DriverFeedbackQuestion(
      key: 'safety_confidence',
      english: 'I knew where to find help or report a safety issue.',
      filipino: 'Alam ko kung saan hihingi ng tulong o mag-uulat ng panganib.',
    ),
    DriverFeedbackQuestion(
      key: 'continued_use',
      english: 'I would use ArangCada for future trips.',
      filipino: 'Gagamitin ko ang ArangCada sa mga susunod na biyahe.',
    ),
  ];

  static bool hasValidAnswers(Map<String, int> answers) =>
      answers.length == questions.length &&
      questions.every((question) {
        final score = answers[question.key];
        return score != null && score >= 1 && score <= 5;
      });
}
