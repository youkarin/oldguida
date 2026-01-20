import 'package:flutter/material.dart';
import 'package:italian_driving_app/database/database_helper.dart';

class HistoryDetailScreen extends StatefulWidget {
  final int historyId;
  const HistoryDetailScreen({Key? key, required this.historyId}) : super(key: key);

  @override
  State<HistoryDetailScreen> createState() => _HistoryDetailScreenState();
}

class _HistoryDetailScreenState extends State<HistoryDetailScreen> {
  final List<Map<String, dynamic>> _questions = [];

  String _answerText(int? value) {
    if (value == null) return '未作答';
    return value == 1 ? '✔️ Vero' : '❌ Falso';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await DatabaseHelper.instance.getHistoryQuestions(widget.historyId);
    setState(() {
      _questions
        ..clear()
        ..addAll(data);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('记录详情'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: _questions.isEmpty
          ? const Center(child: Text('暂无数据'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _questions.length,
              itemBuilder: (context, index) {
                final item = _questions[index];
                final userAns = item['user_answer'];
                final correctAns = item['answer'];
                IconData icon;
                Color color;
                if (userAns == null) {
                  icon = Icons.help_outline;
                  color = Colors.grey;
                } else if (userAns == correctAns) {
                  icon = Icons.check_circle;
                  color = Colors.green;
                } else {
                  icon = Icons.cancel;
                  color = Colors.red;
                }
                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(icon, color: color),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('${item['question']}'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text('你的答案: ${_answerText(userAns)}'),
                            ),
                            Expanded(
                              child:
                                  Text('正确答案: ${_answerText(correctAns)}'),
                            ),
                          ],
                        ),
                        if (item['image_url'] != null &&
                            (item['image_url'] as String).isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Image.asset(
                              item['image_url'],
                              height: 100,
                              fit: BoxFit.contain,
                            ),
                          ),
                        const SizedBox(height: 8),
                        Text('翻译: ${item['translation'] ?? ''}'),
                        Text('解析: ${item['explanation'] ?? ''}'),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
