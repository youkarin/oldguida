# Italian Driving App

这是一个帮助华人用户备考意大利驾照理论考试的 Flutter 移动应用。

## 简介

该项目旨在提供一个全面的题库练习和复习工具，帮助用户通过意大利驾照考试。

## 主要功能

### 1. 题库练习
- **随机做题 (`ExamScreen`)**: 随时进行题目练习。
- **全题库 (`QuestionBankScreen`)**: 浏览和学习所有题目。
- **选择练习 (`PracticeScreen`)**: 按分类或章节练习。
- **模拟考试 (`ExamVIPScreen`)**: 全真模拟考试环境。

### 2. 复习与强化
- **错题复习 (`WrongReviewScreen`)**: 自动记录错题，方便针对性复习。
- **易错题与必考题**:
    - **易错题 (`DifficultScreen`)**
    - **单词必对题 (`MustCorrectScreen`)**
    - **单词必错题 (`MustWrongScreen`)**
- **收藏夹 (`FavoritesScreen`)**: 用户可以收藏重点或疑难题目。
- **学习记录 (`StudyRecordScreen`)**: 追踪学习进度和历史成绩。

### 3. 学习辅助
- **多语言支持**: 针对华人用户优化，设置中支持开启/关闭中文翻译和题目解析。
- **即时反馈**: 可设置做题时立即显示正误。

## 技术架构

- **前端**: 基于 [Flutter](https://flutter.dev) 框架开发，支持 Android 和 iOS。
- **数据存储**:
    - 本地使用 **SQLite** (`sqflite`) 存储题库 (`assets/db/quiz.db`)。
    - 后端使用 **Supabase** 处理用户认证和数据同步。
- **更新机制**: 内置版本更新检查功能（对接 GitHub Releases），支持“体验预览版”更新。

## 开发

### 环境要求
- Flutter SDK >=3.5.0 <4.0.0
- Dart SDK (随 Flutter 安装)

### 运行
```bash
flutter pub get
flutter run
```

### 测试
```bash
flutter test
```
