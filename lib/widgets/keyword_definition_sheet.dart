import 'package:flutter/material.dart';

import '../models/keyword_model.dart';

Future<int?> showKeywordDefinitionSheet(
  BuildContext context,
  Keyword keyword, {
  String? matchedForm,
  ValueChanged<int>? onViewFullEntry,
}) async {
  final selectedKeywordId = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => SafeArea(
      child: Semantics(
        container: true,
        namesRoute: true,
        label: '关键词释义',
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            20,
            24,
            24 + MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                matchedForm ?? keyword.term,
                style: Theme.of(sheetContext).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                '词条：${keyword.term}',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text('词性：${keyword.partOfSpeech}'),
              const SizedBox(height: 16),
              Text(
                keyword.translation,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              if (keyword.note.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(keyword.note),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(sheetContext).pop(keyword.id),
                  icon: const Icon(Icons.menu_book_outlined),
                  label: const Text('查看完整词条'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  if (selectedKeywordId != null) {
    onViewFullEntry?.call(selectedKeywordId);
  }
  return selectedKeywordId;
}
