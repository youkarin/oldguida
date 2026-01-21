import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:italian_driving_app/database/database_helper.dart';

class HistoryDetailScreen extends StatefulWidget {
  final Map<String, dynamic> historyData;
  const HistoryDetailScreen({Key? key, required this.historyData}) : super(key: key);

  @override
  State<HistoryDetailScreen> createState() => _HistoryDetailScreenState();
}

class _HistoryDetailScreenState extends State<HistoryDetailScreen> {
  final List<Map<String, dynamic>> _questions = [];
  bool _isLoading = true;
  
  // Settings
  bool _showTranslation = true;
  bool _showExplanation = true;
  bool _collapsedMode = false;

  // Track expansion state for each question
  final Map<int, bool> _translationExpanded = {};
  final Map<int, bool> _explanationExpanded = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    // 1. Load Settings
    final prefs = await SharedPreferences.getInstance();
    final showTrans = prefs.getBool('showTranslation') ?? true;
    final showExpl = prefs.getBool('showExplanation') ?? true;
    final collapsed = prefs.getBool('collapsedMode') ?? false;

    // 2. Load Questions
    final historyId = widget.historyData['id'];
    final data = await DatabaseHelper.instance.getHistoryQuestions(historyId);

    if (mounted) {
      setState(() {
        _showTranslation = showTrans;
        _showExplanation = showExpl;
        _collapsedMode = collapsed;
        
        _questions.clear();
        _questions.addAll(data);
        
        // Initialize expansion states based on collapsedMode
        for (int i = 0; i < _questions.length; i++) {
          _translationExpanded[i] = !collapsed;
          _explanationExpanded[i] = !collapsed;
        }
        
        _isLoading = false;
      });
    }
  }

  String _answerText(int? value) {
    if (value == null) return '未作答';
    return value == 1 ? '✔️ Vero' : '❌ Falso';
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final score = widget.historyData['score'] ?? 0;
    final total = widget.historyData['total_questions'] ?? 0;
    final usedTime = widget.historyData['used_time'] ?? 0;
    final accuracy = total > 0 ? (score / total * 100).toStringAsFixed(1) : '0.0';
    final completedAt = widget.historyData['completed_at'];
    DateTime? date;
    if (completedAt != null) {
      date = DateTime.tryParse(completedAt);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('记录详情'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildSummaryCard(score, total, usedTime, accuracy, date),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _questions.length,
                    itemBuilder: (context, index) {
                      return _buildQuestionCard(index);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSummaryCard(int score, int total, int usedTime, String accuracy, DateTime? date) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSummaryItem(Icons.grade, '$score/$total', '得分', Colors.orange),
              _buildSummaryItem(Icons.timer, _formatTime(usedTime), '用时', Colors.blue),
              _buildSummaryItem(Icons.pie_chart, '$accuracy%', '正确率', Colors.green),
            ],
          ),
          if (date != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '提交时间: ${date.toLocal().toString().split('.')[0]}',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildQuestionCard(int index) {
    final item = _questions[index];
    final userAns = item['user_answer'];
    final correctAns = item['answer'];
    final questionText = item['question'];
    final translation = item['translation'] ?? '';
    final explanation = item['explanation'] ?? '';
    final imageUrl = item['image_url'];

    bool isCorrect = false;
    IconData icon;
    Color color;
    
    if (userAns == null) {
      icon = Icons.help_outline;
      color = Colors.grey;
    } else if (userAns == correctAns) {
      icon = Icons.check_circle;
      color = Colors.green;
      isCorrect = true;
    } else {
      icon = Icons.cancel;
      color = Colors.red;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Question Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${index + 1}. $questionText',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Image
            if (imageUrl != null && (imageUrl as String).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    imageUrl,
                    height: 120,
                    fit: BoxFit.contain,
                    errorBuilder: (ctx, err, stack) => const SizedBox(),
                  ),
                ),
              ),

            // Answers
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '你的: ${_answerText(userAns)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: userAns == correctAns ? Colors.green : Colors.red,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '正确: ${_answerText(correctAns)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                  ),
                ],
              ),
            ),
            
            // Translation & Explanation
            if (_showTranslation && translation.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildCollapsible(
                '翻译',
                translation,
                _translationExpanded[index] ?? false,
                (val) => setState(() => _translationExpanded[index] = val),
              ),
            ],

            if (_showExplanation && explanation.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildCollapsible(
                '解析',
                explanation,
                _explanationExpanded[index] ?? false,
                (val) => setState(() => _explanationExpanded[index] = val),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCollapsible(String title, String content, bool isExpanded, Function(bool) onChanged) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => onChanged(!isExpanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 13)),
                  const Spacer(),
                  Icon(isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 20, color: Colors.grey),
                ],
              ),
            ),
          ),
          if (isExpanded)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text(
                content,
                style: const TextStyle(color: Colors.black87, height: 1.4, fontSize: 14),
              ),
            ),
        ],
      ),
    );
  }
}