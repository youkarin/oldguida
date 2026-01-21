import 'package:flutter/material.dart';
import 'package:italian_driving_app/database/database_helper.dart';
import 'package:italian_driving_app/Services/auth_service.dart';
// import 'package:italian_driving_app/Services/sync_service.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({Key? key}) : super(key: key);

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final List<Map<String, dynamic>> _favoriteQuestions = [];
  int? _userId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    _userId = await AuthService().ensureLocalUser();
    print('[FavoritesScreen] userId: $_userId');
    
    if (_userId != null) {
      final favs =
          await DatabaseHelper.instance.getFavoriteQuestions(_userId!);
      setState(() {
        _favoriteQuestions
          ..clear()
          ..addAll(favs);
      });
    } else {
      setState(() {
        _favoriteQuestions.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('收藏夹'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: _favoriteQuestions.isEmpty
          ? const Center(child: Text('暂无收藏'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _favoriteQuestions.length,
              itemBuilder: (context, index) {
                final item = _favoriteQuestions[index];
                return Dismissible(
                  key: ValueKey(
                      '${item['section_id']}-${item['question_number']}'),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) async {
                    if (_userId != null) {
                      await DatabaseHelper.instance.removeFavorite(
                          _userId!, item['section_id'], item['question_number']);
                      // await SyncService.syncFavoriteChange(
                      //     _userId!, item['section_id'], item['question_number'], false);
                    }
                    setState(() {
                      _favoriteQuestions.removeAt(index);
                    });
                  },
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: ListTile(
                      title: Text('${item['question']}'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (item['image_url'] != null &&
                              (item['image_url'] as String).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 8),
                              child: Image.asset(
                                item['image_url'],
                                height: 100,
                                fit: BoxFit.contain,
                              ),
                            ),
                          Text('翻译: ${item['translation'] ?? ''}'),
                          Text('解析: ${item['explanation'] ?? ''}'),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}