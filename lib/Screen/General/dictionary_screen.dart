import 'dart:async';

import 'package:flutter/material.dart';

import '../../Services/keyword_repository.dart';
import '../../models/keyword_model.dart';
import 'dictionary_detail_screen.dart';

class DictionaryScreen extends StatefulWidget {
  const DictionaryScreen({super.key, this.repository});

  final KeywordRepository? repository;

  @override
  State<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends State<DictionaryScreen> {
  final TextEditingController _searchController = TextEditingController();
  late final KeywordRepository _repository =
      widget.repository ?? KeywordRepository();

  Timer? _debounce;
  List<Keyword> _entries = const [];
  Object? _error;
  var _isLoading = false;
  var _hasSearchText = false;
  var _requestId = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_search(''));
  }

  void _onSearchChanged(String value) {
    final hasSearchText = value.isNotEmpty;
    if (hasSearchText != _hasSearchText) {
      setState(() => _hasSearchText = hasSearchText);
    }
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      unawaited(_search(''));
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 200),
      () => unawaited(_search(value)),
    );
  }

  void _onSubmitted(String value) {
    _debounce?.cancel();
    unawaited(_search(value));
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    if (_hasSearchText) {
      setState(() => _hasSearchText = false);
    }
    unawaited(_search(''));
  }

  Future<void> _search(String value) async {
    final requestId = ++_requestId;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final entries = await _repository.search(value.trim());
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _entries = entries;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _entries = const [];
        _error = error;
        _isLoading = false;
      });
    }
  }

  void _openEntry(Keyword entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DictionaryDetailScreen(
          keywordId: entry.id,
          repository: _repository,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _requestId++;
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('驾考词典')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: SearchBar(
              controller: _searchController,
              hintText: '搜索意大利语或中文',
              textInputAction: TextInputAction.search,
              leading: const Tooltip(
                message: '搜索词典',
                child: Icon(Icons.search),
              ),
              trailing: [
                if (_hasSearchText)
                  IconButton(
                    tooltip: '清除搜索',
                    onPressed: _clearSearch,
                    icon: const Icon(Icons.clear),
                  ),
              ],
              onChanged: _onSearchChanged,
              onSubmitted: _onSubmitted,
            ),
          ),
          SizedBox(
            height: 3,
            child: _isLoading ? const LinearProgressIndicator() : null,
          ),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_error != null) {
      return _MessageState(
        icon: Icons.error_outline,
        message: '词典加载失败',
        action: FilledButton.icon(
          onPressed: () => unawaited(_search(_searchController.text)),
          icon: const Icon(Icons.refresh),
          label: const Text('重试'),
        ),
      );
    }
    if (_isLoading && _entries.isEmpty) {
      return const Center(child: Text('正在加载词典...'));
    }
    if (_entries.isEmpty) {
      return const _MessageState(
        icon: Icons.search_off,
        message: '未找到相关词条',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: _entries.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = _entries[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 6,
          ),
          title: Text(
            entry.term,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Text(entry.partOfSpeech),
              const SizedBox(height: 2),
              Text(
                entry.translation,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openEntry(entry),
        );
      },
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(message, style: Theme.of(context).textTheme.titleMedium),
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
