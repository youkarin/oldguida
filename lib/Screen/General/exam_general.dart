import 'dart:async';

import 'package:flutter/material.dart';
import 'package:italian_driving_app/models/question_model.dart';
import 'package:italian_driving_app/database/database_helper.dart';
import 'package:italian_driving_app/Services/auth_service.dart';
import 'package:italian_driving_app/Services/sync_service.dart';
import 'package:italian_driving_app/utils/debug_utils.dart';
import 'final_score.dart';

class ExamGeneral extends StatefulWidget {
  final bool isRandom;
  final List<Question> questions;
  final bool showTranslation;
  final bool showExplanation;
  final bool immediateFeedback;
  final bool collapsedMode;

  const ExamGeneral({
    super.key,
    required this.isRandom,
    required this.questions,
    required this.showTranslation,
    required this.showExplanation,
    required this.immediateFeedback,
    this.collapsedMode = false,
  });

  @override
  State<ExamGeneral> createState() => _ExamGeneralState();
}

class _ExamGeneralState extends State<ExamGeneral> {
  int currentIndex = 0;
  List<int?> userAnswers = [];
  List<bool?> answerResults = [];
  late DateTime startTime;
  Timer? _timer; // 用于30分钟倒计时
  int _remainingSeconds = 30 * 60; // 30分钟 = 1800秒
  int? _userId;
  bool _hasVip = false;
  bool _isFavorite = false;
  
  // Controls the visibility of translation and explanation content
  late bool _showTranslationContent;
  late bool _showExplanationContent;

  @override
  void initState() {
    super.initState();
    _resetVisibility();
    userAnswers = List.filled(widget.questions.length, null);
    answerResults = List.filled(widget.questions.length, null);
    startTime = DateTime.now();
    _startTimer();
    _loadUser();
  }

  void _resetVisibility() {
    setState(() {
      _showTranslationContent = !widget.collapsedMode;
      _showExplanationContent = !widget.collapsedMode;
    });
  }

  /// 启动倒计时，每秒刷新一次，时间到自动提交试卷
  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        timer.cancel();
        _finishExam();
      }
    });
  }

  void _submitAnswer(bool answer) {
    final isCorrect = widget.questions[currentIndex].answer == (answer ? 1 : 0);
    setState(() {
      userAnswers[currentIndex] = answer ? 1 : 0;
      answerResults[currentIndex] = isCorrect;
    });

    if (widget.immediateFeedback) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (currentIndex < widget.questions.length - 1) {
          _nextQuestion();
        }
      });
    } else {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (currentIndex < widget.questions.length - 1) {
          _nextQuestion();
        }
      });
    }
  }

  Future<void> _loadUser() async {
    final vip = await AuthService().getVipDays();
    print('[ExamGeneral] vip days: $vip');
    _hasVip = vip > 0;

    final username = await AuthService().getUsername();
    print('[ExamGeneral] username: $username');
    _userId = await AuthService().ensureLocalUser();
    print('[ExamGeneral] userId: $_userId hasVip: $_hasVip');

    _updateFavoriteStatus();
  }

  Future<void> _updateFavoriteStatus() async {
    if (_userId == null || !_hasVip) {
      print('[ExamGeneral] updateFavoriteStatus blocked userId=$_userId hasVip=$_hasVip');
      setState(() {
        _isFavorite = false;
      });
      return;
    }
    final q = widget.questions[currentIndex];
    final fav = await DatabaseHelper.instance
        .isFavorite(_userId!, q.sectionId, q.questionNumber);
    if (mounted) {
      setState(() {
        _isFavorite = fav;
      });
    }
  }

  void _nextQuestion() {
    setState(() {
      currentIndex++;
    });
    _resetVisibility();
    _updateFavoriteStatus();
  }

  void _goToQuestion(int index) {
    setState(() {
      currentIndex = index;
    });
    _resetVisibility();
    _updateFavoriteStatus();
  }

  Future<void> _toggleFavorite() async {
    print('[ExamGeneral] toggleFavorite userId=$_userId hasVip=$_hasVip');
    if (_userId == null || !_hasVip) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先登录并开通VIP才能使用收藏功能')),
        );
      }
      return;
    }
    final q = widget.questions[currentIndex];
    bool ok;
    if (_isFavorite) {
      ok = await DatabaseHelper.instance
          .removeFavorite(_userId!, q.sectionId, q.questionNumber);
    } else {
      ok = await DatabaseHelper.instance
          .addFavorite(_userId!, q.sectionId, q.questionNumber);
    }
    if (ok) {
      if (mounted) {
        setState(() {
          _isFavorite = !_isFavorite;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_isFavorite ? '已收藏' : '已取消收藏')));
        await SyncService.syncFavoriteChange(
            _userId!, q.sectionId, q.questionNumber, _isFavorite);
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('操作失败，请稍后重试')));
      }
    }
  }

  Future<void> _finishExam() async {
    _timer?.cancel();
    final endTime = DateTime.now();
    final duration = endTime.difference(startTime);
    final correctCount = answerResults.where((r) => r == true).length;
    final wrongCount = answerResults.where((r) => r != true).length;

    try {
      if (_userId != null && _hasVip) {
        final questionMaps =
            widget.questions.map((q) => q.toMap()).toList();
        final historyId = await DatabaseHelper.instance.saveQuizAttempt(
          _userId!,
          questionMaps,
          userAnswers,
          answerResults,
          isRandom: widget.isRandom,
          usedTime: duration.inSeconds,
        );
        await DatabaseHelper.instance.trimQuizHistory(_userId!, 100);
        await SyncService.syncQuizAttempt(historyId);
        unawaited(() async {
          final ok = await SyncService.syncAll();
          await DebugUtils.showSnackBar(
              ok ? '同步完成' : '同步失败',
              isError: !ok);
        }());
      } else {
        print('[ExamGeneral] Not saving history userId=$_userId hasVip=$_hasVip');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('登录并开通VIP后才会记录历史')),
          );
        }
      }
    } catch (e) {
      print('Failed to save quiz data: $e');
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => FinalScorePage(
          duration: duration,
          correctCount: correctCount,
          wrongCount: wrongCount,
          questions: widget.questions,
          userAnswers: userAnswers,
        ),
      ),
    );
  }

  /// 将剩余秒数格式化为 mm:ss 形式
  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Widget _buildQuestionNavigator() {
    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: widget.questions.length,
        itemBuilder: (context, index) {
          final isSelected = index == currentIndex;
          final answer = userAnswers[index];
          final result = answerResults[index];
          Color bgColor;

          if (!widget.immediateFeedback) {
            bgColor = Colors.grey.shade300;
          } else if (answer == null) {
            bgColor = Colors.grey.shade300;
          } else {
            bgColor = result == true ? Colors.green : Colors.red;
          }

          return GestureDetector(
            onTap: () => _goToQuestion(index),
            child: Container(
              width: 40,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? Colors.orange : bgColor,
              ),
              alignment: Alignment.center,
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.black,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );

        },
      ),
    );
  }

  Widget _buildBottomButtons() {
    final selectedAnswer = userAnswers[currentIndex];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        ElevatedButton(
          onPressed: () => _submitAnswer(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: selectedAnswer == 1
                ? Colors.green
                : Colors.grey.shade400,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
          child: const Text('✔️ Vero', style: TextStyle(fontSize: 20)),
        ),
        ElevatedButton(
          onPressed: () => _submitAnswer(false),
          style: ElevatedButton.styleFrom(
            backgroundColor: selectedAnswer == 0
                ? Colors.red
                : Colors.grey.shade400,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
          child: const Text('❌ Falso', style: TextStyle(fontSize: 20)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final question = widget.questions[currentIndex];
    final answered = userAnswers[currentIndex] != null;
    final result = answerResults[currentIndex];

    final progress = userAnswers.where((a) => a != null).length / widget.questions.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isRandom ? '乱序考试' : '顺序考试'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                _formatTime(_remainingSeconds),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          TextButton(
            onPressed: _finishExam,
            child: const Text('交卷', style: TextStyle(color: Colors.white)),
          )
        ],
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: Colors.grey.shade300,
            color: Colors.orange,
          ),
          const SizedBox(height: 8),
          _buildQuestionNavigator(),
          const Divider(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: ListView(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '题目 ${currentIndex + 1}: ${question.question}',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          _isFavorite
                              ? Icons.bookmark
                              : Icons.bookmark_border,
                          color: Colors.orange,
                        ),
                        onPressed: _toggleFavorite,
                      )
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (widget.immediateFeedback && answered)
                    Center(
                      child: Icon(
                        result == true ? Icons.check_circle : Icons.cancel,
                        color: result == true ? Colors.green : Colors.red,
                        size: 36,
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (widget.showTranslation && question.translation.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: () => setState(() => _showTranslationContent = !_showTranslationContent),
                          child: Row(
                            children: [
                              Text(
                                '翻译: ',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey[700],
                                ),
                              ),
                              Icon(
                                _showTranslationContent ? Icons.expand_less : Icons.expand_more,
                                size: 16,
                                color: Colors.blueGrey,
                              ),
                              if (!_showTranslationContent)
                                const Text(' (点击展开)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                        ),
                        if (_showTranslationContent)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
                            child: Text(question.translation),
                          ),
                      ],
                    ),
                  if (widget.showExplanation && question.explanation.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: () => setState(() => _showExplanationContent = !_showExplanationContent),
                          child: Row(
                            children: [
                              Text(
                                '解析: ',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey[700],
                                ),
                              ),
                              Icon(
                                _showExplanationContent ? Icons.expand_less : Icons.expand_more,
                                size: 16,
                                color: Colors.blueGrey,
                              ),
                              if (!_showExplanationContent)
                                const Text(' (点击展开)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                        ),
                        if (_showExplanationContent)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
                            child: Text(question.explanation),
                          ),
                      ],
                    ),
                  if (question.imageUrl != null && question.imageUrl!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Image.asset(
                        '${question.imageUrl!}',
                        errorBuilder: (_, __, ___) => const Text('图片加载失败'),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          _buildBottomButtons(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
