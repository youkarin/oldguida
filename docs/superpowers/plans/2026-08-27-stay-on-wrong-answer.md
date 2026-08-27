# Stay on Wrong Answer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in setting that keeps an immediately marked wrong answer on screen until the learner manually moves to another question.

**Architecture:** Persist the preference beside the existing `immediateFeedback` setting, conditionally expose it in Settings, and pass its effective value into the shared `ExamGeneral` flow. A small pure policy function makes the navigation combinations testable without timers, while `ExamGeneral` remains responsible for scheduling or suppressing automatic movement.

**Tech Stack:** Flutter/Dart, `shared_preferences`, Flutter unit and widget tests.

**Spec:** `docs/superpowers/specs/2026-08-27-keyword-translation-and-branding-design.md`

## Global Constraints

- The setting key is exactly `stayOnWrongAnswer` and defaults to `false`.
- The switch is visible only when `immediateFeedback` is `true`.
- Turning immediate feedback off makes stay-on-wrong ineffective but preserves its stored value.
- A wrong answer remains until manual `下一题` or question-number navigation.
- The first wrong answer is locked and cannot be overwritten by tapping the correct choice.
- Correct answers retain the existing 600 ms immediate-feedback auto-advance behavior.
- The timer continues while a wrong answer is displayed.
- Do not alter scoring, history, wrong-answer persistence, translation, or explanation rules.
- Do not stage unrelated generated plugin file changes.

---

## File Map

- Create `lib/Services/answer_advance_policy.dart`: pure decision helpers for answer locking and automatic movement.
- Modify `lib/Screen/General/settings_screen.dart`: persist and conditionally display the new switch.
- Modify `lib/Screen/General/exam_general.dart`: accept the setting and suppress movement after a wrong answer.
- Modify `lib/Screen/General/exam_screen.dart`: load and pass the effective setting.
- Modify `lib/Screen/General/practice_screen.dart`: load and pass the effective setting.
- Modify `lib/Screen/General/study_record_screen.dart`: explicitly pass `false` because immediate feedback is forced off.
- Modify `lib/Screen/General/wrong_review_screen.dart`: explicitly pass `false` because immediate feedback is forced off.
- Create `test/Services/answer_advance_policy_test.dart`: exhaustive truth-table tests.
- Create `test/Screen/General/settings_screen_test.dart`: conditional visibility and persistence tests.
- Create `test/Screen/General/exam_general_stay_test.dart`: timer and manual-navigation behavior tests using a minimal test harness.

### Task 1: Define and Test the Answer Advance Policy

**Files:**
- Create: `lib/Services/answer_advance_policy.dart`
- Create: `test/Services/answer_advance_policy_test.dart`

**Interfaces:**
- Produces: `bool shouldAutoAdvance({required bool immediateFeedback, required bool stayOnWrongAnswer, required bool isCorrect})`.
- Produces: `bool shouldLockAnsweredQuestion({required bool immediateFeedback, required bool stayOnWrongAnswer, required bool? previousResult})`.

- [ ] **Step 1: Write the complete policy truth table**

```dart
void main() {
  test('auto-advance policy covers every setting combination', () {
    expect(shouldAutoAdvance(immediateFeedback: false, stayOnWrongAnswer: false, isCorrect: false), isTrue);
    expect(shouldAutoAdvance(immediateFeedback: false, stayOnWrongAnswer: true, isCorrect: false), isTrue);
    expect(shouldAutoAdvance(immediateFeedback: true, stayOnWrongAnswer: false, isCorrect: false), isTrue);
    expect(shouldAutoAdvance(immediateFeedback: true, stayOnWrongAnswer: true, isCorrect: false), isFalse);
    expect(shouldAutoAdvance(immediateFeedback: true, stayOnWrongAnswer: true, isCorrect: true), isTrue);
  });

  test('only a stored wrong result in stay mode locks re-answering', () {
    expect(shouldLockAnsweredQuestion(immediateFeedback: true, stayOnWrongAnswer: true, previousResult: false), isTrue);
    expect(shouldLockAnsweredQuestion(immediateFeedback: true, stayOnWrongAnswer: true, previousResult: true), isFalse);
    expect(shouldLockAnsweredQuestion(immediateFeedback: true, stayOnWrongAnswer: false, previousResult: false), isFalse);
    expect(shouldLockAnsweredQuestion(immediateFeedback: false, stayOnWrongAnswer: true, previousResult: false), isTrue);
    expect(shouldLockAnsweredQuestion(immediateFeedback: true, stayOnWrongAnswer: true, previousResult: null), isFalse);
  });
}
```

- [ ] **Step 2: Run the test and observe failure**

Run: `flutter test test/Services/answer_advance_policy_test.dart`

Expected: FAIL because the policy functions are missing.

- [ ] **Step 3: Implement the pure policy**

```dart
bool shouldAutoAdvance({
  required bool immediateFeedback,
  required bool stayOnWrongAnswer,
  required bool isCorrect,
}) {
  return !(immediateFeedback && stayOnWrongAnswer && !isCorrect);
}

bool shouldLockAnsweredQuestion({
  required bool immediateFeedback,
  required bool stayOnWrongAnswer,
  required bool? previousResult,
}) {
  if (previousResult == null) return false;
  if (!immediateFeedback) return true;
  return stayOnWrongAnswer && previousResult == false;
}
```

- [ ] **Step 4: Run the policy test**

Run: `flutter test test/Services/answer_advance_policy_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit the policy**

```powershell
git add -- lib/Services/answer_advance_policy.dart test/Services/answer_advance_policy_test.dart
git commit -m "test: define wrong-answer advance policy"
```

### Task 2: Add the Conditional Settings Switch

**Files:**
- Modify: `lib/Screen/General/settings_screen.dart`
- Create: `test/Screen/General/settings_screen_test.dart`

**Interfaces:**
- Consumes existing `immediateFeedback` preference.
- Produces persisted `stayOnWrongAnswer` preference with a default of `false`.

- [ ] **Step 1: Write conditional visibility and persistence widget tests**

```dart
setUp(() {
  PackageInfo.setMockInitialValues(
    appName: 'OldGuida',
    packageName: 'italian_driving_app',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
  );
});

testWidgets('stay switch is hidden until immediate feedback is enabled', (tester) async {
  SharedPreferences.setMockInitialValues({
    'immediateFeedback': false,
    'stayOnWrongAnswer': true,
  });
  await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
  await tester.pumpAndSettle();
  expect(find.text('错题自动停留'), findsNothing);
  await tester.tap(find.text('立即提示正误'));
  await tester.pumpAndSettle();
  expect(find.text('错题自动停留'), findsOneWidget);
  expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '错题自动停留')).value, isTrue);
});

testWidgets('stay switch defaults off and persists a change', (tester) async {
  SharedPreferences.setMockInitialValues({'immediateFeedback': true});
  await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
  await tester.pumpAndSettle();
  final tile = find.widgetWithText(SwitchListTile, '错题自动停留');
  expect(tester.widget<SwitchListTile>(tile).value, isFalse);
  await tester.tap(tile);
  await tester.pumpAndSettle();
  expect((await SharedPreferences.getInstance()).getBool('stayOnWrongAnswer'), isTrue);
});
```

- [ ] **Step 2: Run settings tests and observe failure**

Run: `flutter test test/Screen/General/settings_screen_test.dart`

Expected: FAIL because the new preference and switch are missing.

- [ ] **Step 3: Add state loading and persistence**

```dart
bool _stayOnWrongAnswer = false;

// Inside _loadSettings setState:
_stayOnWrongAnswer = prefs.getBool('stayOnWrongAnswer') ?? false;

Future<void> _updateStayOnWrongAnswer(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('stayOnWrongAnswer', value);
  if (!mounted) return;
  setState(() => _stayOnWrongAnswer = value);
}
```

- [ ] **Step 4: Render the dependent switch**

Immediately after the existing `立即提示正误` tile, add:

```dart
if (_immediateFeedback)
  SwitchListTile(
    title: const Text('错题自动停留'),
    subtitle: const Text('答错后停留在当前题，手动点击下一题继续'),
    value: _stayOnWrongAnswer,
    onChanged: _updateStayOnWrongAnswer,
  ),
```

Do not set `_stayOnWrongAnswer` to false when immediate feedback is turned off.

- [ ] **Step 5: Run settings tests and analysis**

```powershell
flutter test test\Screen\General\settings_screen_test.dart
flutter analyze lib\Screen\General\settings_screen.dart
```

Expected: both commands exit 0.

- [ ] **Step 6: Commit the settings behavior**

```powershell
git add -- lib/Screen/General/settings_screen.dart test/Screen/General/settings_screen_test.dart
git commit -m "feat: add wrong-answer stay setting"
```

### Task 3: Pass the Effective Setting into Every ExamGeneral Caller

**Files:**
- Modify: `lib/Screen/General/exam_general.dart`
- Modify: `lib/Screen/General/exam_screen.dart`
- Modify: `lib/Screen/General/practice_screen.dart`
- Modify: `lib/Screen/General/study_record_screen.dart`
- Modify: `lib/Screen/General/wrong_review_screen.dart`
- Create: `test/Screen/General/exam_general_constructor_test.dart`

**Interfaces:**
- Produces constructor field `ExamGeneral.stayOnWrongAnswer`.
- `exam_screen.dart` and `practice_screen.dart` pass `immediateFeedback && storedStayOnWrongAnswer`.
- Replay and wrong-review flows that force `immediateFeedback: false` pass `stayOnWrongAnswer: false`.

- [ ] **Step 1: Write a constructor contract test**

```dart
test('ExamGeneral stores the effective stay setting', () {
  final widget = ExamGeneral(
    isRandom: false,
    questions: [questionFixture()],
    showTranslation: true,
    showExplanation: true,
    immediateFeedback: true,
    stayOnWrongAnswer: true,
  );
  expect(widget.stayOnWrongAnswer, isTrue);
});
```

- [ ] **Step 2: Run the test and observe failure**

Run: `flutter test test/Screen/General/exam_general_constructor_test.dart`

Expected: FAIL because the constructor field is missing.

- [ ] **Step 3: Add the required constructor field**

```dart
final bool stayOnWrongAnswer;

const ExamGeneral({
  super.key,
  required this.isRandom,
  required this.questions,
  required this.showTranslation,
  required this.showExplanation,
  required this.immediateFeedback,
  required this.stayOnWrongAnswer,
  this.collapsedMode = false,
});
```

- [ ] **Step 4: Load and pass the effective setting in normal entry points**

In both `exam_screen.dart` and `practice_screen.dart`:

```dart
final immediateFeedback = prefs.getBool('immediateFeedback') ?? false;
final storedStayOnWrongAnswer = prefs.getBool('stayOnWrongAnswer') ?? false;
final stayOnWrongAnswer = immediateFeedback && storedStayOnWrongAnswer;
```

Pass `stayOnWrongAnswer: stayOnWrongAnswer`. In `study_record_screen.dart` and `wrong_review_screen.dart`, pass `stayOnWrongAnswer: false` alongside the existing `immediateFeedback: false`.

- [ ] **Step 5: Prove all constructor calls compile**

```powershell
rg -n "ExamGeneral\(" lib test
flutter test test\Screen\General\exam_general_constructor_test.dart
flutter analyze lib\Screen\General
```

Expected: every `ExamGeneral` call supplies `stayOnWrongAnswer`; tests and analysis exit 0.

- [ ] **Step 6: Commit constructor plumbing**

```powershell
git add -- lib/Screen/General/exam_general.dart lib/Screen/General/exam_screen.dart lib/Screen/General/practice_screen.dart lib/Screen/General/study_record_screen.dart lib/Screen/General/wrong_review_screen.dart test/Screen/General/exam_general_constructor_test.dart
git commit -m "feat: pass wrong-answer stay preference to exams"
```

### Task 4: Enforce Wrong-Answer Stay and First-Answer Locking

**Files:**
- Modify: `lib/Screen/General/exam_general.dart`
- Create: `test/Screen/General/exam_general_stay_test.dart`

**Interfaces:**
- Consumes: `shouldAutoAdvance` and `shouldLockAnsweredQuestion`.
- Produces: timer-safe suppression of `_nextQuestion()` after a wrong answer.

- [ ] **Step 1: Write fake-time behavior tests**

```dart
testWidgets('wrong answer stays after the normal delay and locks re-answering', (tester) async {
  await tester.pumpWidget(examHarness(
    answers: [1, 0],
    immediateFeedback: true,
    stayOnWrongAnswer: true,
  ));
  await tester.tap(find.text('Falso'));
  await tester.pump();
  expect(find.text('回答错误'), findsOneWidget);
  await tester.pump(const Duration(seconds: 2));
  expect(find.textContaining('Q1:'), findsOneWidget);
  await tester.tap(find.text('Vero'));
  await tester.pump();
  expect(find.text('回答错误'), findsOneWidget);
});

testWidgets('manual next works after a retained wrong answer', (tester) async {
  await tester.pumpWidget(examHarness(immediateFeedback: true, stayOnWrongAnswer: true));
  await tester.tap(find.text('Falso'));
  await tester.pump();
  await tester.tap(find.text('下一题'));
  await tester.pump();
  expect(find.textContaining('Q2:'), findsOneWidget);
});

testWidgets('correct answer still advances after 600 milliseconds', (tester) async {
  await tester.pumpWidget(examHarness(immediateFeedback: true, stayOnWrongAnswer: true));
  await tester.tap(find.text('Vero'));
  await tester.pump(const Duration(milliseconds: 601));
  expect(find.textContaining('Q2:'), findsOneWidget);
});
```

The harness must inject a local user/database boundary or test-mode callbacks so no Supabase or filesystem operation is needed to submit an answer.

- [ ] **Step 2: Run behavior tests and observe failure**

Run: `flutter test test/Screen/General/exam_general_stay_test.dart`

Expected: the wrong-answer test advances or allows the answer to change.

- [ ] **Step 3: Apply locking and auto-advance policy in `_submitAnswer`**

```dart
void _submitAnswer(bool answer) {
  if (shouldLockAnsweredQuestion(
    immediateFeedback: widget.immediateFeedback,
    stayOnWrongAnswer: widget.stayOnWrongAnswer,
    previousResult: answerResults[currentIndex],
  )) {
    return;
  }

  final isCorrect = widget.questions[currentIndex].answer == (answer ? 1 : 0);
  setState(() {
    userAnswers[currentIndex] = answer ? 1 : 0;
    answerResults[currentIndex] = isCorrect;
  });

  if (!shouldAutoAdvance(
    immediateFeedback: widget.immediateFeedback,
    stayOnWrongAnswer: widget.stayOnWrongAnswer,
    isCorrect: isCorrect,
  )) {
    return;
  }

  final tappedIndex = currentIndex;
  final delay = widget.immediateFeedback ? 600 : 300;
  Future.delayed(Duration(milliseconds: delay), () {
    if (mounted && currentIndex == tappedIndex && currentIndex < widget.questions.length - 1) {
      _nextQuestion();
    }
  });
}
```

Keep `_nextQuestion`, question-number navigation, timer state, scoring arrays, and persistence code unchanged.

- [ ] **Step 4: Run focused and full tests**

```powershell
flutter test test\Services\answer_advance_policy_test.dart test\Screen\General\exam_general_stay_test.dart
flutter test
flutter analyze
```

Expected: all commands exit 0.

- [ ] **Step 5: Manually verify the setting combinations**

Run the app and check these exact cases:

| Immediate feedback | Stay on wrong | Wrong result | Correct result |
|---|---|---|---|
| Off | Hidden/ineffective | Existing 300 ms movement | Existing 300 ms movement |
| On | Off | Existing 600 ms movement | Existing 600 ms movement |
| On | On | No automatic movement; first result locked | Existing 600 ms movement |

While retained on a wrong answer, confirm the countdown continues and `下一题` plus question-number navigation remain enabled.

- [ ] **Step 6: Commit answer-flow behavior**

```powershell
git add -- lib/Screen/General/exam_general.dart test/Screen/General/exam_general_stay_test.dart
git commit -m "feat: retain immediately marked wrong answers"
```
