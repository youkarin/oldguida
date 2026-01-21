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
    final collapsedMode = prefs.getBool('collapsedMode') ?? false;

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
          collapsedMode: collapsedMode,
        ),
      ),
    );
  }

  void _openPractice({bool isSequential = false}) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PracticeScreen(isSequential: isSequential)),
    );
  }

  Widget _buildMenuButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return SizedBox(
      width: 280, // Fixed width for all buttons
      height: 60,  // Fixed height for all buttons
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 28),
        label: Text(
          label,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
      ),
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
        centerTitle: true,
      ),
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.orange.withOpacity(0.1), Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.quiz_outlined,
              size: 80,
              color: Colors.orange,
            ),
            const SizedBox(height: 40),
            _buildMenuButton(
              onPressed: () => _openPractice(isSequential: false),
              icon: Icons.school,
              label: '章节练习 (随机)',
              color: Colors.blueAccent,
            ),
            const SizedBox(height: 20),
            _buildMenuButton(
              onPressed: () => _openPractice(isSequential: true),
              icon: Icons.format_list_numbered,
              label: '章节练习 (顺序)',
              color: Colors.indigo,
            ),
            const SizedBox(height: 20),
            _buildMenuButton(
              onPressed: _startExam,
              icon: Icons.shuffle,
              label: '全真模拟 (随机)',
              color: Colors.teal,
            ),
            const SizedBox(height: 40),
            _buildMenuButton(
              onPressed: () => Navigator.pop(context),
              icon: Icons.home,
              label: '返回首页',
              color: Colors.orange,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
