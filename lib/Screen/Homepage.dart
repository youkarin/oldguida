import 'package:flutter/material.dart';

// Services
import 'package:italian_driving_app/database/database_helper.dart';
import 'package:italian_driving_app/Services/update_service.dart';

// Banner 轮播组件
import '../Banner/Banner.dart';

// General Screens
import 'General/question_bank_screen.dart';
import 'General/exam_screen.dart';
import 'General/wrong_review_screen.dart';
import 'General/study_record_screen.dart';
import 'General/settings_screen.dart';
import 'General/practice_screen.dart';
import 'General/favorites_screen.dart';
import 'General/Navigation_Bar/NavigationBar.dart';
import 'General/dictionary_screen.dart';

// VIP Screens (Now General/Advanced)
import 'VIP/must_correct_screen.dart';
import 'VIP/must_wrong_screen.dart';
import 'VIP/difficult_screen.dart';
import 'VIP/examVIP_screen.dart';

/// 主页面：带底部导航的首页
class HomePage extends StatefulWidget {
  const HomePage({super.key, this.dictionaryScreenBuilder});

  final WidgetBuilder? dictionaryScreenBuilder;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    // 延迟一秒检查更新，避免刚进入页面时弹窗冲突
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        UpdateService.checkUpdate(context);
      }
    });
  }

  // ✅ 通用功能
  final List<MenuItem> generalItems = [
    MenuItem(
      icon: Image.asset(
        'assets/images/icons/steering-wheel.png',
        width: 32,
        height: 32,
      ),
      label: '开始做题',
      color: Colors.orange,
    ),
    MenuItem(
      icon: Image.asset(
        'assets/images/icons/book-open-cover.png',
        width: 32,
        height: 32,
      ),
      label: '全题库',
      color: Colors.pink,
    ),
    MenuItem(
      icon: Image.asset(
        'assets/images/icons/to-do-alt.png',
        width: 32,
        height: 32,
      ),
      label: '选择练习',
      color: Colors.teal,
    ),
    MenuItem(
      icon: const Icon(Icons.translate),
      label: '驾考词典',
      color: Colors.blue,
    ),
  ];

  // 🌟 记录/高级功能 (原 VIP 功能)
  final List<MenuItem> recordItems = [
    MenuItem(
      icon: Image.asset(
        'assets/images/icons/time-past.png',
        width: 32,
        height: 32,
      ),
      label: '学习记录',
      color: Colors.indigo,
    ),
    MenuItem(
      icon: Image.asset(
        'assets/images/icons/wishlist-star.png',
        width: 32,
        height: 32,
      ),
      label: '收藏夹',
      color: Colors.amber,
    ),
    MenuItem(
      icon: Image.asset(
        'assets/images/icons/check-circle.png',
        width: 32,
        height: 32,
      ),
      label: '单词必对题',
      color: Colors.green,
    ),
    MenuItem(
      icon: Image.asset(
        'assets/images/icons/cross-circle.png',
        width: 32,
        height: 32,
      ),
      label: '单词必错题',
      color: Colors.red,
    ),
    MenuItem(
      icon: Image.asset(
        'assets/images/icons/guide-book.png',
        width: 32,
        height: 32,
      ),
      label: '错题复习',
      color: Colors.redAccent,
    ),
    MenuItem(
      icon: Image.asset(
        'assets/images/icons/not-found-magnifying-glass.png',
        width: 32,
        height: 32,
      ),
      label: '易错题',
      color: Colors.red,
    ),
    MenuItem(
      icon: Image.asset(
        'assets/images/icons/test.png',
        width: 32,
        height: 32,
      ),
      label: 'EXAM',
      color: Colors.blueAccent,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildHomeContent(),
      _buildRecordContent(),
      _buildNewsContent(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: pages,
      ),
      bottomNavigationBar: AppNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onNavTap,
      ),
    );
  }

  void _onNavTap(int index) {
    setState(() => _selectedIndex = index);
  }

  // 首页内容：Banner + 通用功能
  Widget _buildHomeContent() {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('OldGuida',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF2F2F7), Color(0xFFE5E5EA)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.only(top: kToolbarHeight + 8, bottom: 0),
          children: [
            _buildSectionTitle('推荐内容'),
            SizedBox(
              height: 200,
              child: TopBanner(),
            ),
            _buildSectionTitle('通用功能'),
            _buildGrid(
              context,
              generalItems,
              2,
              wideCrossAxisCount: 4,
            ),
          ],
        ),
      ),
    );
  }

  // 记录页面内容 (原 VIP)
  Widget _buildRecordContent() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('记录与进阶'),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF2F2F7), Color(0xFFE5E5EA)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.only(top: 16),
          children: [
            _buildGrid(context, recordItems, 3),
          ],
        ),
      ),
    );
  }

  // 新闻占位页面
  Widget _buildNewsContent() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('新闻'),
        centerTitle: true,
      ),
      body: const Center(
        child: Text('新闻内容正在开发中'),
      ),
    );
  }

  // 构建章节标题
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4, left: 20, right: 20),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.blueGrey[700],
          fontSize: 18,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  // 通用的网格构建
  Widget _buildGrid(
    BuildContext context,
    List<MenuItem> items,
    int crossAxisCount, {
    int? wideCrossAxisCount,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12, top: 10, bottom: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final resolvedCrossAxisCount =
              wideCrossAxisCount != null && constraints.maxWidth >= 720
                  ? wideCrossAxisCount
                  : crossAxisCount;
          return GridView.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: resolvedCrossAxisCount,
              mainAxisExtent: 150,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                margin: const EdgeInsets.all(2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                elevation: 4,
                shadowColor: item.color.withOpacity(0.2),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () {
                    _navigateToScreen(context, item.label);
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              item.color.withOpacity(0.8),
                              item.color.withOpacity(0.5),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: IconTheme.merge(
                          data: const IconThemeData(
                            color: Colors.white,
                            size: 32,
                          ),
                          child: item.icon,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          item.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.blueGrey[900],
                          ),
                        ),
                      ),
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

  // 统一导航
  void _navigateToScreen(BuildContext context, String screenName) {
    final screen = _getScreenByName(context, screenName);
    if (screen != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => screen,
          settings: RouteSettings(name: screenName),
        ),
      );
    } else {
      _showDevelopmentDialog(context, screenName);
    }
  }

  // 名称 → 页面映射
  Widget? _getScreenByName(BuildContext context, String screenName) {
    switch (screenName) {
      // 通用功能
      case '开始做题':
        return const ExamScreen();
      case '全题库':
        return QuestionBankScreen();
      case '错题复习':
        return WrongReviewScreen();
      case '学习记录':
        return StudyRecordScreen();
      case '选择练习':
        return const PracticeScreen();
      case '驾考词典':
        return widget.dictionaryScreenBuilder?.call(context) ??
            const DictionaryScreen();
      case '收藏夹':
        return const FavoritesScreen();
      case '设置':
        return const SettingsScreen();

      // 原 VIP 功能 (现已开放)
      case '单词必对题':
        return MustCorrectScreen();
      case '单词必错题':
        return MustWrongScreen();
      case '易错题':
        return DifficultScreen();
      case 'EXAM':
        return ExamVIPScreen();

      default:
        return null;
    }
  }

  // 开发中弹窗
  void _showDevelopmentDialog(BuildContext context, String screenName) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Row(
          children: const [
            Icon(Icons.construction, color: Colors.orange),
            SizedBox(width: 8),
            Text('开发中'),
          ],
        ),
        content: Text('$screenName 功能正在开发中，敬请期待！'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了')),
        ],
      ),
    );
  }
}

class MenuItem {
  final Widget icon; // 兼容 Image.asset 与 Icon
  final String label;
  final Color color;
  MenuItem({required this.icon, required this.label, required this.color});
}
