import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:italian_driving_app/database/database_helper.dart';
import 'package:italian_driving_app/models/question_model.dart';
import 'package:italian_driving_app/Services/auth_service.dart';
import 'exam_general.dart';

/// 错题复习页面
class WrongReviewScreen extends StatefulWidget {
  final int? historyId;
  const WrongReviewScreen({Key? key, this.historyId}) : super(key: key);

  @override
  State<WrongReviewScreen> createState() => _WrongReviewScreenState();
}

class _WrongReviewScreenState extends State<WrongReviewScreen> {
  final List<Map<String, dynamic>> _wrongQuestions = [];
  int? _userId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    _userId = await AuthService().ensureLocalUser();
    print('[WrongReviewScreen] userId: $_userId');
    
    if (_userId != null) {
      final questions = widget.historyId != null
          ? await DatabaseHelper.instance
              .getWrongAnswersByHistory(widget.historyId!)
          : await DatabaseHelper.instance.getWrongAnswerQuestions(_userId!);
      setState(() {
        _wrongQuestions
          ..clear()
          ..addAll(questions);
      });
    } else {
      setState(() {
        _wrongQuestions.clear();
      });
    }
  }

  Future<void> _retakeQuiz() async {
    final questions =
        _wrongQuestions.map((e) => Question.fromMap(e)).toList()..shuffle();
    if (questions.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('暂无错题')));
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final showTranslation = prefs.getBool('showTranslation') ?? true;
    final showExplanation = prefs.getBool('showExplanation') ?? true;
    final collapsedMode = prefs.getBool('collapsedMode') ?? false;

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
        title: const Text('错题复习'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: _wrongQuestions.isEmpty
          ? const Center(child: Text('暂无错题'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _wrongQuestions.length,
              itemBuilder: (context, index) {
                final item = _wrongQuestions[index];
                return Dismissible(
                  key: ValueKey('${item['section_id']}-${item['question_number']}'),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) async {
                    if (_userId != null) {
                      await DatabaseHelper.instance.removeWrongAnswer(
                          _userId!, item['section_id'], item['question_number']);
                      // Sync removed
                    }
                    setState(() {
                      _wrongQuestions.removeAt(index);
                    });
                  },
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: ListTile(
                      title: Text('${item['question']}'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (item['image_url'] != null &&
                              (item['image_url'] as String).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 8),
                              child: Image.asset(
                                item['image_url'],
                                height: 100,
                                fit: BoxFit.contain,
                              ),
                            ),
                          Text('翻译: ${item['translation'] ?? ''}'),
                          Text('解析: ${item['explanation'] ?? ''}'),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: widget.historyId == null
          ? FloatingActionButton.extended(
              onPressed: _retakeQuiz,
              icon: const Icon(Icons.shuffle),
              label: const Text('随机练习'),
              backgroundColor: Colors.deepPurple,
            )
          : null,
    );
  }
}