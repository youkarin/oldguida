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
  Timer? _timer; 
  int _remainingSeconds = 30 * 60; 
  int? _userId;
  bool _hasVip = false;
  bool _isFavorite = false;
  bool _isTimerPaused = false; // New state for time stop

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

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isTimerPaused && _remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else if (_remainingSeconds <= 0) {
        timer.cancel();
        _finishExam();
      }
    });
  }

  void _toggleTimer() {
    setState(() {
      _isTimerPaused = !_isTimerPaused;
    });
  }

  void _submitAnswer(bool answer) {
    if (userAnswers[currentIndex] != null && !widget.immediateFeedback) return;
    
    final isCorrect = widget.questions[currentIndex].answer == (answer ? 1 : 0);
    setState(() {
      userAnswers[currentIndex] = answer ? 1 : 0;
      answerResults[currentIndex] = isCorrect;
    });

    if (widget.immediateFeedback) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (currentIndex < widget.questions.length - 1) {
          _nextQuestion();
        }
      });
    }
  }

  void _nextQuestion() {
    if (currentIndex < widget.questions.length - 1) {
      setState(() {
        currentIndex++;
      });
      _resetVisibility();
      _updateFavoriteStatus();
    }
  }

  void _prevQuestion() {
    if (currentIndex > 0) {
      setState(() {
        currentIndex--;
      });
      _resetVisibility();
      _updateFavoriteStatus();
    }
  }

  void _goToQuestion(int index) {
    setState(() {
      currentIndex = index;
    });
    _resetVisibility();
    _updateFavoriteStatus();
  }

  // ... (keep _toggleFavorite, _finishExam, _loadUser, _updateFavoriteStatus, _resetVisibility as they are or with slight logic adjustments)

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Widget _buildQuestionNavigator() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: widget.questions.length,
        itemBuilder: (context, index) {
          final isSelected = index == currentIndex;
          final answer = userAnswers[index];
          final result = answerResults[index];
          
          Color borderColor = Colors.grey.shade300;
          Color bgColor = Colors.transparent;
          Color textColor = Colors.black87;

          if (isSelected) {
            borderColor = const Color(0xFF1A237E);
            bgColor = const Color(0xFF1A237E).withOpacity(0.1);
            textColor = const Color(0xFF1A237E);
          } else if (answer != null) {
            if (widget.immediateFeedback) {
              bgColor = result == true ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1);
              borderColor = result == true ? Colors.green : Colors.red;
            } else {
              bgColor = Colors.blueGrey.withOpacity(0.1);
              borderColor = Colors.blueGrey;
            }
          }

          return GestureDetector(
            onTap: () => _goToQuestion(index),
            child: Container(
              width: 44,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 2),
                color: bgColor,
              ),
              alignment: Alignment.center,
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: textColor,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAnswerButton(bool value, String text, Color color) {
    final selectedAnswer = userAnswers[currentIndex];
    final isSelected = selectedAnswer == (value ? 1 : 0);
    
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: InkWell(
          onTap: () => _submitAnswer(value),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? color : Colors.grey.shade300,
                width: 2,
              ),
              color: isSelected ? color.withOpacity(0.1) : Colors.white,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  value ? Icons.check_circle_outline : Icons.highlight_off,
                  color: isSelected ? color : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? color : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final question = widget.questions[currentIndex];
    final answered = userAnswers[currentIndex] != null;
    final result = answerResults[currentIndex];
    final progress = userAnswers.where((a) => a != null).length / widget.questions.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          widget.isRandom ? '随机练习' : '顺序练习',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined, size: 18, color: Colors.white),
                const SizedBox(width: 4),
                Text(
                  _formatTime(_remainingSeconds),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(_isTimerPaused ? Icons.play_arrow : Icons.pause_circle_outline),
            onPressed: _toggleTimer,
            tooltip: _isTimerPaused ? '恢复计时' : '停止计时',
          ),
          TextButton(
            onPressed: _finishExam,
            child: const Text('交卷', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )
        ],
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            backgroundColor: Colors.grey.shade200,
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF1A237E)),
          ),
          _buildQuestionNavigator(),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            'Q${currentIndex + 1}: ${question.question}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2D3436),
                              height: 1.4,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            _isFavorite ? Icons.bookmark : Icons.bookmark_border,
                            color: const Color(0xFF1A237E),
                          ),
                          onPressed: _toggleFavorite,
                        )
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (question.imageUrl != null && question.imageUrl!.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade100),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.asset(
                            '${question.imageUrl!}',
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const SizedBox(),
                          ),
                        ),
                      ),
                    if (widget.immediateFeedback && answered)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: result == true ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              result == true ? Icons.check_circle : Icons.cancel,
                              color: result == true ? Colors.green : Colors.red,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              result == true ? '正确答案！' : '回答错误',
                              style: TextStyle(
                                color: result == true ? Colors.green[700] : Colors.red[700],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    // Toggleable Translation
                    if (widget.showTranslation && question.translation.isNotEmpty)
                      _buildCollapsibleSection(
                        title: '翻译 (Translation)',
                        content: question.translation,
                        isExpanded: _showTranslationContent,
                        onToggle: () => setState(() => _showTranslationContent = !_showTranslationContent),
                      ),
                    
                    // Toggleable Explanation
                    if (widget.showExplanation && question.explanation.isNotEmpty)
                      _buildCollapsibleSection(
                        title: '解析 (Explanation)',
                        content: question.explanation,
                        isExpanded: _showExplanationContent,
                        onToggle: () => setState(() => _showExplanationContent = !_showExplanationContent),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Row(
              children: [
                _buildAnswerButton(true, 'Vero', Colors.green),
                _buildAnswerButton(false, 'Falso', Colors.red),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton.icon(
                  onPressed: currentIndex > 0 ? _prevQuestion : null,
                  icon: const Icon(Icons.arrow_back_ios, size: 16),
                  label: const Text('上一题'),
                ),
                TextButton.icon(
                  onPressed: currentIndex < widget.questions.length - 1 ? _nextQuestion : null,
                  icon: const Icon(Icons.arrow_forward_ios, size: 16),
                  label: const Text('下一题'),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildCollapsibleSection({
    required String title,
    required String content,
    required bool isExpanded,
    required VoidCallback onToggle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                  const Spacer(),
                  Icon(isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.blueGrey),
                ],
              ),
            ),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text(content, style: const TextStyle(height: 1.5, color: Colors.black87)),
            ),
        ],
      ),
    );
  }
}
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
