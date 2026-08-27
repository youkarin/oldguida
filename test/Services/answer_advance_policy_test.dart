import 'package:flutter_test/flutter_test.dart';

import 'package:italian_driving_app/Services/answer_advance_policy.dart';

void main() {
  test('auto-advance policy covers every setting combination', () {
    expect(
      shouldAutoAdvance(
        immediateFeedback: false,
        stayOnWrongAnswer: false,
        isCorrect: false,
      ),
      isTrue,
    );
    expect(
      shouldAutoAdvance(
        immediateFeedback: false,
        stayOnWrongAnswer: true,
        isCorrect: false,
      ),
      isTrue,
    );
    expect(
      shouldAutoAdvance(
        immediateFeedback: true,
        stayOnWrongAnswer: false,
        isCorrect: false,
      ),
      isTrue,
    );
    expect(
      shouldAutoAdvance(
        immediateFeedback: true,
        stayOnWrongAnswer: true,
        isCorrect: false,
      ),
      isFalse,
    );
    expect(
      shouldAutoAdvance(
        immediateFeedback: true,
        stayOnWrongAnswer: true,
        isCorrect: true,
      ),
      isTrue,
    );
  });

  test('only a stored wrong result in stay mode locks re-answering', () {
    expect(
      shouldLockAnsweredQuestion(
        immediateFeedback: true,
        stayOnWrongAnswer: true,
        previousResult: false,
      ),
      isTrue,
    );
    expect(
      shouldLockAnsweredQuestion(
        immediateFeedback: true,
        stayOnWrongAnswer: true,
        previousResult: true,
      ),
      isFalse,
    );
    expect(
      shouldLockAnsweredQuestion(
        immediateFeedback: true,
        stayOnWrongAnswer: false,
        previousResult: false,
      ),
      isFalse,
    );
    expect(
      shouldLockAnsweredQuestion(
        immediateFeedback: false,
        stayOnWrongAnswer: true,
        previousResult: false,
      ),
      isTrue,
    );
    expect(
      shouldLockAnsweredQuestion(
        immediateFeedback: true,
        stayOnWrongAnswer: true,
        previousResult: null,
      ),
      isFalse,
    );
  });
}
