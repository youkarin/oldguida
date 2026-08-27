import 'package:flutter_test/flutter_test.dart';
import 'package:italian_driving_app/Screen/General/exam_general.dart';
import 'package:italian_driving_app/models/question_model.dart';

void main() {
  test('ExamGeneral stores the effective stay setting', () {
    final widget = ExamGeneral(
      isRandom: false,
      questions: [
        Question(
          sectionId: 1,
          questionNumber: 1,
          question: 'Question',
          translation: 'Translation',
          explanation: 'Explanation',
          answer: 1,
        ),
      ],
      showTranslation: true,
      showExplanation: true,
      immediateFeedback: true,
      stayOnWrongAnswer: true,
    );

    expect(widget.stayOnWrongAnswer, isTrue);
  });
}
