import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  static const String owner = 'youkarin';
  static const String repo = 'oldguida';
  static const String apiUrl = 'https://api.github.com/repos/$owner/$repo/releases/latest';

  /// 检测更新
  static Future<void> checkUpdate(BuildContext context, {bool showNoUpdate = false}) async {
    try {
      final response = await http.get(Uri.parse(apiUrl));
      if (response.statusCode != 200) {
        if (showNoUpdate) {
          _showSnackBar(context, '无法获取更新信息');
        }
        return;
      }

      final data = json.decode(response.body);
      final String latestVersion = data['tag_name']?.replaceAll('v', '') ?? '';
      final String releaseNotes = data['body'] ?? '暂无更新说明';
      final String downloadUrl = data['html_url'] ?? 'https://github.com/$owner/$repo/releases';

      final packageInfo = await PackageInfo.fromPlatform();
      final String currentVersion = packageInfo.version;

      if (_isNewer(latestVersion, currentVersion)) {
        if (context.mounted) {
          _showUpdateDialog(context, latestVersion, currentVersion, releaseNotes, downloadUrl);
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

  /// 版本对比
  static bool _isNewer(String latest, String current) {
    if (latest.isEmpty) return false;
    List<int> latestParts = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    List<int> currentParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < latestParts.length; i++) {
      int cur = i < currentParts.length ? currentParts[i] : 0;
      if (latestParts[i] > cur) return true;
      if (latestParts[i] < cur) return false;
    }
    return false;
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
