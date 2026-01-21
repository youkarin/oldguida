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
  final Map<int, Future<List<Map<String, dynamic>>>> _sectionFutures = {};

  @override
  void initState() {
    super.initState();
    _chapterList = _dbHelper.getChapters();
  }

  Future<List<Map<String, dynamic>>> _getSections(int chapterId) {
    return _sectionFutures.putIfAbsent(chapterId, () => _dbHelper.getSections(chapterId));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7), // iOS style background
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        title: const Text(
          '全题库',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 20),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _chapterList,
        builder: (context, chapterSnapshot) {
          if (chapterSnapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (chapterSnapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text('加载失败: ${chapterSnapshot.error}'),
                ],
              ),
            );
          }
          final chapters = chapterSnapshot.data ?? [];
          if (chapters.isEmpty) {
            return const Center(
              child: Text(
                '暂无题库数据',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: chapters.length,
            itemBuilder: (context, index) {
              final chapter = chapters[index];
              return _buildChapterCard(chapter);
            },
          );
        },
      ),
    );
  }

  Widget _buildChapterCard(Map<String, dynamic> chapter) {
    final chapterId = chapter['chapter_id'] as int;
    final chapterName = chapter['name'] as String;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          backgroundColor: Colors.white,
          collapsedBackgroundColor: Colors.white,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$chapterId',
              style: TextStyle(
                color: Colors.blue.shade700,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          title: Text(
            chapterName,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.black87,
              height: 1.3,
            ),
          ),
          children: [
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _getSections(chapterId),
              builder: (context, sectionSnapshot) {
                if (sectionSnapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                }
                final sections = sectionSnapshot.data ?? [];
                if (sections.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('暂无小节', style: TextStyle(color: Colors.grey)),
                  );
                }
                return Column(
                  children: sections.map((section) => _buildSectionItem(section)).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionItem(Map<String, dynamic> section) {
    final sectionId = section['section_id'] as int;
    final sectionName = section['name'] as String;

    return InkWell(
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
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          border: Border(
            top: BorderSide(color: Colors.grey.shade200, width: 0.5),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: Icon(
                Icons.subdirectory_arrow_right,
                size: 18,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '第 $sectionId 节',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sectionName,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.black87,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 20,
              color: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}