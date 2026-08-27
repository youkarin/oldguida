import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:italian_driving_app/Services/keyword_translation_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

/// App-wide settings page.
///
/// Stores user preferences such as whether to display
/// translations/explanations or show immediate feedback during quizzes.
///
/// These values are persisted using [SharedPreferences] so that
/// they can later be synced with a remote user profile or database.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.keywordTranslationSettings,
  });

  final KeywordTranslationSettings? keywordTranslationSettings;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final KeywordTranslationSettings _keywordTranslationSettings;
  bool _showTranslation = true;
  bool _showExplanation = true;
  bool _immediateFeedback = false;
  bool _stayOnWrongAnswer = false;
  bool _debugMode = false;
  bool _collapsedMode = false;
  bool _experiencePreview = false;
  String _version = '';
  String _buildNumber = '';

  @override
  void initState() {
    super.initState();
    _keywordTranslationSettings = widget.keywordTranslationSettings ??
        KeywordTranslationSettings.instance;
    _loadSettings();
    _loadVersion();
  }

  /// Loads persisted settings. Defaults are provided for first-time runs.
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _showTranslation = prefs.getBool('showTranslation') ?? true;
      _showExplanation = prefs.getBool('showExplanation') ?? true;
      _immediateFeedback = prefs.getBool('immediateFeedback') ?? false;
      _stayOnWrongAnswer = prefs.getBool('stayOnWrongAnswer') ?? false;
      _debugMode = prefs.getBool('debugMode') ?? false;
      _collapsedMode = prefs.getBool('collapsedMode') ?? false;
      _experiencePreview = prefs.getBool('experiencePreview') ?? false;
    });
  }

  Future<void> _loadVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _version = packageInfo.version;
      _buildNumber = packageInfo.buildNumber;
    });
  }

  /// Updates the "show translation" preference and persists it.
  Future<void> _updateShowTranslation(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showTranslation', value);
    setState(() {
      _showTranslation = value;
    });
  }

  /// Updates the "show explanation" preference and persists it.
  Future<void> _updateShowExplanation(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showExplanation', value);
    setState(() {
      _showExplanation = value;
    });
  }

  /// Updates the "immediate feedback" preference and persists it.
  Future<void> _updateImmediateFeedback(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('immediateFeedback', value);
    setState(() {
      _immediateFeedback = value;
    });
  }

  Future<void> _updateStayOnWrongAnswer(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('stayOnWrongAnswer', value);
    if (!mounted) return;
    setState(() => _stayOnWrongAnswer = value);
  }

  Future<void> _updateKeywordTranslation(bool value) async {
    try {
      await _keywordTranslationSettings.setEnabled(value);
    } catch (_) {
      // The settings notifier has already restored the persisted value.
    }
  }

  /// Updates the "debug" preference and persists it.
  Future<void> _updateDebugMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('debugMode', value);
    setState(() {
      _debugMode = value;
    });
  }

  /// Updates the "collapsed mode" preference and persists it.
  Future<void> _updateCollapsedMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('collapsedMode', value);
    setState(() {
      _collapsedMode = value;
    });
  }

  /// Updates the "experience preview" preference and persists it.
  Future<void> _updateExperiencePreview(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('experiencePreview', value);
    setState(() {
      _experiencePreview = value;
    });
  }

  Future<void> _checkForUpdates() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在检查更新...')),
    );

    try {
      final String apiUrl;
      if (_experiencePreview) {
        // Fetch list of releases (including pre-releases) if preview is enabled
        apiUrl =
            'https://api.github.com/repos/youkarin/Oldguida_release/releases?per_page=1';
      } else {
        // Fetch only the latest stable release
        apiUrl =
            'https://api.github.com/repos/youkarin/Oldguida_release/releases/latest';
      }

      print('Checking updates from: $apiUrl');

      final response = await http.get(Uri.parse(apiUrl));

      if (response.statusCode == 200) {
        final dynamic releaseData;
        if (_experiencePreview) {
          // response body is a list
          final List<dynamic> releases = json.decode(response.body);
          if (releases.isEmpty) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('未找到任何发布版本')),
              );
            }
            return;
          }
          releaseData = releases[0];
        } else {
          // response body is a single object
          releaseData = json.decode(response.body);
        }

        final String latestVersionTag = releaseData['tag_name'];
        final String htmlUrl = releaseData['html_url'];
        final String body = releaseData['body'] ?? '';

        // Try to find the direct APK download URL in assets
        String downloadUrl = htmlUrl; // Fallback to htmlUrl
        if (releaseData['assets'] != null &&
            (releaseData['assets'] as List).isNotEmpty) {
          final assets = releaseData['assets'] as List;
          final apkAsset = assets.firstWhere(
            (asset) => asset['name'].toString().endsWith('.apk'),
            orElse: () => null,
          );
          if (apkAsset != null) {
            downloadUrl = apkAsset['browser_download_url'];
          }
        }

        // Expected Tag Format: v1.0.0+42 OR v1.0.0
        // Parse the tag to extract version and build number
        String cleanTag =
            latestVersionTag.replaceAll('v', ''); // 1.0.0+42 or 1.0.0-pre.42
        String latestVersionPart = '';
        String latestBuildPart = '0';

        if (cleanTag.contains('+')) {
          final parts = cleanTag.split('+');
          latestVersionPart = parts[0];
          latestBuildPart = parts[1];
        } else if (cleanTag.contains('-pre.')) {
          // Handle our pre-release format: v1.0.0-pre.42
          final parts = cleanTag.split('-pre.');
          latestVersionPart = parts[0];
          latestBuildPart = parts[1];
        } else {
          latestVersionPart = cleanTag;
        }

        // Check if new version is actually newer
        if (_isNewer(latestVersionPart, latestBuildPart)) {
          _showUpdateDialog(latestVersionTag, downloadUrl, body);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('当前已是最新版本')),
            );
          }
        }
      } else {
        print('Update check failed. Status: ${response.statusCode}');
        print('Response body: ${response.body}');
        if (mounted) {
          String errorMsg = '检查更新失败: ${response.statusCode}';
          if (response.statusCode == 404) {
            errorMsg += ' (未找到发布版本或仓库不存在)';
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errorMsg)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('检查更新出错: $e')),
        );
      }
    }
  }

  bool _isNewer(String latestVersionPart, String latestBuildPart) {
    // 1. Compare Version (e.g. 1.0.0 vs 1.0.1)
    if (_compareVersions(latestVersionPart, _version) > 0) {
      return true;
    }

    // 2. If Version is equal, compare Build Number (e.g. 42 vs 41)
    if (_compareVersions(latestVersionPart, _version) == 0) {
      int latestBuild = int.tryParse(latestBuildPart) ?? 0;
      int currentBuild = int.tryParse(_buildNumber) ?? 0;
      if (latestBuild > currentBuild) {
        return true;
      }
    }

    return false;
  }

  int _compareVersions(String v1, String v2) {
    try {
      List<String> parts1 = v1.split('.');
      List<String> parts2 = v2.split('.');

      for (int i = 0; i < parts1.length && i < parts2.length; i++) {
        int p1 = int.tryParse(parts1[i]) ?? 0;
        int p2 = int.tryParse(parts2[i]) ?? 0;
        if (p1 > p2) return 1;
        if (p1 < p2) return -1;
      }

      if (parts1.length > parts2.length) return 1;
      if (parts1.length < parts2.length) return -1;

      return 0;
    } catch (e) {
      return v1.compareTo(v2);
    }
  }

  void _showUpdateDialog(String version, String url, String description) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('发现新版本 $version'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('更新内容：'),
              const SizedBox(height: 8),
              Text(description),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('稍后'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _launchUrl(url);
            },
            child: const Text('立即更新'),
          ),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开更新链接')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('显示翻译'),
            value: _showTranslation,
            onChanged: _updateShowTranslation,
          ),
          SwitchListTile(
            title: const Text('显示解析'),
            value: _showExplanation,
            onChanged: _updateShowExplanation,
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _keywordTranslationSettings.enabled,
            builder: (context, enabled, child) => SwitchListTile(
              title: const Text('题目关键词翻译'),
              subtitle: const Text('在意大利语题目中划线显示可点击词条'),
              value: enabled,
              onChanged: (value) {
                unawaited(_updateKeywordTranslation(value));
              },
            ),
          ),
          SwitchListTile(
            title: const Text('立即提示正误'),
            value: _immediateFeedback,
            onChanged: _updateImmediateFeedback,
          ),
          if (_immediateFeedback)
            SwitchListTile(
              title: const Text('错题自动停留'),
              subtitle: const Text('答错后停留在当前题，手动点击下一题继续'),
              value: _stayOnWrongAnswer,
              onChanged: _updateStayOnWrongAnswer,
            ),
          SwitchListTile(
            title: const Text('Debug 模式'),
            value: _debugMode,
            onChanged: _updateDebugMode,
          ),
          SwitchListTile(
            title: const Text('默认折叠翻译与解析'),
            subtitle: const Text('开启后，翻译和解析默认隐藏，需手动展开'),
            value: _collapsedMode,
            onChanged: _updateCollapsedMode,
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('体验预览版'),
            subtitle: const Text('包括尚未稳定的新功能'),
            value: _experiencePreview,
            onChanged: _updateExperiencePreview,
          ),
          ListTile(
            leading: const Icon(Icons.system_update),
            title: const Text('检查更新'),
            subtitle: Text('当前版本: $_version ($_buildNumber)'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: _checkForUpdates,
          ),
          // TODO: Add more settings such as language, notifications, etc.
        ],
      ),
    );
  }
}
