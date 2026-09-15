# OldGuida

这是一个帮助华人用户备考意大利驾照理论考试的 Flutter 移动应用。

## 许可与使用范围

Copyright (c) 2025 youkarin。当前版本采用自定义的 [免费使用与禁止销售、收费运营许可](LICENSE)，不是 MIT 或 OSI 定义的开源许可。

- 允许免费学习、使用、研究、修改与分享；分享时保留署名和许可，修改版注明改动。
- 未经作者另行书面授权，禁止出售、付费下载、订阅/会员收费运营，以及将本项目或其功能捆绑在收费产品、服务或课程中提供。
- 许可仅涵盖作者有权授权的代码及原创数据部分。网络图片、外部原题和第三方依赖适用各自权利与许可；图片来源及授权尚需核实，不能因本仓库公开而认定可自由分发。
- 以前按 MIT 等许可合法取得的历史版本授权不被追溯撤销。

完整条款以 `LICENSE` 为准。此自定义文本尚未经专业法律审查。

## 简介

该项目旨在提供一个全面的题库练习和复习工具，帮助用户通过意大利驾照考试。

## 主要功能

### 1. 题库练习
- **随机做题 (`ExamScreen`)**: 随时进行题目练习。
- **全题库 (`QuestionBankScreen`)**: 浏览和学习所有题目。
- **选择练习 (`PracticeScreen`)**: 按分类或章节练习。

### 2. 复习与强化
- **错题复习 (`WrongReviewScreen`)**: 自动记录错题，方便针对性复习。

- **收藏夹 (`FavoritesScreen`)**: 用户可以收藏重点或疑难题目。
- **学习记录 (`StudyRecordScreen`)**: 追踪学习进度和历史成绩。

### 3. 学习辅助
- **多语言支持**: 针对华人用户优化，设置中支持开启/关闭中文翻译和题目解析。
- **即时反馈**: 可设置做题时立即显示正误。
- **离线驾考词典**: 词条、词形、中文搜索及题干关键词释义。

## 技术架构

- **前端**: 基于 [Flutter](https://flutter.dev) 框架开发，支持 Android 和 iOS。
- **数据存储**:
    - 本地使用 **SQLite** (`sqflite`) 存储题库 (`assets/db/quiz.db`)。
    - 收藏、错题、学习历史仅保存在本机，不需要注册、登录或会员。
    - 卸载或清除应用数据可能丢失记录；不提供云备份。
    - 单一本地模式，无账号或数据集选择器。保留旧记录和有效明确归属；归属歧义或旧选择失效时，为新记录创建独立、持久的本地归属，不合并或清空旧数据。其他历史归属/孤立记录可能不可见，详见 [本地数据兼容说明](docs/local-only.md)。
- **更新机制**: 内置版本更新检查功能（对接 GitHub Releases），支持“体验预览版”更新。

## 开发

### 环境要求
- 使用满足 `pubspec.lock` SDK 下限的 Flutter / Dart 工具链。
- 当前本地化改动尚未通过 SDK 解析；锁文件保留原样，需在具备 SDK 和依赖缓存的环境运行 `flutter pub get --offline` 生成真实锁文件后再验证。

### 运行
```bash
flutter pub get
flutter run
```

### 测试
```bash
flutter test
```

### 手动构建 macOS（Apple Silicon）

新增工作流 `.github/workflows/build_macos.yml` 仅接受 `workflow_dispatch`，不会因 push、PR 或定时任务自动运行，也不会创建 GitHub Release、发布到其他仓库或提交锁文件。

1. 由维护者自行审核并将所需代码及工作流提交、推送到 GitHub；工作流需出现在默认分支，Actions 页面才会显示手动运行入口。**云端 checkout 只取得所选远端分支的提交，不包含这台电脑尚未提交或推送的本地化改动。** 请核对运行详情与产物 `build-metadata.json` 中的 commit。
2. 打开仓库 **Actions → Build macOS (manual) → Run workflow**，选择已审核的分支并手动运行。需要仓库运行工作流的权限；私有仓库可能消耗 Actions 分钟和存储配额。
3. 只有真实依赖解析、`flutter test --no-pub`、Release 构建、包结构/架构/签名/校验和检查及上传全部成功后，才可在该次运行页面 **Artifacts** 下载 `OldGuida-macos-arm64-<run_id>-<run_attempt>`（保留 14 天）。解开 Actions 外层压缩包，可得应用 ZIP、`SHA256SUMS`、实际生成的 `pubspec.lock`、构建元数据、工具链与签名记录及原样 `LICENSE`。
4. 在下载内容所在目录运行 `shasum -a 256 -c SHA256SUMS`；通过后，用 macOS 归档实用工具或 `ditto -x -k OldGuida-macos-arm64.zip <目标目录>` 解开内层 ZIP，保留完整 `.app` 结构及执行权限。不要直接分发拆散的 `.app` 内容。

工作流只在 GitHub 的 `macos-15` ARM64 runner 安装官方 **Flutter 3.47.1 / Dart 3.13.1**，校验固定 SDK SHA-256 与 revision；Actions 固定完整提交 SHA。通过该版本正式提供的 `--enable-macos-arm64-only` 配置构建，检查主程序仅含 ARM64、所有随包 Mach-O 均支持 ARM64并记录实际架构；**不宣称 Universal，也不支持 Intel Mac**。项目最低 macOS 版本为 12.0，与固定 Flutter SDK 的最低部署版本一致；实际包声明记录在元数据中。原生 SQLite 由真实依赖解析及构建 hooks 处理，不伪造锁文件。沙盒 Release 保留出站网络权限，以支持现有 GitHub 更新检查；此打包流程不会向更新仓库发布内容。

**安全与验证边界：** 此为自行测试用的 ad-hoc 签名包，没有 Developer ID 签名、没有 Apple notarization，不需要 Apple ID、证书、密码或其他用户凭据。工作流会验证现有 ad-hoc 签名，但这不等于 Apple 认可其来源；Gatekeeper 仍可能阻止打开。只使用自己审核过的源码及对应成功运行的产物；SHA-256 只能检测文件是否变化，不能证明可信或无恶意。不要全局关闭 Gatekeeper、删除系统安全设置或盲目绕过告警。首次测试前自行备份已有学习数据；下载和打开应用不是自动完成的，也不代表已验证真实旧库升级或 UI 行为。分发仍须遵守上方许可与第三方素材权利限制。

本次仅完成工作流静态验证，未触发云端构建，也未在本机安装 Flutter、解析依赖或运行 Flutter 测试；首次手动运行仍可能暴露依赖、插件或 Xcode 构建问题，失败时不会上传成功包。
