import 'dart:async';


import 'package:flutter/material.dart';
import 'package:italian_driving_app/Services/keyword_translation_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';


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

  bool _collapsedMode = false;
  bool _experiencePreview = false;


  @override
  void initState() {
    super.initState();
    _keywordTranslationSettings = widget.keywordTranslationSettings ??
        KeywordTranslationSettings.instance;
    _loadSettings();

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

      _collapsedMode = prefs.getBool('collapsedMode') ?? false;
      _experiencePreview = prefs.getBool('experiencePreview') ?? false;
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


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        children: [
          const _SettingsSectionHeader('答题显示'),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
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
            title: const Text('默认折叠翻译与解析'),
            subtitle: const Text('开启后，翻译和解析默认隐藏，需手动展开'),
            value: _collapsedMode,
            onChanged: _updateCollapsedMode,
          ),
          const _SettingsSectionHeader('实验功能'),
          SwitchListTile(
            title: const Text('体验预览版'),
            subtitle: const Text('包括尚未稳定的新功能'),
            value: _experiencePreview,
            onChanged: _updateExperiencePreview,
          ),
          // TODO: Add more settings such as language, notifications, etc.
        ],
      ),
    );
  }
}

class _SettingsSectionHeader extends StatelessWidget {
  const _SettingsSectionHeader(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
      );
}
