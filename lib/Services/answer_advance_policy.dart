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
