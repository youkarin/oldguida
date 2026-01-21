import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  static const String owner = 'youkarin';
  // 注意：这里使用的是存储 Release 的仓库名
  static const String repo = 'Oldguida_release';
  
  static String _getApiUrl(bool isPreview) {
    final tag = isPreview ? 'preview' : 'stable';
    return 'https://api.github.com/repos/$owner/$repo/releases/tags/$tag';
  }

  /// 检测更新
  static Future<void> checkUpdate(BuildContext context, {bool showNoUpdate = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool isPreview = prefs.getBool('experiencePreview') ?? false;
      
      final response = await http.get(Uri.parse(_getApiUrl(isPreview)));
      if (response.statusCode != 200) {
        if (showNoUpdate) {
          _showSnackBar(context, '无法获取更新信息 (${response.statusCode})');
        }
        return;
      }

      final data = json.decode(response.body);
      
      // 从描述文本中提取真实的 Tag，因为固定标签 Release 的 tag_name 永远是 'stable' 或 'preview'
      // 我们在 Action 中会把真实版本号写在 Body 的第一行或者使用其他方式
      // 更好的办法是：Action 发布时，把 Release Name 设置为真实版本号
      final String latestVersion = data['name']?.toString().split(' ').last.replaceAll('v', '') ?? '';
      final String releaseNotes = data['body'] ?? '暂无更新说明';
      final String downloadUrl = (data['assets'] as List).isNotEmpty 
          ? data['assets'][0]['browser_download_url'] 
          : data['html_url'];

      final packageInfo = await PackageInfo.fromPlatform();
      final String currentVersion = packageInfo.version;
      final String currentBuildNumber = packageInfo.buildNumber;

      if (_isNewer(latestVersion, '$currentVersion+$currentBuildNumber')) {
        if (context.mounted) {
          _showUpdateDialog(context, latestVersion, '$currentVersion+$currentBuildNumber', releaseNotes, downloadUrl);
        }
      } else {
        if (showNoUpdate && context.mounted) {
          _showSnackBar(context, '当前已是最新版本');
        }
      }
    } catch (e) {
      if (showNoUpdate && context.mounted) {
        _showSnackBar(context, '检查更新出错: $e');
      }
    }
  }

  /// 增强版版本对比
  /// 支持 1.2.3+45 这种格式
  static bool _isNewer(String latest, String current) {
    if (latest.isEmpty) return false;
    
    // 处理带 + 的版本号
    String latestVer = latest.split('+').first;
    int latestBuild = int.tryParse(latest.split('+').last) ?? 0;
    
    String currentVer = current.split('+').first;
    int currentBuild = int.tryParse(current.split('+').last) ?? 0;

    List<int> latestParts = latestVer.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    List<int> currentParts = currentVer.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    // 比较主版本号 (x.y.z)
    int maxLength = latestParts.length > currentParts.length ? latestParts.length : currentParts.length;
    for (int i = 0; i < maxLength; i++) {
      int l = i < latestParts.length ? latestParts[i] : 0;
      int c = i < currentParts.length ? currentParts[i] : 0;
      if (l > c) return true;
      if (l < c) return false;
    }

    // 如果主版本号相同，比较 Build Number
    return latestBuild > currentBuild;
  }

  /// 显示更新对话框
  static void _showUpdateDialog(
    BuildContext context,
    String latest,
    String current,
    String notes,
    String url,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.system_update_alt, color: Colors.blue),
            const SizedBox(width: 10),
            Text('发现新版本 v$latest'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('当前版本: v$current', style: const TextStyle(color: Colors.grey)),
              const Divider(),
              const Text('更新日志:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    notes,
                    style: const TextStyle(fontSize: 14, height: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('稍后'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: const Text('立即更新'),
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    );
  }

  static void _showSnackBar(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
