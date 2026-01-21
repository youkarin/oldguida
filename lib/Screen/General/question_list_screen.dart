import 'package:flutter/material.dart';
import '../../database/database_helper.dart';
import '../../models/question_model.dart';

class QuestionListScreen extends StatefulWidget {
  final int sectionId;
  final String sectionName;

  const QuestionListScreen({
    Key? key,
    required this.sectionId,
    required this.sectionName,
  }) : super(key: key);

  @override
  State<QuestionListScreen> createState() => _QuestionListScreenState();
}

class _QuestionListScreenState extends State<QuestionListScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  late Future<List<Question>> _questionsFuture;

  @override
  void initState() {
    super.initState();
    _questionsFuture = _loadQuestions();
  }

  Future<List<Question>> _loadQuestions() async {
    final raw = await _dbHelper.getQuestionsWithSectionImage(widget.sectionId);
    return raw.map((m) => Question.fromMap(m)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(widget.sectionName),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: FutureBuilder<List<Question>>(
        future: _questionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('加载出错: ${snapshot.error}'));
          }
          final questions = snapshot.data ?? [];
          if (questions.isEmpty) {
            return const Center(child: Text('本节暂无题目'));
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: questions.length,
            itemBuilder: (context, index) {
              return QuestionFlashcard(
                question: questions[index],
                index: index + 1,
              );
            },
          );
        },
      ),
    );
  }
}

class QuestionFlashcard extends StatefulWidget {
  final Question question;
  final int index;

  const QuestionFlashcard({
    Key? key,
    required this.question,
    required this.index,
  }) : super(key: key);

  @override
  State<QuestionFlashcard> createState() => _QuestionFlashcardState();
}

class _QuestionFlashcardState extends State<QuestionFlashcard> {
  bool _showDetails = true; // 默认展示详情以便学习

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final isTrue = q.answer == 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部题号和答案标识
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: isTrue ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '题目 ${widget.index}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isTrue ? Colors.green[700] : Colors.red[700],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: isTrue ? Colors.green : Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isTrue ? 'VERO' : 'FALSO',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 意大利语原文
                Text(
                  q.question,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2D3436),
                    height: 1.4,
                  ),
                ),
                
                const SizedBox(height: 16),

                // 图片 (如果有)
                if ((q.sectionImage != null && q.sectionImage!.isNotEmpty) || (q.imageUrl != null && q.imageUrl!.isNotEmpty))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 400),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            (q.sectionImage != null && q.sectionImage!.isNotEmpty) ? q.sectionImage! : q.imageUrl!,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              String path = (q.sectionImage != null && q.sectionImage!.isNotEmpty) ? q.sectionImage! : q.imageUrl!;
                              if (!path.startsWith('assets/')) {
                                path = 'assets/$path';
                              }
                              return Image.asset(
                                path,
                                fit: BoxFit.contain,
                                errorBuilder: (c, e, s) => const SizedBox.shrink(),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),

                // 翻译
                if (q.translation.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.blueGrey[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '翻译',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueGrey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          q.translation,
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.blueGrey[800],
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 12),

                // 解析
                if (q.explanation.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.amber[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '解析',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber[900],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          q.explanation,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.amber[950],
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
