import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../Services/keyword_service.dart';
import '../Services/keyword_translation_settings.dart';
import '../models/keyword_model.dart';
import 'keyword_definition_sheet.dart';

class KeywordQuestionText extends StatefulWidget {
  const KeywordQuestionText({
    super.key,
    required this.questionId,
    required this.text,
    this.prefix = '',
    this.style,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.strutStyle,
    this.service,
    this.settings,
    this.onViewFullEntry,
  });

  final int questionId;
  final String text;
  final String prefix;
  final TextStyle? style;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final StrutStyle? strutStyle;
  final KeywordLookup? service;
  final KeywordTranslationSettings? settings;
  final ValueChanged<int>? onViewFullEntry;

  @override
  State<KeywordQuestionText> createState() => _KeywordQuestionTextState();
}

class _KeywordQuestionTextState extends State<KeywordQuestionText> {
  late KeywordLookup _service;
  late KeywordTranslationSettings _settings;
  List<KeywordMatch> _matches = const [];
  List<TapGestureRecognizer> _recognizers = const [];
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? KeywordService.instance;
    _settings = widget.settings ?? KeywordTranslationSettings.instance;
    _settings.enabled.addListener(_handleEnabledChanged);
    unawaited(_refreshMatches());
  }

  @override
  void didUpdateWidget(covariant KeywordQuestionText oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextSettings = widget.settings ?? KeywordTranslationSettings.instance;
    final settingsChanged = !identical(_settings, nextSettings);
    if (settingsChanged) {
      _settings.enabled.removeListener(_handleEnabledChanged);
      _settings = nextSettings;
      _settings.enabled.addListener(_handleEnabledChanged);
    }

    final nextService = widget.service ?? KeywordService.instance;
    final lookupChanged = !identical(_service, nextService);
    if (lookupChanged) {
      _service = nextService;
    }

    if (settingsChanged ||
        lookupChanged ||
        oldWidget.questionId != widget.questionId ||
        oldWidget.text != widget.text) {
      unawaited(_refreshMatches());
    }
  }

  void _handleEnabledChanged() {
    unawaited(_refreshMatches());
  }

  Future<void> _refreshMatches() async {
    final generation = ++_requestGeneration;
    _clearAnnotations();
    if (!_settings.enabled.value || widget.text.isEmpty) {
      return;
    }

    final questionId = widget.questionId;
    final text = widget.text;
    final service = _service;
    try {
      final matches = await service.matchQuestion(
        questionId: questionId,
        text: text,
      );
      if (!mounted ||
          generation != _requestGeneration ||
          !_settings.enabled.value) {
        return;
      }
      _installAnnotations(_validMatches(matches, text));
    } catch (_) {
      // Dictionary failures deliberately preserve the ordinary question text.
    }
  }

  List<KeywordMatch> _validMatches(
    List<KeywordMatch> matches,
    String text,
  ) {
    final sorted = matches
        .where(
          (match) =>
              match.start >= 0 &&
              match.end > match.start &&
              match.end <= text.length,
        )
        .toList(growable: false)
      ..sort((left, right) => left.start.compareTo(right.start));
    final result = <KeywordMatch>[];
    var cursor = 0;
    for (final match in sorted) {
      if (match.start < cursor) continue;
      result.add(match);
      cursor = match.end;
    }
    return result;
  }

  void _installAnnotations(List<KeywordMatch> matches) {
    _disposeRecognizers();
    final recognizers = matches
        .map(
          (match) => TapGestureRecognizer()
            ..onTap = () => unawaited(_openDefinition(match)),
        )
        .toList(growable: false);
    setState(() {
      _matches = matches;
      _recognizers = recognizers;
    });
  }

  void _clearAnnotations() {
    _disposeRecognizers();
    if (_matches.isNotEmpty && mounted) {
      setState(() => _matches = const []);
    } else {
      _matches = const [];
    }
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers = const [];
  }

  Future<void> _openDefinition(KeywordMatch match) async {
    if (!mounted) return;
    final selectedKeywordId = await showKeywordDefinitionSheet(
      context,
      match.keyword,
      matchedForm: match.matchedText,
    );
    if (mounted && selectedKeywordId != null) {
      widget.onViewFullEntry?.call(selectedKeywordId);
    }
  }

  @override
  void dispose() {
    _requestGeneration++;
    _settings.enabled.removeListener(_handleEnabledChanged);
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    if (widget.prefix.isNotEmpty) {
      spans.add(TextSpan(text: widget.prefix));
    }

    var cursor = 0;
    for (var index = 0; index < _matches.length; index++) {
      final match = _matches[index];
      if (match.start > cursor) {
        spans.add(TextSpan(text: widget.text.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: widget.text.substring(match.start, match.end),
          style: const TextStyle(
            decoration: TextDecoration.underline,
            decorationStyle: TextDecorationStyle.dotted,
            decorationColor: Colors.teal,
          ),
          recognizer: _recognizers[index],
        ),
      );
      cursor = match.end;
    }
    if (cursor < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(cursor)));
    }

    return Text.rich(
      TextSpan(children: spans),
      style: widget.style,
      textAlign: widget.textAlign,
      textDirection: widget.textDirection,
      locale: widget.locale,
      softWrap: widget.softWrap,
      overflow: widget.overflow,
      textScaler: widget.textScaler,
      maxLines: widget.maxLines,
      strutStyle: widget.strutStyle,
    );
  }
}
