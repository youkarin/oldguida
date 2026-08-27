// lib/models/question_model.dart

class Question {
  final int id;
  final int sectionId;
  final int questionNumber;
  final String question;
  final String translation;
  final String explanation;
  final int? answer;
  final String? imageUrl;
  final String? sectionImage; // 新增字段

  Question({
    this.id = 0,
    required this.sectionId,
    required this.questionNumber,
    required this.question,
    required this.translation,
    required this.explanation,
    this.answer,
    this.imageUrl,
    this.sectionImage, // 新增
  });

  factory Question.fromMap(Map<String, dynamic> map) {
    return Question(
      id: map['id'] as int,
      sectionId: map['section_id'] ?? 0,
      questionNumber: map['question_number'] ?? 0,
      question: map['question'] ?? '',
      translation: map['translation'] ?? '',
      explanation: map['explanation'] ?? '',
      answer: map['answer'],
      imageUrl: map['image_url'],
      sectionImage: map['section_image'], // 新增
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'section_id': sectionId,
      'question_number': questionNumber,
      'question': question,
      'translation': translation,
      'explanation': explanation,
      'answer': answer,
      'image_url': imageUrl,
      'section_image': sectionImage, // 新增
    };
  }
}
