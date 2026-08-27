import 'dart:async';

import 'package:flutter/material.dart';

import '../../Services/keyword_repository.dart';
import '../../models/keyword_model.dart';

class DictionaryDetailScreen extends StatefulWidget {
  const DictionaryDetailScreen({
    super.key,
    required this.keywordId,
    this.repository,
  });

  final int keywordId;
  final KeywordRepository? repository;

  @override
  State<DictionaryDetailScreen> createState() => _DictionaryDetailScreenState();
}

class _DictionaryDetailScreenState extends State<DictionaryDetailScreen> {
  late final KeywordRepository _repository =
      widget.repository ?? KeywordRepository();

  Keyword? _keyword;
  List<KeywordForm> _forms = const [];
  KeywordExample? _example;
  Object? _error;
  var _isLoading = true;
  var _requestId = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final requestId = ++_requestId;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object?>([
        _repository.byId(widget.keywordId),
        _repository.forms(),
        _repository.exampleFor(widget.keywordId),
      ]);
      if (!mounted || requestId != _requestId) return;

      final forms = (results[1] as List<KeywordForm>)
          .where((form) => form.keywordId == widget.keywordId)
          .toList(growable: false)
        ..sort(_compareForms);
      setState(() {
        _keyword = results[0] as Keyword?;
        _forms = forms;
        _example = results[2] as KeywordExample?;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }

  static int _compareForms(KeywordForm left, KeywordForm right) {
    final lengthOrder =
        right.normalizedForm.length.compareTo(left.normalizedForm.length);
    if (lengthOrder != 0) return lengthOrder;
    final formOrder = left.normalizedForm.compareTo(right.normalizedForm);
    if (formOrder != 0) return formOrder;
    return left.id.compareTo(right.id);
  }

  @override
  void dispose() {
    _requestId++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('词条详情')),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _DetailMessage(
        icon: Icons.error_outline,
        message: '词条加载失败',
        action: FilledButton.icon(
          onPressed: () => unawaited(_load()),
          icon: const Icon(Icons.refresh),
          label: const Text('重试'),
        ),
      );
    }
    final keyword = _keyword;
    if (keyword == null) {
      return const _DetailMessage(
        icon: Icons.menu_book_outlined,
        message: '未找到该词条',
      );
    }

    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(keyword.term, style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text('词性：${keyword.partOfSpeech}'),
            const SizedBox(height: 20),
            _SectionHeading('中文释义'),
            const SizedBox(height: 8),
            SelectableText(
              keyword.translation,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 20),
            _SectionHeading('说明'),
            const SizedBox(height: 8),
            SelectableText(
              keyword.note.trim().isEmpty ? '暂无补充说明' : keyword.note,
            ),
            const SizedBox(height: 20),
            _SectionHeading('常见词形与搭配'),
            const SizedBox(height: 10),
            if (_forms.isEmpty)
              const Text('暂无词形')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final form in _forms) Chip(label: Text(form.form)),
                ],
              ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),
            _SectionHeading('例句'),
            const SizedBox(height: 10),
            if (_example == null)
              const Text('暂无例句')
            else ...[
              SelectableText(
                _example!.question,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              SelectableText(_example!.translation),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

class _DetailMessage extends StatelessWidget {
  const _DetailMessage({
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
      child: SingleChildScrollView(
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
