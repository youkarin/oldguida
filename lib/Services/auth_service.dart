import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:italian_driving_app/database/database_helper.dart';

class AuthService {
  // 单例模式
  static final AuthService _instance = AuthService._internal();
  AuthService._internal();
  factory AuthService() => _instance;

  /// 保存用户名
  Future<void> login(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', username);
  }

  /// 清除登录状态
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('username');
    await Supabase.instance.client.auth.signOut();
  }

  /// 获取当前是否已登录
  Future<bool> isLoggedIn() async {
    return Supabase.instance.client.auth.currentSession != null;
  }

  /// 获取已保存的用户名
  Future<String?> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('username');
    if (stored != null && stored.isNotEmpty) return stored;
    final user = Supabase.instance.client.auth.currentUser;
    return user?.userMetadata?['username'] as String? ??
        user?.email?.split('@').first;
  }

  /// 确保本地数据库中存在当前用户，返回用户ID
  Future<int?> ensureLocalUser() async {
    String? username = await getUsername();
    if (username == null || username.isEmpty) {
      print('[AuthService] ensureLocalUser: no username, fallback to guest');
      username = 'guest';
    }
    final existing = await DatabaseHelper.instance.getUser(username);
    if (existing != null) {
      return existing[columnUserId] as int?;
    }
    try {
      final session = Supabase.instance.client.auth.currentSession;
      final uuid = session?.user.id;
      final id = await DatabaseHelper.instance
          .addUser(username, '', uuid: uuid);
      print('[AuthService] Created local user id=$id for username=$username');
      return id;
    } catch (e) {
      print('[AuthService] Failed to create local user: $e');
      return null;
    }
  }

  /// 获取剩余VIP天数（基于 Supabase profiles.vip_expire_at）
  Future<int> getVipDays() async {
    final client = Supabase.instance.client;
    final session = client.auth.currentSession;

    // 未登录时直接从本地数据库读取
    if (session == null) {
      final username = await getUsername();
      print('[AuthService] No session, username=$username');
      if (username != null) {
        final local = await DatabaseHelper.instance.getUser(username);
        final days = (local?[columnUserVipDays] as int?) ?? 0;
        print('[AuthService] Returning local VIP days: $days');
        return days;
      }
      print('[AuthService] No local user found, returning 0');
      return 0;
    }

    int? remaining;
    try {
      final user = session.user;
      Map<String, dynamic>? resp;

      // 尝试优先通过 user_id 查询
      resp = await client
          .from('profiles')
          .select('vip_expire_at')
          .eq('user_id', user.id)
          .maybeSingle();
      print('[AuthService] Query by user_id result: $resp');

      // 如果未查到，再通过 username 尝试一次（某些记录可能使用 username 关联）
      if (resp == null || resp.isEmpty) {
        final username = await getUsername();
        print('[AuthService] Fallback query by username: $username');
        if (username != null) {
          resp = await client
              .from('profiles')
              .select('vip_expire_at')
              .eq('username', username)
              .maybeSingle();
          print('[AuthService] Query by username result: $resp');
        }
      }

      final rawExpireAt = resp?['vip_expire_at'];
      print('[AuthService] raw vip_expire_at: $rawExpireAt');
      int? expireAt;
      if (rawExpireAt is DateTime) {
        expireAt = rawExpireAt.millisecondsSinceEpoch;
      } else if (rawExpireAt is int) {
        // Some records store seconds instead of milliseconds
        expireAt =
            rawExpireAt < 1000000000000 ? rawExpireAt * 1000 : rawExpireAt;
      } else if (rawExpireAt is String) {
        expireAt = DateTime.tryParse(rawExpireAt)?.millisecondsSinceEpoch;
      }

      if (expireAt != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        remaining = expireAt > now
            ? ((expireAt - now) / (24 * 3600 * 1000)).ceil()
            : 0;
        print('[AuthService] Calculated remaining days: $remaining');
      } else {
        print('[AuthService] vip_expire_at not found or invalid');
      }
    } catch (e) {
      print('[AuthService] Error while fetching VIP days: $e');
    }

    final username = await getUsername();

    // 远程值存在时更新本地并返回（即使为0也覆盖本地）
    if (remaining != null) {
      if (username != null) {
        final localUser = await DatabaseHelper.instance.getUser(username);
        final userId = localUser?[columnUserId] as int?;
        if (userId != null) {
          await DatabaseHelper.instance.updateVipDays(userId, remaining);
        }
      }
      print('[AuthService] Using remote VIP days: $remaining');
      return remaining;
    }

    // 远程查询失败时回退到本地存储的 VIP 天数
    if (username != null) {
      final local = await DatabaseHelper.instance.getUser(username);
      final localDays = local?[columnUserVipDays] as int?;
      print('[AuthService] Fallback local VIP days: $localDays');
      if (localDays != null) return localDays;
    }

    print('[AuthService] No VIP days found, returning 0');
    return 0;
  }
}
