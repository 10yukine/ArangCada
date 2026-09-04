import 'package:arangcada/domain/models/driver_app_feedback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'the bilingual instrument has seven stable required ISO-linked items',
    () {
      expect(DriverAppFeedback.questions.map((item) => item.key), [
        'ease_of_use',
        'booking_clarity',
        'navigation_clarity',
        'fare_fairness',
        'reliability',
        'safety_confidence',
        'continued_use',
      ]);
      for (final item in DriverAppFeedback.questions) {
        expect(item.english, isNotEmpty);
        expect(item.filipino, isNotEmpty);
      }
    },
  );

  test('all required answers must be on the five-point Likert scale', () {
    final answers = {
      for (final item in DriverAppFeedback.questions) item.key: 4,
    };

    expect(DriverAppFeedback.hasValidAnswers(answers), isTrue);
    expect(
      DriverAppFeedback.hasValidAnswers({...answers, 'fare_fairness': 6}),
      isFalse,
    );
    expect(
      DriverAppFeedback.hasValidAnswers({...answers}..remove('reliability')),
      isFalse,
    );
  });
}
