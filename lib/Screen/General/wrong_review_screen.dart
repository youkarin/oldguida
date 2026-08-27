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
  String _sortType = 'time'; // 'time', 'chapter', 'count'

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _applySort() {
    setState(() {
      if (_sortType == 'time') {
        _wrongQuestions.sort((a, b) {
          final timeA = a['wrong_time'] ?? '';
          final timeB = b['wrong_time'] ?? '';
          return timeB.compareTo(timeA); // Newest first
        });
      } else if (_sortType == 'chapter') {
        _wrongQuestions.sort((a, b) {
          final sectionA = a['section_id'] ?? 0;
          final sectionB = b['section_id'] ?? 0;
          if (sectionA != sectionB) return sectionA.compareTo(sectionB);
          final numA = a['question_number'] ?? 0;
          final numB = b['question_number'] ?? 0;
          return numA.compareTo(numB);
        });
      } else if (_sortType == 'count') {
        _wrongQuestions.sort((a, b) {
          final countA = a['wrong_count'] ?? 0;
          final countB = b['wrong_count'] ?? 0;
          return countB.compareTo(countA); // Most frequent first
        });
      }
    });
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
        _applySort();
      });
    } else {
      setState(() {
        _wrongQuestions.clear();
      });
    }
  }

  Future<void> _retakeQuiz() async {
    final questions = _wrongQuestions.map((e) => Question.fromMap(e)).toList()
      ..shuffle();
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
          stayOnWrongAnswer: false,
          collapsedMode: collapsedMode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F4), // Light grey-green background
      appBar: AppBar(
        title:
            const Text('错题复习', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.teal[300], // Fresh Teal color
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_wrongQuestions.isNotEmpty) ...[
            PopupMenuButton<String>(
              icon: const Icon(Icons.sort),
              tooltip: '排序',
              onSelected: (String value) {
                _sortType = value;
                _applySort();
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'time',
                  child: ListTile(
                    leading: Icon(Icons.access_time),
                    title: Text('按时间 (最新优先)'),
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'chapter',
                  child: ListTile(
                    leading: Icon(Icons.book),
                    title: Text('按章节 (顺序)'),
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'count',
                  child: ListTile(
                    leading: Icon(Icons.format_list_numbered),
                    title: Text('按错误次数'),
                  ),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: _confirmClearAll,
              tooltip: '清空错题',
            ),
          ],
        ],
      ),
      body: _wrongQuestions.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _wrongQuestions.length,
              itemBuilder: (context, index) {
                return _buildWrongQuestionCard(index);
              },
            ),
      floatingActionButton:
          widget.historyId == null && _wrongQuestions.isNotEmpty
              ? FloatingActionButton.extended(
                  onPressed: _retakeQuiz,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('重新练习'),
                  backgroundColor: Colors.teal[400],
                )
              : null,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline, size: 80, color: Colors.teal[100]),
          const SizedBox(height: 16),
          Text('太棒了，目前没有错题！',
              style: TextStyle(fontSize: 18, color: Colors.teal[700])),
        ],
      ),
    );
  }

  Widget _buildWrongQuestionCard(int index) {
    final item = _wrongQuestions[index];
    final wrongCount = item['wrong_count'] ?? 1;
    final questionText = item['question'];
    final translation = item['translation'] ?? '';
    final explanation = item['explanation'] ?? '';
    final imageUrl = item['image_url'];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    questionText,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w500, height: 1.4),
                  ),
                ),
                const SizedBox(width: 8),
                // Wrong count badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red[100]!),
                  ),
                  child: Text(
                    '错误 $wrongCount 次',
                    style: TextStyle(
                        color: Colors.red[700],
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            if (imageUrl != null && imageUrl.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    imageUrl,
                    height: 120,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox(),
                  ),
                ),
              ),
            const Divider(height: 24),
            if (translation.isNotEmpty)
              _buildInfoRow('翻译', translation, Colors.blueGrey[700]!),
            if (explanation.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _buildInfoRow('解析', explanation, Colors.teal[700]!),
              ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _deleteItem(index),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('移除此题'),
                  style:
                      TextButton.styleFrom(foregroundColor: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String content, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color.withOpacity(0.7))),
        const SizedBox(height: 2),
        Text(content,
            style: TextStyle(fontSize: 14, color: color, height: 1.4)),
      ],
    );
  }

  Future<void> _deleteItem(int index) async {
    final item = _wrongQuestions[index];
    if (_userId != null) {
      await DatabaseHelper.instance.removeWrongAnswer(
          _userId!, item['section_id'], item['question_number']);
    }
    setState(() {
      _wrongQuestions.removeAt(index);
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('已从错题本移除'), duration: Duration(seconds: 1)));
    }
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清空'),
        content: const Text('确定要清空所有错题记录吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && _userId != null) {
      await DatabaseHelper.instance.clearWrongAnswers(_userId!);
      _loadData();
    }
  }
}
