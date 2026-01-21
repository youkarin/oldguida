import 'package:flutter/material.dart';
import '../../database/database_helper.dart';
import 'question_list_screen.dart';

class QuestionBankScreen extends StatefulWidget {
  const QuestionBankScreen({Key? key}) : super(key: key);

  @override
  State<QuestionBankScreen> createState() => _QuestionBankScreenState();
}

class _QuestionBankScreenState extends State<QuestionBankScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  late Future<List<Map<String, dynamic>>> _chapterList;
  late Map<int, Future<List<Map<String, dynamic>>>> _sectionFutures;

  @override
  void initState() {
    super.initState();
    _chapterList = _dbHelper.getChapters();
    _sectionFutures = {};
  }

  Future<List<Map<String, dynamic>>> _getSections(int chapterId) {
    _sectionFutures[chapterId] ??= _dbHelper.getSections(chapterId);
    return _sectionFutures[chapterId]!;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('全题库 - Question Bank'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _chapterList,
        builder: (context, chapterSnapshot) {
          if (chapterSnapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (chapterSnapshot.hasError) {
            return Center(child: Text('加载失败: ${chapterSnapshot.error}'));
          }
          final chapters = chapterSnapshot.data ?? [];
          if (chapters.isEmpty) {
            return const Center(child: Text('暂无题库数据'));
          }

          return ListView.builder(
            itemCount: chapters.length,
            itemBuilder: (context, index) {
              final chapter = chapters[index];
              final chapterId = chapter['chapter_id'] as int;
              final chapterName = chapter['name'] as String;
              return ExpansionTile(
                title: Text('第$chapterId章 $chapterName'),
                children: [
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _getSections(chapterId),
                    builder: (context, sectionSnapshot) {
                      if (sectionSnapshot.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final sections = sectionSnapshot.data ?? [];
                      if (sections.isEmpty) {
                        return const ListTile(title: Text('暂无小节'));
                      }
                      return Column(
                        children: sections.map((section) {
                          final sectionId = section['section_id'] as int;
                          final sectionName = section['name'] as String;
                          return ListTile(
                            title: Text('第$sectionId节 $sectionName'),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => QuestionListScreen(
                                    sectionId: sectionId,
                                    sectionName: sectionName,
                                  ),
                                ),
                              );
                            },
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
