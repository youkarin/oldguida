import 'package:flutter/material.dart';
import 'General/profile_screen.dart';

// Services
import 'package:italian_driving_app/Services/auth_service.dart';
import 'package:italian_driving_app/database/database_helper.dart';

// Banner 轮播组件
import '../Banner/Banner.dart';

// General Screens
import 'General/question_bank_screen.dart';
import 'General/exam_screen.dart';
import 'General/wrong_review_screen.dart';
import 'General/study_record_screen.dart';
import 'General/vip_upgrade_screen.dart';
import 'General/settings_screen.dart';
import 'General/practice_screen.dart';
import 'General/favorites_screen.dart';
import 'General/Navigation_Bar/NavigationBar.dart';

// VIP Screens
import 'VIP/must_correct_screen.dart';
import 'VIP/must_wrong_screen.dart';
import 'VIP/difficult_screen.dart';
import 'VIP/examVIP_screen.dart';

/// 主页面：带底部导航的首页
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  bool _isLoggedIn = false;
  bool _isVip = false;
  int _vipDays = 0;

  @override
  void initState() {
    super.initState();
    _checkVipStatus();
  }

  Future<void> _checkVipStatus() async {
    final loggedIn = await AuthService().isLoggedIn();
    final vip = loggedIn ? await AuthService().getVipDays() : 0;
    setState(() {
      _isLoggedIn = loggedIn;
      _isVip = vip > 0;
      _vipDays = vip;
    });
  }

  // ✅ 通用功能
  final List<MenuItem> generalItems = [
    // PNG 图标示例（需要在 pubspec.yaml 注册）
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

  ];

  // 🌟 VIP 功能
  final List<MenuItem> vipItems = [
      //学习记录-按钮
      MenuItem(
      icon: Image.asset(
        'assets/images/icons/time-past.png',
        width: 32,
        height: 32,
      ),
      label: '学习记录',
      color: Colors.indigo,
      ),

      //收藏夹-按钮
      MenuItem(
      icon: Image.asset(
        'assets/images/icons/wishlist-star.png',
        width: 32,
        height: 32,
      ),
      label: '收藏夹',
      color: Colors.amber,
    ),

      //单词必对题-按钮
      MenuItem(
      icon: Image.asset(
        'assets/images/icons/check-circle.png',
        width: 32,
        height: 32,
      ),
      label: '单词必对题',
      color: Colors.green,
      ),

      //单词必错题-按钮
      MenuItem(
      icon: Image.asset(
        'assets/images/icons/cross-circle.png',
        width: 32,
        height: 32,
      ),
      label: '单词必错题',
      color: Colors.red,
      ),

      //错题复习-按钮
         MenuItem(
      icon: Image.asset(
        'assets/images/icons/guide-book.png',
        width: 32,
        height: 32,
      ),
      label: '错题复习',
      color: Colors.redAccent,
    ),

      //单词易错题-按钮
      MenuItem(
      icon: Image.asset(
        'assets/images/icons/not-found-magnifying-glass.png',
        width: 32,
        height: 32,
      ),
      label: '易错题',
      color: Colors.red,
      ),

      //EXAM-按钮
      MenuItem(
      icon: Image.asset(
        'assets/images/icons/test.png',
        width: 32,
        height: 32,
      ),
      label: 'EXAM',
      color: Colors.blueAccent,
      ),

    // 个人信息-按钮
      // MenuItem(
      // icon: Image.asset(
      //   'assets/images/icons/user.png',
      //   width: 32,
      //   height: 32,
      // ),
      // label: '个人信息',
      // color: Colors.brown,
      // ),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildHomeContent(),
      _buildVipContent(),
      _buildNewsContent(),
      const ProfileScreen(),
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
    if (index == 1) {
      _checkVipStatus();
    }
  }

  void _handleVipButton() async {
    await _checkVipStatus();
    if (!_isLoggedIn) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先登录')));
      return;
    }
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.workspace_premium,
                  color: Colors.amber, size: 48),
              const SizedBox(height: 12),
              Text(
                _isVip ? '尊贵的VIP用户' : '升级为VIP',
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _isVip
                    ? '剩余天数：$_vipDays'
                    : '解锁收藏夹、错题复习等专属功能',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'),
                  ),
                  if (!_isVip) ...[
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _navigateToScreen(context, '转为VIP');
                      },
                      child: const Text('去升级'),
                    ),
                  ]
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  // 首页内容：Banner + 通用功能
  Widget _buildHomeContent() {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Italian Driving App', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _navigateToScreen(context, '设置'),
          ),
          IconButton(
            icon: const Icon(Icons.workspace_premium, color: Colors.amber),
            tooltip: 'VIP',
            onPressed: _handleVipButton,
          ),
        ],
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
            _buildGrid(context, generalItems, 3),
          ],
        ),
      ),
    );
  }

  // VIP 页面内容
  Widget _buildVipContent() {
    if (!_isLoggedIn) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('VIP 功能'),
          centerTitle: true,
        ),
        body: const Center(child: Text('请先登录')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('VIP 功能'),
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
          padding: const EdgeInsets.only(top: 16),
          children: [
            _buildGrid(context, vipItems, 3, requireVip: true),
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
  Widget _buildGrid(BuildContext context, List<MenuItem> items, int crossAxisCount,
      {bool requireVip = false}) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12, top: 10, bottom: 8),
      child: GridView.count(
        crossAxisCount: crossAxisCount,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 0.85,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        padding: EdgeInsets.zero,
        children: items.map((item) {
          return Card(
            margin: const EdgeInsets.all(2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            elevation: 4,
            shadowColor: item.color.withOpacity(0.2),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                if (requireVip && !_isVip) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('请成为VIP后使用此功能')),
                  );
                } else {
                  _navigateToScreen(context, item.label);
                }
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 圆形渐变图标背景
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [item.color.withOpacity(0.8), item.color.withOpacity(0.5)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    // IconTheme 只会影响 Icon，不会影响 Image.asset
                    child: IconTheme.merge(
                      data: const IconThemeData(color: Colors.white, size: 32),
                      child: item.icon,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.blueGrey[900],
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // 统一导航
  void _navigateToScreen(BuildContext context, String screenName) {
    final screen = _getScreenByName(screenName);
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
  Widget? _getScreenByName(String screenName) {
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
      case '收藏夹':
        return const FavoritesScreen();
      case '转为VIP':
        return VipUpgradeScreen();
      case '设置':
        return const SettingsScreen();

      // VIP功能
      case '单词必对题':
        return MustCorrectScreen();
      case '单词必错题':
        return MustWrongScreen();
      case '易错题':
        return DifficultScreen();
      case 'EXAM':
        return ExamVIPScreen();
      case '个人信息':
        return ProfileScreen();

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
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('知道了')),
        ],
      ),
    );
  }
}

class MenuItem {
  final Widget icon;   // 兼容 Image.asset 与 Icon
  final String label;
  final Color color;
  MenuItem({required this.icon, required this.label, required this.color});
}
