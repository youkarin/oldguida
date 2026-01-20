/*import 'package:flutter/material.dart';
import '../../database/database_helper.dart';
import 'exam_screen.dart';
import 'practice_screen.dart';

/// 开始做题页面
///
/// 将原本的“测验”、“练习”和“选题测试”合并到一起，
/// 用户可以在此选择做题模式（计时测验 / 练习）以及题源。
/// 页面示例使用 [DatabaseHelper] 加载章节与节信息，
/// 可根据实际情况替换为自己的数据库或接口。
class StartQuizScreen extends StatefulWidget {
  const StartQuizScreen({Key? key}) : super(key: key);

  @override
  State<StartQuizScreen> createState() => _StartQuizScreenState();
}

class _StartQuizScreenState extends State<StartQuizScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final TextEditingController _countController =
  TextEditingController(text: '10');

  /// 0 代表“测验”模式，1 代表“练习”模式
  int _modeIndex = 0;

  List<int> _chapters = [];
  List<int> _subsections = [];
  int? _selectedChapter;
  int? _selectedSubsection;

  @override
  void initState() {
    super.initState();
    _loadChapters();
  }

  /// 加载所有章节
  Future<void> _loadChapters() async {
    try {
      final chapters = await _dbHelper.getChapters();
      setState(() {
        _chapters = chapters;
      });
    } catch (e) {
      debugPrint('加载章节失败: $e');
    }
  }

  /// 当用户选择章节时，同时加载对应的节
  Future<void> _onChapterChanged(int? chapter) async {
    setState(() {
      _selectedChapter = chapter;
      _selectedSubsection = null;
      _subsections = [];
    });
    if (chapter != null) {
      try {
        final subs = await _dbHelper.getSections(chapter);
        setState(() {
          _subsections = subs;
        });
      } catch (e) {
        debugPrint('加载节失败: $e');
      }
    }
  }

  /// 点击“开始做题”后的处理
  void _startQuiz() {
    // TODO: 根据章节、节和题量获取题目传入下一个页面
    final Widget target = _modeIndex == 0
        ? const ExamScreen()
        : const PracticeScreen();
    debugPrint(
        'mode=$_modeIndex chapter=$_selectedChapter subsection=$_selectedSubsection count=${_countController.text}');
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => target),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('开始做题 - Start Quiz'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ToggleButtons(
              isSelected: [_modeIndex == 0, _modeIndex == 1],
              onPressed: (index) => setState(() => _modeIndex = index),
              borderRadius: BorderRadius.circular(8),
              selectedColor: Colors.white,
              fillColor: Colors.deepPurple,
              children: const [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('测验'),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('练习'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(labelText: '选择章节'),
              items: _chapters
                  .map((c) => DropdownMenuItem(
                value: c,
                child: Text('第$c章'),
              ))
                  .toList(),
              value: _selectedChapter,
              onChanged: _onChapterChanged,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(labelText: '选择节'),
              items: _subsections
                  .map((s) => DropdownMenuItem(
                value: s,
                child: Text('第$s节'),
              ))
                  .toList(),
              value: _selectedSubsection,
              onChanged: (v) => setState(() => _selectedSubsection = v),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _countController,
              decoration: const InputDecoration(
                labelText: '题目数量',
                hintText: '例如：10',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _startQuiz,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                ),
                child: const Text('开始'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _countController.dispose();
    super.dispose();
  }
}

 */