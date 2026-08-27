# 第 2-25 章中文翻译与解析审校实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 逐题审校第 2 至第 25 章全部 6658 道题，在逐张查看 511 个带图小节的图片后，只将必要的中文翻译和解析修订安全写回数据库。

**Architecture:** 以章节为事务边界，每章先导出只读数据并按小节拆成互不重叠的审校分片。审查者只生成 patch JSON 和图片查看记录；主审合并后检查答案一致性、翻译准确性和图片依据，再运行只读校验、dry-run、单事务写回及与检查点数据库的字段级差异验证。第 2-10 章和第 14 章图片密集，必须完成逐图查看记录后才能写回。

**Tech Stack:** Python 3 标准库（`sqlite3`、`json`、`unittest`）、SQLite CLI、PowerShell、`tools/review/export_chapter.py`、`tools/review/validate_chapter.py`、`tools/review/apply_patch.py`、Codex `view_image`。

---

## 文件职责

- `assets/db/backup/quiz.post-chapter1-pre-remaining.20260826.db`：继续处理前的数据库检查点。
- `tools/review/work/chNN/baseline/chNN_before.json`：第 NN 章写回前完整导出。
- `tools/review/work/chNN/exports/*.json`：互不重叠的只读审校分片。
- `tools/review/work/chNN/image_review_manifest.json`：该章全部带图小节和题目的实际查看记录。
- `tools/review/patches/chNN_*.json`：该章必要修改和严重问题记录。
- `tools/review/revision_log.jsonl`：写回脚本生成的逐题修改审计日志。
- `tools/review/work/chNN/verification.txt`：该章写回前后校验、差异和哈希证据。
- `assets/db/quiz.db`：只允许当前已完成章节的 `translation` 和 `explanation` 发生必要变化。

### Task 1: 建立继续处理前的可恢复检查点

- [ ] 使用 SQLite `.backup` 创建 `assets/db/backup/quiz.post-chapter1-pre-remaining.20260826.db`。
- [ ] 对活动数据库和检查点分别执行 `PRAGMA integrity_check`，预期均输出 `ok`。
- [ ] 比较两者 SHA256，预期创建时完全一致。

### Task 2: 按章节循环执行只读导出与分片审校

- [ ] 对章节 2 至 25 依次运行 `python tools/review/export_chapter.py --chapter NN --out tools/review/work/chNN/baseline/chNN_before.json`。
- [ ] 按题量将每章拆成互不重叠的小节分片，每个分片完整覆盖所含小节的全部题目。
- [ ] 每名审查者遵守 `tools/review/REVIEW_SPEC.md`，逐题比较意大利语题干、固定答案、现有中文翻译和解析。
- [ ] 原翻译或解析准确时不改；只把必要修改写入 `tools/review/patches/chNN_*.json`。
- [ ] 对每个 `image_path` 调用 `view_image`，根据实际形状、颜色、符号和道路布局核对解析，并记录小节 ID 和题目 ID。
- [ ] 对不确定的现行规则只查意大利政府、Normattiva 或主管机构的一手资料，不凭记忆改写。

### Task 3: 对每章补丁做主审和覆盖校验

- [ ] 主审逐项对照写回前导出，删除纯风格改写，确认每处翻译变化都修复真实语义或术语问题。
- [ ] 对 `answer=1` 的修改确认解析论证“正确”，对 `answer=0` 的修改确认解析先判定“错误”并说明错误点。
- [ ] 对全部 severe 项复核题目、固定答案、图片和改后解析；未解决的冲突不得写回。
- [ ] 合并实际查看记录为 `tools/review/work/chNN/image_review_manifest.json`。
- [ ] 运行 `python tools/review/validate_chapter.py --db assets/db/quiz.db --chapter NN --patches "tools/review/patches/chNN_*.json" --image-manifest tools/review/work/chNN/image_review_manifest.json --expect-reviewed COUNT`，预期退出码 0，且 `reviewed=COUNT`、图片数量与数据库一致。

### Task 4: 对每章执行受控写回

- [ ] 运行 `python tools/review/apply_patch.py --dry-run "tools/review/patches/chNN_*.json"`，检查更新数与 patch 条目一致且无章节外 ID。
- [ ] dry-run 通过后运行 `python tools/review/apply_patch.py "tools/review/patches/chNN_*.json"`，由单个主进程写入数据库。
- [ ] 再次运行该章校验器和 `PRAGMA integrity_check`。
- [ ] 将活动数据库与本章写回前导出及总检查点比较，证明题目、答案、ID、小节归属和题号未变，章节外数据未被本次写回改变。
- [ ] 核对活动数据库中的新值与 patch JSON 完全一致，并把证据写入 `tools/review/work/chNN/verification.txt`。

### Task 5: 全部章节完成后的总体验证

- [ ] 确认第 1-25 章合计覆盖 7193 道题，无遗漏、无重复审查 ID。
- [ ] 确认 518 个带图小节、3974 道含图题均有实际查看记录。
- [ ] 与最初备份比较，确认所有 7193 行的 `id`、`question`、`answer`、`section_id`、`question_number` 完全不变。
- [ ] 确认 `chapter`、`section` 表完全不变，`quiz` 表仅 `translation`、`explanation` 发生审校所需变化。
- [ ] 运行 `python tools/review/tests/test_validate_chapter.py -q` 和 `PRAGMA integrity_check`，记录完整输出。
- [ ] 汇总各章 severe 项；普通措辞和术语修正不单独打扰用户。
