import 'package:flutter/material.dart';
import 'package:italian_driving_app/models/question_model.dart';

class FinalScorePage extends StatelessWidget {
  final Duration duration;
  final int correctCount;
  final int wrongCount;
  final List<Question> questions;
  final List<int?> userAnswers;

  const FinalScorePage({
    super.key,
    required this.duration,
    required this.correctCount,
    required this.wrongCount,
    required this.questions,
    required this.userAnswers,
  });

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '${minutes}分${seconds.toString().padLeft(2, '0')}秒';
  }

  String _answerText(int? value) {
    if (value == null) return '未作答';
    return value == 1 ? '✔️ Vero' : '❌ Falso';
  }

  @override
  Widget build(BuildContext context) {
    final total = questions.length;
    final passed = (correctCount / total) >= 0.9;

    return Scaffold(
      appBar: AppBar(
        title: const Text('考试结果'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  Icon(
                    passed ? Icons.emoji_emotions : Icons.emoji_emotions_outlined,
                    color: passed ? Colors.green : Colors.red,
                    size: 48,
                  ),
                  Text(
                    passed ? '🎉 恭喜你通过考试！' : '😢 Noob. 菜就多练',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: passed ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text('用时：${_formatDuration(duration)}', style: const TextStyle(fontSize: 16)),
            Text('答对：$correctCount 题', style: const TextStyle(color: Colors.green, fontSize: 16)),
            Text('答错：$wrongCount 题', style: const TextStyle(color: Colors.red, fontSize: 16)),
            const SizedBox(height: 16),
            const Text('答题回顾：', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: questions.length,
                itemBuilder: (context, index) {
                  final question = questions[index];
                  final userAnswer = userAnswers[index];
                  final isCorrect = userAnswer == question.answer;

                  return Card(
                    color: userAnswer == null
                        ? Colors.grey.shade200
                        : isCorrect
                        ? Colors.green.shade100
                        : Colors.red.shade100,
                    child: ListTile(
                      leading: question.imageUrl != null && question.imageUrl!.isNotEmpty
                          ? Image.asset(
                              question.imageUrl!,
                              width: 60,
                              height: 60,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.image_not_supported),
                            )
                          : const SizedBox(width: 60, height: 60),
                      title: Text('题目 ${index + 1}: ${question.question}'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text('你的答案: ${_answerText(userAnswer)}'),
                          Text('正确答案: ${_answerText(question.answer)}'),
                          const SizedBox(height: 4),
                          Text('翻译: ${question.translation}'),
                          Text('解析: ${question.explanation}'),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
