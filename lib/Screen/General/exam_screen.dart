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
    return Container(
      width: double.infinity,
      height: 70,
      margin: const EdgeInsets.only(bottom: 20),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: color,
          elevation: 0,
          side: BorderSide(color: color.withOpacity(0.5), width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 26, color: color),
            ),
            const SizedBox(width: 20),
            Text(
              label,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.blueGrey[900],
              ),
            ),
            const Spacer(),
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        title: const Text(
          '练习与测验',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "准备好开始了吗？",
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey[900],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "选择一个模式来提升你的驾驶知识",
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 40),
            _buildMenuButton(
              onPressed: () => _openPractice(isSequential: false),
              icon: Icons.auto_awesome_motion,
              label: '章节练习 (随机)',
              color: const Color(0xFF3F51B5),
            ),
            _buildMenuButton(
              onPressed: () => _openPractice(isSequential: true),
              icon: Icons.format_list_numbered_rounded,
              label: '章节练习 (顺序)',
              color: const Color(0xFF673AB7),
            ),
            _buildMenuButton(
              onPressed: _startExam,
              icon: Icons.assignment_turned_in_rounded,
              label: '全真模拟 (随机)',
              color: const Color(0xFF009688),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 20),
            _buildMenuButton(
              onPressed: () => Navigator.pop(context),
              icon: Icons.home_rounded,
              label: '返回首页',
              color: Colors.blueGrey,
            ),
          ],
        ),
      ),
    );
  }
}
