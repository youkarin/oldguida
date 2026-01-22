import 'package:flutter/material.dart';
import 'package:italian_driving_app/database/database_helper.dart';
import 'package:italian_driving_app/models/question_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'exam_general.dart';

class PracticeScreen extends StatefulWidget {
  final bool isSequential;
  const PracticeScreen({Key? key, this.isSequential = false}) : super(key: key);

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  late Future<List<Map<String, dynamic>>> _chaptersFuture;
  final Set<int> _selectedChapters = {};

  @override
  void initState() {
    super.initState();
    _chaptersFuture = _db.getChapters();
  }

  void _toggleChapter(int id) {
    setState(() {
      if (_selectedChapters.contains(id)) {
        _selectedChapters.remove(id);
      } else {
        _selectedChapters.add(id);
      }
    });
  }

  Future<void> _startTest() async {
    if (_selectedChapters.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请至少选择一个章节')));
      return;
    }
    
    final List<Map<String, dynamic>> rawQuestions;
    if (widget.isSequential) {
      rawQuestions = await _db.getQuestionsByChaptersSequential(
          _selectedChapters.toList());
    } else {
      rawQuestions = await _db.getQuestionsByChaptersRandom(
          _selectedChapters.toList(), 30);
    }
    
    final questions =
        rawQuestions.map((q) => Question.fromMap(q)).toList();

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
          isRandom: !widget.isSequential,
          questions: questions,
          showTranslation: showTranslation,
          showExplanation: showExplanation,
          immediateFeedback: immediateFeedback,
          collapsedMode: collapsedMode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        title: Text(widget.isSequential ? '顺序练习' : '选题练习'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _chaptersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('加载失败: ${snapshot.error}'));
          }
          final chapters = snapshot.data ?? [];
          if (chapters.isEmpty) {
            return const Center(child: Text('暂无章节'));
          }
          return ListView(
            children: chapters.map((c) {
              final id = c['chapter_id'] as int;
              final name = c['name'] as String;
              return CheckboxListTile(
                title: Text('第$id章 $name'),
                value: _selectedChapters.contains(id),
                onChanged: (_) => _toggleChapter(id),
              );
            }).toList(),
          );
        },
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton(
          onPressed: _startTest,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: const Text('去测试'),
        ),
      ),
    );
  }
}



