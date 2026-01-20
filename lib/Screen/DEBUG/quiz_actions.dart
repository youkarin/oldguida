import 'package:flutter/material.dart';
import 'package:italian_driving_app/database/database_helper.dart';

class QuizActionsPage extends StatefulWidget {
  const QuizActionsPage({Key? key}) : super(key: key);

  @override
  _QuizActionsPageState createState() => _QuizActionsPageState();
}

class _QuizActionsPageState extends State<QuizActionsPage> {
  late Future<List<Map<String, dynamic>>> _chapterMaps;

  @override
  void initState() {
    super.initState();
    _chapterMaps = DatabaseHelper.instance.getChapters();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('题目集')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _chapterMaps,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final chapters = snapshot.data ?? [];
          if (chapters.isEmpty) {
            return const Center(child: Text('暂无章节'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: chapters.length,
            itemBuilder: (context, index) {
              final ch = chapters[index];
              final chId = ch['chapter_id'] as int;
              final chName = ch['name'] as String;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: SizedBox(
                  height: 60,
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SubsectionPage(chapterId: chId, chapterName: chName),
                        ),
                      );
                    },
                    child: Text("第${chId}章 ${chName}"),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class SubsectionPage extends StatefulWidget {
  final int chapterId;
  final String chapterName;
  const SubsectionPage({Key? key, required this.chapterId, required this.chapterName}) : super(key: key);

  @override
  _SubsectionPageState createState() => _SubsectionPageState();
}

class _SubsectionPageState extends State<SubsectionPage> {
  late Future<List<Map<String, dynamic>>> _sectionMaps;

  @override
  void initState() {
    super.initState();
    _sectionMaps = DatabaseHelper.instance.getSections(widget.chapterId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("第${widget.chapterId}章 ${widget.chapterName} - 小节")),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _sectionMaps,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final subs = snapshot.data ?? [];
          if (subs.isEmpty) {
            return const Center(child: Text('暂无小节'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: subs.length,
            itemBuilder: (context, index) {
              final sub = subs[index];
              final subId = sub['section_id'] as int;
              final subName = sub['name'] as String;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: SizedBox(
                  height: 50,
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => QuestionPage(
                          sectionId: subId,
                          sectionName: subName,
                        ),
                      ),
                    ),
                    child: Text("小节${subId} - $subName"),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class QuestionPage extends StatefulWidget {
  final int sectionId;
  final String sectionName;
  const QuestionPage({Key? key, required this.sectionId, required this.sectionName}) : super(key: key);

  @override
  _QuestionPageState createState() => _QuestionPageState();
}

class _QuestionPageState extends State<QuestionPage> {
  late Future<List<Map<String, dynamic>>> _qList;

  @override
  void initState() {
    super.initState();
    // 用 join 查询带出 section_image
    _qList = DatabaseHelper.instance.getQuestionsWithSectionImage(widget.sectionId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("小节${widget.sectionId} - ${widget.sectionName}")),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _qList,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snapshot.data ?? [];
          if (list.isEmpty) {
            return const Center(child: Text('暂无题目'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemCount: list.length,
            itemBuilder: (context, index) {
              final item = list[index];
              final ok = (item['answer'] is int ? item['answer'] : int.tryParse(item['answer'].toString()) ?? 0) == 1;
              final sectionImg = item['section_image'] as String?;
              return Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${index + 1}. Q: ${item['question']}",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (item['translation'] != null) ...[
                        const SizedBox(height: 6),
                        Text("翻译: ${item['translation']}"),
                      ],
                      if (item['explanation'] != null) ...[
                        const SizedBox(height: 6),
                        Text("解析: ${item['explanation']}"),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Text('结果:'),
                          const SizedBox(width: 4),
                          Icon(
                            ok ? Icons.check_circle : Icons.cancel,
                            color: ok ? Colors.green : Colors.red,
                          ),
                        ],
                      ),
                      if (sectionImg != null && sectionImg.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Image.asset(
                          sectionImg.startsWith('assets/')
                              ? sectionImg
                              : 'assets/images/section/$sectionImg',
                          fit: BoxFit.contain,
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
