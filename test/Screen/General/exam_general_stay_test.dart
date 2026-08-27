import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:italian_driving_app/Screen/General/exam_general.dart';
import 'package:italian_driving_app/models/question_model.dart';

void main() {
  Future<void> pumpExam(
    WidgetTester tester, {
    required bool immediateFeedback,
    required bool stayOnWrongAnswer,
  }) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: ExamGeneral(
          isRandom: false,
          questions: [
            Question(
              sectionId: 1,
              questionNumber: 1,
              question: 'First question',
              translation: '',
              explanation: '',
              answer: 1,
            ),
            Question(
              sectionId: 1,
              questionNumber: 2,
              question: 'Second question',
              translation: '',
              explanation: '',
              answer: 0,
            ),
          ],
          showTranslation: false,
          showExplanation: false,
          immediateFeedback: immediateFeedback,
          stayOnWrongAnswer: stayOnWrongAnswer,
          loadUser: () async => null,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
      'wrong answer stays after the normal delay and locks re-answering',
      (tester) async {
    await pumpExam(
      tester,
      immediateFeedback: true,
      stayOnWrongAnswer: true,
    );

    await tester.tap(find.text('Falso'));
    await tester.pump();
    expect(find.text('回答错误'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('Q1:'), findsOneWidget);
    expect(find.text('29:58'), findsOneWidget);

    await tester.tap(find.text('Vero'));
    await tester.pump();
    expect(find.text('回答错误'), findsOneWidget);
    expect(find.text('正确答案！'), findsNothing);
  });

  testWidgets('manual next works after a retained wrong answer',
      (tester) async {
    await pumpExam(
      tester,
      immediateFeedback: true,
      stayOnWrongAnswer: true,
    );

    await tester.tap(find.text('Falso'));
    await tester.pump();
    await tester.tap(find.text('下一题'));
    await tester.pump();

    expect(find.textContaining('Q2:'), findsOneWidget);
  });

  testWidgets('question-number navigation works after a retained wrong answer',
      (tester) async {
    await pumpExam(
      tester,
      immediateFeedback: true,
      stayOnWrongAnswer: true,
    );

    await tester.tap(find.text('Falso'));
    await tester.pump();
    await tester.tap(find.text('2'));
    await tester.pump();

    expect(find.textContaining('Q2:'), findsOneWidget);
  });

  testWidgets('correct answer still advances after 600 milliseconds',
      (tester) async {
    await pumpExam(
      tester,
      immediateFeedback: true,
      stayOnWrongAnswer: true,
    );

    await tester.tap(find.text('Vero'));
    await tester.pump(const Duration(milliseconds: 599));
    expect(find.textContaining('Q1:'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1));
    expect(find.textContaining('Q2:'), findsOneWidget);
  });

  testWidgets('changing a correct answer to wrong cancels the pending advance',
      (tester) async {
    await pumpExam(
      tester,
      immediateFeedback: true,
      stayOnWrongAnswer: true,
    );

    await tester.tap(find.text('Vero'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Falso'));
    await tester.pump();
    expect(find.text('回答错误'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 301));
    expect(find.textContaining('Q1:'), findsOneWidget);
    expect(find.text('回答错误'), findsOneWidget);
  });

  for (final answerLabel in ['Vero', 'Falso']) {
    testWidgets(
        'non-immediate $answerLabel answer keeps the existing 300 ms advance',
        (tester) async {
      await pumpExam(
        tester,
        immediateFeedback: false,
        stayOnWrongAnswer: true,
      );

      await tester.tap(find.text(answerLabel));
      await tester.pump(const Duration(milliseconds: 299));
      expect(find.textContaining('Q1:'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1));
      expect(find.textContaining('Q2:'), findsOneWidget);
    });

    testWidgets(
        'immediate $answerLabel answer without stay keeps the existing 600 ms advance',
        (tester) async {
      await pumpExam(
        tester,
        immediateFeedback: true,
        stayOnWrongAnswer: false,
      );

      await tester.tap(find.text(answerLabel));
      await tester.pump(const Duration(milliseconds: 599));
      expect(find.textContaining('Q1:'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1));
      expect(find.textContaining('Q2:'), findsOneWidget);
    });
  }
}
