import 'package:flutter/material.dart';
import 'package:italian_driving_app/database/database_helper.dart'; // 按你的实际路径修改
import 'package:italian_driving_app/models/question_model.dart'; // Question 模型
import 'practice_screen.dart';
import 'exam_general.dart'; // 同级导入考试页面
import 'package:shared_preferences/shared_preferences.dart';

class ExamScreen extends StatefulWidget {
  const ExamScreen({super.key});

  @override
  State<ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends State<ExamScreen> {
  Future<void> _startExam() async {
    final db = DatabaseHelper.instance;

    // 随机抽取题目用于模拟考试
    final rawQuestions = await db.getAllQuestionsRandomWithSectionImage();

    final questions = rawQuestions
        .take(30)
        .map((q) => Question.fromMap(q))
        .toList();

    // 读取全局设置
    final prefs = await SharedPreferences.getInstance();
    final showTranslation = prefs.getBool('showTranslation') ?? true;
    final showExplanation = prefs.getBool('showExplanation') ?? true;
    final immediateFeedback = prefs.getBool('immediateFeedback') ?? false;

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExamGeneral(
          isRandom: true,
          questions: questions,
          showTranslation: showTranslation,
          showExplanation: showExplanation,
          immediateFeedback: immediateFeedback,
        ),
      ),
    );
  }

  void _openPractice() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PracticeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('测试 - Quiz'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.orange.withOpacity(0.1), Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _openPractice,
                icon: const Icon(Icons.school),
                label: const Text('选章节练习'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _startExam,
                icon: const Icon(Icons.shuffle),
                label: const Text('开始测验（随机30题）'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text('返回首页'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
