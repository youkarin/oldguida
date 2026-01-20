import 'package:flutter/material.dart';
import 'package:italian_driving_app/Services/auth_service.dart';
import 'package:italian_driving_app/Services/sync_service.dart';
import 'package:italian_driving_app/utils/debug_utils.dart';
import 'login_register_screen.dart';
import 'code_redeem_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool isLoggedIn = false;

  // 用户信息将从数据库加载
  String userName = "";
  String userEmail = "";
  String joinDate = "";

  int totalQuestions = 1250;
  int correctAnswers = 1050;
  int wrongAnswers = 200;
  int studyDays = 45;
  int studyHours = 38;

  bool isVipUser = false;
  String vipExpireDate = "";

  int? _lastSyncAt;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus(); // 检查持久登录
    _loadLastSyncTime();
  }

  Future<void> _checkLoginStatus() async {
    bool loggedIn = await AuthService().isLoggedIn();
    if (loggedIn) {
      String? username = await AuthService().getUsername();
      if (username != null) {
        final profile = await Supabase.instance.client
            .from('profiles')
            .select()
            .eq('username', username)
            .maybeSingle();
        if (profile != null) {
          final rawVipExpire = profile['vip_expire_at'];
          final rawCreatedAt = profile['created_at'];
          int? vipExpire;
          if (rawVipExpire is DateTime) {
            vipExpire = rawVipExpire.millisecondsSinceEpoch;
          } else if (rawVipExpire is int) {
            // convert seconds to milliseconds if needed
            vipExpire =
                rawVipExpire < 1000000000000 ? rawVipExpire * 1000 : rawVipExpire;
          } else if (rawVipExpire is String) {
            vipExpire =
                DateTime.tryParse(rawVipExpire)?.millisecondsSinceEpoch;
          }
          int? createdAt;
          if (rawCreatedAt is DateTime) {
            createdAt = rawCreatedAt.millisecondsSinceEpoch;
          } else if (rawCreatedAt is int) {
            createdAt = rawCreatedAt < 1000000000000
                ? rawCreatedAt * 1000
                : rawCreatedAt;
          } else if (rawCreatedAt is String) {
            createdAt =
                DateTime.tryParse(rawCreatedAt)?.millisecondsSinceEpoch;
          }
          final now = DateTime.now().millisecondsSinceEpoch;
          setState(() {
            isLoggedIn = true;
            userName = profile['username'] ?? "";
            userEmail = profile['email'] ?? "";
            joinDate = createdAt != null
                ? DateTime.fromMillisecondsSinceEpoch(createdAt)
                    .toLocal()
                    .toString()
                    .split(' ')
                    .first
                : "";
            if (vipExpire != null && vipExpire > now) {
              isVipUser = true;
              vipExpireDate = DateTime.fromMillisecondsSinceEpoch(vipExpire)
                  .toLocal()
                  .toString()
                  .split(' ')
                  .first;
            } else {
              isVipUser = false;
              vipExpireDate = "";
            }
          });
        }
      }
    }
  }

  Future<void> _loadLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _lastSyncAt = prefs.getInt('last_sync_at');
    });
  }

  String? get _lastSyncText {
    if (_lastSyncAt == null) return null;
    final dt = DateTime.fromMillisecondsSinceEpoch(_lastSyncAt!).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  // 退出登录时调用 AuthService.logout() 并重置状态
  void _handleLogout() async {
    await AuthService().logout();
    setState(() {
      isLoggedIn = false;
      userName = "";
      userEmail = "";
      joinDate = "";
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已退出登录')),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 如果未登录，显示登录提示
    if (!isLoggedIn) {
      return Scaffold(
        appBar: AppBar(
          title: Text('个人中心'),
          backgroundColor: Color(0xFF667eea),
        ),
        body: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.account_circle, size: 100, color: Colors.grey[400]),
                SizedBox(height: 20),
                Text(
                  '您还没有登录',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  '登录/注册后可保存学习进度、同步错题、参与排行榜、享受更多服务。',
                  style: TextStyle(color: Colors.grey[700], fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 30),
                ElevatedButton.icon(
                  icon: Icon(Icons.login),
                  label: Text('登录 / 注册'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF667eea),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 14, horizontal: 32),
                  ),
                  onPressed: () async {
                    final user = await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => LoginRegisterScreen()),
                    );
                    if (user != null && mounted) {
                      // 登录成功后保存信息并更新页面
                      setState(() {
                        isLoggedIn = true;
                        userName = user['username'] ?? "";
                        userEmail = user['email'] ?? "";
                        // 如有其它字段更新...
                      });
                      await _loadLastSyncTime();
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 已登录状态，生成完整页面（保持原有设计不变）
    double accuracy = ((correctAnswers / totalQuestions) * 100);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // 顶部AppBar
          SliverAppBar(
            expandedHeight: 200,
            floating: false,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(height: isVipUser ? 20 : 40),
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 40,
                          backgroundColor: Colors.white,
                          child: Icon(
                            Icons.person,
                            size: 50,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        userName,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (isVipUser)
                        Container(
                          margin: EdgeInsets.only(top: 8),
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amber,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Text(
                            '👑 VIP用户',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            backgroundColor: Color(0xFF667eea),
            iconTheme: IconThemeData(color: Colors.white),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatsCard(accuracy),
                  SizedBox(height: 20),
                  _buildPersonalInfoCard(),
                  SizedBox(height: 20),
                  _buildVipInfoCard(),
                  SizedBox(height: 20),
                  _buildSettingsCard(),
                  SizedBox(height: 20),
                  _buildActionButtons(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 📈 学习统计卡片
  Widget _buildStatsCard(double accuracy) {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: LinearGradient(
            colors: [Colors.blue[50]!, Colors.indigo[50]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bar_chart, color: Colors.indigo, size: 24),
                SizedBox(width: 8),
                Text(
                  '学习统计',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo[800],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildStatItem('总题数', totalQuestions.toString(), Colors.blue)),
                Expanded(child: _buildStatItem('正确', correctAnswers.toString(), Colors.green)),
                Expanded(child: _buildStatItem('错误', wrongAnswers.toString(), Colors.red)),
              ],
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildStatItem('准确率', '${accuracy.toStringAsFixed(1)}%', Colors.orange)),
                Expanded(child: _buildStatItem('学习天数', '$studyDays天', Colors.purple)),
                Expanded(child: _buildStatItem('学习时长', '${studyHours}小时', Colors.teal)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  // 👤 个人信息卡片
  Widget _buildPersonalInfoCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.person_outline, color: Colors.brown, size: 24),
                SizedBox(width: 8),
                Text(
                  '个人信息',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.brown[800],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            _buildInfoRow(Icons.email_outlined, '邮箱', userEmail),
            _buildInfoRow(Icons.calendar_today_outlined, '注册时间', joinDate),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 👑 VIP信息卡片
  Widget _buildVipInfoCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: isVipUser
              ? LinearGradient(
            colors: [Colors.amber[50]!, Colors.orange[50]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isVipUser ? Icons.workspace_premium : Icons.lock_outline,
                  color: isVipUser ? Colors.amber[700] : Colors.grey[600],
                  size: 24,
                ),
                SizedBox(width: 8),
                Text(
                  isVipUser ? 'VIP会员' : '会员升级',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isVipUser ? Colors.amber[800] : Colors.grey[700],
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            if (isVipUser)
              Text(
                '✅ 您是尊贵的VIP用户\n到期时间：$vipExpireDate',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                  height: 1.5,
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '升级VIP享受更多功能：',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• 易错题专项练习\n• 单词必对/必错题\n• 专属考试模拟\n• 无广告体验',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      height: 1.4,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ⚙️ 设置卡片
  Widget _buildSettingsCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.settings_outlined, color: Colors.indigo, size: 24),
                SizedBox(width: 8),
                Text(
                  '应用设置',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo[800],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            _buildSettingItem(Icons.notifications_outlined, '消息通知', '开启'),
            _buildSettingItem(Icons.language_outlined, '语言设置', '中文/意大利语'),
            _buildSettingItem(Icons.dark_mode_outlined, '深色模式', '关闭'),
            _buildSettingItem(Icons.backup_outlined, '数据备份', '自动备份'),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingItem(IconData icon, String title, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(fontSize: 14),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          Icon(Icons.chevron_right, color: Colors.grey[400]),
        ],
      ),
    );
  }

  // 🔘 操作按钮
  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              _showEditProfileDialog();
            },
            icon: Icon(Icons.edit),
            label: Text('编辑个人信息'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        SizedBox(height: 12),
        if (!isVipUser)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                _showVipUpgradeDialog();
              },
              icon: Icon(Icons.workspace_premium),
              label: Text('升级为VIP'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () async {
              if (!isVipUser) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请成为VIP后使用此功能')),
                );
                return;
              }
              final ok = await SyncService.syncAll();
              await _loadLastSyncTime();
              if (mounted) {
                await DebugUtils.showSnackBar(
                    ok ? '同步完成' : '同步失败',
                    isError: !ok);
              }
            },
            icon: Icon(Icons.sync),
            label: Text('同步数据'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueGrey,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        SizedBox(height: 4),
        Text(
          _lastSyncText != null ? '上次同步: ' + _lastSyncText! : '尚未同步',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CodeRedeemScreen()),
              );
            },
            icon: Icon(Icons.card_giftcard),
            label: Text('兑换激活码'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        SizedBox(height: 12),
        TextButton.icon(
          onPressed: () {
            _showLogoutDialog();
          },
          icon: Icon(Icons.logout, color: Colors.red),
          label: Text(
            '退出登录',
            style: TextStyle(color: Colors.red),
          ),
        ),
      ],
    );
  }

  // 🔄 编辑个人信息对话框
  void _showEditProfileDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('编辑个人信息'),
        content: Text('编辑功能开发中...'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('知道了'),
          ),
        ],
      ),
    );
  }

  // 👑 VIP升级对话框
  void _showVipUpgradeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.workspace_premium, color: Colors.amber),
            SizedBox(width: 8),
            Text('升级VIP'),
          ],
        ),
        content: Text('VIP升级功能开发中...\n即将为您提供更多优质功能！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('稍后升级'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: Text('立即升级'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
          ),
        ],
      ),
    );
  }

  // 🚪 退出登录对话框
  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认退出'),
        content: Text('确定要退出登录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _handleLogout();
            },
            child: Text('确定', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
