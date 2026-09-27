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

/// The level-of-implementation survey (capstone Objective 4): whether TODA
/// drivers find the platform usable, operational and adopted in their daily
/// work, on the paper's 5-point Strongly Disagree..Strongly Agree scale.
///
/// Each item asks one thing, from the driver's side. The keys are fixed: the
/// database constraint and the admin evaluation averages are keyed by them,
/// so wording may change but a key may not be renamed without a migration.
abstract final class DriverAppFeedback {
  static const questions = <DriverFeedbackQuestion>[
    // Usable
    DriverFeedbackQuestion(
      key: 'ease_of_use',
      english: 'ArangCada is easy to use while I am working.',
      filipino: 'Madaling gamitin ang ArangCada habang nagtatrabaho ako.',
    ),
    DriverFeedbackQuestion(
      key: 'booking_clarity',
      english: 'I can understand a ride request quickly.',
      filipino: 'Mabilis kong naiintindihan ang bawat kahilingan sa biyahe.',
    ),
    DriverFeedbackQuestion(
      key: 'navigation_clarity',
      english: "Finding the passenger's pickup point is easy.",
      filipino: 'Madaling hanapin ang sakayan ng pasahero.',
    ),
    // Operational
    DriverFeedbackQuestion(
      key: 'fare_fairness',
      english: 'I trust the fare that the app shows.',
      filipino: 'Tiwala ako sa pamasaheng ipinapakita ng app.',
    ),
    DriverFeedbackQuestion(
      key: 'reliability',
      english: 'The app keeps working without problems during trips.',
      filipino:
          'Tuloy-tuloy na gumagana ang app nang walang problema sa biyahe.',
    ),
    DriverFeedbackQuestion(
      key: 'safety_confidence',
      english: 'I know how to send an SOS if something goes wrong on a trip.',
      filipino:
          'Alam ko kung paano magpadala ng SOS kapag may problema sa biyahe.',
    ),
    // Adopted
    DriverFeedbackQuestion(
      key: 'continued_use',
      english: 'I would use ArangCada in my daily work as a driver.',
      filipino: 'Gagamitin ko ang ArangCada sa araw-araw kong pamamasada.',
    ),
  ];

  static bool hasValidAnswers(Map<String, int> answers) =>
      answers.length == questions.length &&
      questions.every((question) {
        final score = answers[question.key];
        return score != null && score >= 1 && score <= 5;
      });
}
