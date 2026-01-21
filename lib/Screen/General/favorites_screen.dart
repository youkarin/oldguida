import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:italian_driving_app/database/database_helper.dart';
import 'package:italian_driving_app/Services/auth_service.dart';
import 'package:italian_driving_app/Services/sync_service.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({Key? key}) : super(key: key);

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final List<Map<String, dynamic>> _favoriteQuestions = [];
  int? _userId;
  bool _isLoading = true;

  // Settings
  bool _showTranslation = true;
  bool _showExplanation = true;
  bool _collapsedMode = false;

  // Expansion state
  final Map<String, bool> _translationExpanded = {};
  final Map<String, bool> _explanationExpanded = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final showTrans = prefs.getBool('showTranslation') ?? true;
    final showExpl = prefs.getBool('showExplanation') ?? true;
    final collapsed = prefs.getBool('collapsedMode') ?? false;

    _userId = await AuthService().ensureLocalUser();
    
    if (_userId != null) {
      final favs = await DatabaseHelper.instance.getFavoriteQuestions(_userId!);
      if (mounted) {
        setState(() {
          _showTranslation = showTrans;
          _showExplanation = showExpl;
          _collapsedMode = collapsed;
          
          _favoriteQuestions.clear();
          _favoriteQuestions.addAll(favs);
          
          // Initialize expansion states
          for (var item in favs) {
            final key = '${item['section_id']}-${item['question_number']}';
            _translationExpanded[key] = !collapsed;
            _explanationExpanded[key] = !collapsed;
          }
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _removeFavorite(int index) async {
    if (_userId == null) return;
    
    final item = _favoriteQuestions[index];
    final sectionId = item['section_id'];
    final questionNum = item['question_number'];

    // Optimistic UI update
    final removedItem = item;
    setState(() {
      _favoriteQuestions.removeAt(index);
    });

    final success = await DatabaseHelper.instance.removeFavorite(
        _userId!, sectionId, questionNum);

    if (success) {
      await SyncService.syncFavoriteChange(_userId!, sectionId, questionNum, false);
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已取消收藏')),
        );
      }
    } else {
      // Revert if failed
      if (mounted) {
        setState(() {
          _favoriteQuestions.insert(index, removedItem);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('操作失败，请重试')),
        );
      }
    }
  }

  String _answerText(int? value) {
    if (value == null) return '未知';
    return value == 1 ? 'Vero (正确)' : 'Falso (错误)';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('收藏夹'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _favoriteQuestions.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _favoriteQuestions.length,
                  itemBuilder: (context, index) {
                    return _buildFavoriteCard(index);
                  },
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bookmark_border, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            '暂无收藏题目',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            '在做题时点击右上角的书签图标即可收藏',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoriteCard(int index) {
    final item = _favoriteQuestions[index];
    final key = '${item['section_id']}-${item['question_number']}';
    final questionText = item['question'];
    final translation = item['translation'] ?? '';
    final explanation = item['explanation'] ?? '';
    final imageUrl = item['image_url'];
    final answer = item['answer']; // 1 or 0

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with Bookmark Button
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '${index + 1}. $questionText',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.bookmark, color: Colors.amber),
                  onPressed: () => _removeFavorite(index),
                  tooltip: '取消收藏',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
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

            // Answer Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: answer == 1 ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: answer == 1 ? Colors.green.withOpacity(0.5) : Colors.red.withOpacity(0.5),
                ),
              ),
              child: Text(
                '答案: ${_answerText(answer)}',
                style: TextStyle(
                  color: answer == 1 ? Colors.green[700] : Colors.red[700],
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            
            // Translation & Explanation
            if (_showTranslation && translation.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildCollapsible(
                '翻译',
                translation,
                _translationExpanded[key] ?? false,
                (val) => setState(() => _translationExpanded[key] = val),
              ),
            ],

            if (_showExplanation && explanation.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildCollapsible(
                '解析',
                explanation,
                _explanationExpanded[key] ?? false,
                (val) => setState(() => _explanationExpanded[key] = val),
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
