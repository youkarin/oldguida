import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:italian_driving_app/database/database_helper.dart';
import 'package:italian_driving_app/models/question_model.dart';
import 'package:italian_driving_app/Services/auth_service.dart';
import 'exam_general.dart';
import 'history_detail_screen.dart';

class StudyRecordScreen extends StatefulWidget {
  const StudyRecordScreen({Key? key}) : super(key: key);

  @override
  State<StudyRecordScreen> createState() => _StudyRecordScreenState();
}

class _StudyRecordScreenState extends State<StudyRecordScreen> {
  List<Map<String, dynamic>> _history = [];
  int? _userId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _userId = await AuthService().ensureLocalUser();
    if (_userId == null) {
      print('[StudyRecordScreen] failed to ensure local user');
      return;
    }
    print('[StudyRecordScreen] userId: $_userId');
    final hist = await DatabaseHelper.instance.getQuizHistory(_userId!);
    setState(() {
      _history = hist;
    });
  }

  bool _isPass(Map<String, dynamic> item) {
    int wrong = (item[columnHistoryTotalQuestions] ?? 0) -
        (item[columnHistoryScore] ?? 0);
    return wrong <= 3;
  }

  void _view(Map<String, dynamic> item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HistoryDetailScreen(historyId: item[columnHistoryId]),
      ),
    );
  }

  Future<void> _redo(Map<String, dynamic> item) async {
    final historyId = item[columnHistoryId];
    final data =
        await DatabaseHelper.instance.getHistoryQuestions(historyId);
    if (data.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无题目')));
      return;
    }
    final questions = data.map((e) => Question.fromMap(e)).toList();
    
    final prefs = await SharedPreferences.getInstance();
    final showTranslation = prefs.getBool('showTranslation') ?? true;
    final showExplanation = prefs.getBool('showExplanation') ?? true;
    final collapsedMode = prefs.getBool('collapsedMode') ?? false;

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExamGeneral(
          isRandom: false,
          questions: questions,
          showTranslation: showTranslation,
          showExplanation: showExplanation,
          immediateFeedback: false,
          collapsedMode: collapsedMode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('学习记录'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: _history.isEmpty
          ? const Center(child: Text('暂无历史'))
          : ListView.builder(
              itemCount: _history.length,
              itemBuilder: (context, index) {
                final item = _history[index];
                int wrong = (item[columnHistoryTotalQuestions] ?? 0) -
                    (item[columnHistoryScore] ?? 0);
                DateTime? time = item[columnHistoryCompletedAt] != null
                    ? DateTime.tryParse(item[columnHistoryCompletedAt])
                    : null;
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: ListTile(
                    leading: Icon(
                      _isPass(item)
                          ? Icons.sentiment_satisfied
                          : Icons.sentiment_dissatisfied,
                      color:
                          _isPass(item) ? Colors.green : Colors.red,
                    ),
                    title: Text(
                        time != null ? time.toLocal().toString() : '未知时间'),
                    subtitle: Text('用时 ${item[columnHistoryUsedTime] ?? 0} 秒  错题 $wrong'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                            onPressed: () => _view(item),
                            child: const Text('查看')),
                        TextButton(
                            onPressed: () => _redo(item),
                            child: const Text('重做')),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}