# 第 1 章中文翻译与解析审校实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 逐题审校第 1 章全部 535 道题，在核对 7 个带图小节的 33 道题后，仅将必要的中文翻译和解析修订安全写回数据库。

**Architecture:** 先建立只读数据库基线和受保护字段快照，再将 58 个小节拆成 8 个审校分片。每个分片只产出必要修改 JSON；独立校验器检查覆盖率、ID、字段白名单和图片审校清单，随后 dry-run、单事务写回，并与备份数据库逐字段比较。

**Tech Stack:** Python 3 标准库（`sqlite3`、`json`、`unittest`）、SQLite CLI、PowerShell、现有 `tools/review/export_chapter.py` 与 `tools/review/apply_patch.py`、Codex `view_image`。

---

## 文件职责

- `tools/review/validate_chapter.py`：校验审校补丁覆盖率、字段范围、章节 ID 和图片审校清单，不修改数据库。
- `tools/review/tests/test_validate_chapter.py`：用临时 SQLite 数据库覆盖校验器的成功与失败路径。
- `tools/review/work/ch01/baseline/ch01_before.json`：第 1 章写回前完整导出。
- `tools/review/work/ch01/exports/*.json`：8 个只读审校分片。
- `tools/review/work/ch01/image_review_manifest.json`：7 个图片小节和 33 道带图题的实际查看记录。
- `tools/review/patches/ch01_*.json`：每个分片的必要修改与严重问题。
- `tools/review/revision_log.jsonl`：现有写回脚本生成的逐题前后值审计日志。
- `tools/review/work/ch01/verification.txt`：写回前后命令输出与数据库差异结果。
- `assets/db/backup/quiz.chapter1-pre-review.20260826.db`：写回前数据库备份。
- `assets/db/quiz.db`：最终只允许第 1 章的 `translation`、`explanation` 发生必要变化。

### Task 1: 增加只读补丁校验器

**Files:**
- Create: `tools/review/validate_chapter.py`
- Create: `tools/review/tests/test_validate_chapter.py`

- [ ] **Step 1: 编写失败测试**

创建 `tools/review/tests/test_validate_chapter.py`：

```python
import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from validate_chapter import ValidationError, validate


class ValidateChapterTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.db = self.root / "quiz.db"
        con = sqlite3.connect(self.db)
        con.executescript(
            """
            CREATE TABLE section (
              id INTEGER, section_id INTEGER, chapter_id INTEGER,
              name TEXT, image_path TEXT
            );
            CREATE TABLE quiz (
              id INTEGER, question TEXT, answer INTEGER, section_id INTEGER,
              translation TEXT, explanation TEXT, question_number INTEGER
            );
            INSERT INTO section VALUES (1, 1, 1, 'plain', NULL);
            INSERT INTO section VALUES (2, 2, 1, 'image', 'assets/images/quiz/2.gif');
            INSERT INTO quiz VALUES (1, 'q1', 1, 1, 't1', 'e1', 1);
            INSERT INTO quiz VALUES (2, 'q2', 0, 1, 't2', 'e2', 2);
            INSERT INTO quiz VALUES (3, 'q3', 1, 2, 't3', 'e3', 3);
            """
        )
        con.commit()
        con.close()
        self.patch = self.root / "patch.json"
        self.manifest = self.root / "manifest.json"

    def tearDown(self):
        self.tmp.cleanup()

    def write_json(self, path, value):
        path.write_text(json.dumps(value), encoding="utf-8")

    def valid_patch(self):
        return {
            "slice": "test",
            "reviewed": 3,
            "items": [{"id": 3, "explanation": "修正后的解析"}],
            "severe": [],
        }

    def valid_manifest(self):
        return {"chapter": 1, "section_ids": [2], "question_ids": [3]}

    def test_accepts_complete_chapter_review(self):
        self.write_json(self.patch, self.valid_patch())
        self.write_json(self.manifest, self.valid_manifest())
        result = validate(self.db, 1, [self.patch], self.manifest, 3)
        self.assertEqual(result["reviewed"], 3)
        self.assertEqual(result["items"], 1)
        self.assertEqual(result["image_sections"], 1)
        self.assertEqual(result["image_questions"], 1)

    def test_rejects_protected_field(self):
        patch = self.valid_patch()
        patch["items"][0]["answer"] = 0
        self.write_json(self.patch, patch)
        self.write_json(self.manifest, self.valid_manifest())
        with self.assertRaisesRegex(ValidationError, "unsupported item keys"):
            validate(self.db, 1, [self.patch], self.manifest, 3)

    def test_rejects_incomplete_image_manifest(self):
        self.write_json(self.patch, self.valid_patch())
        self.write_json(
            self.manifest,
            {"chapter": 1, "section_ids": [2], "question_ids": []},
        )
        with self.assertRaisesRegex(ValidationError, "image question manifest"):
            validate(self.db, 1, [self.patch], self.manifest, 3)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `python tools/review/tests/test_validate_chapter.py -v`

Expected: FAIL with `ModuleNotFoundError: No module named 'validate_chapter'`.

- [ ] **Step 3: 实现最小校验器**

创建 `tools/review/validate_chapter.py`：

```python
import argparse
import glob
import json
import sqlite3
import sys
from pathlib import Path


class ValidationError(ValueError):
    pass


TOP_KEYS = {"slice", "reviewed", "items", "severe"}
ITEM_KEYS = {"id", "translation", "explanation", "note"}
SEVERE_KEYS = {"id", "type", "detail"}


def read_json(path):
    with Path(path).open(encoding="utf-8") as handle:
        return json.load(handle)


def validate(db_path, chapter, patch_paths, manifest_path, expect_reviewed):
    con = sqlite3.connect(db_path)
    chapter_rows = con.execute(
        """
        SELECT q.id
        FROM quiz q JOIN section s ON s.section_id=q.section_id
        WHERE s.chapter_id=?
        """,
        (chapter,),
    ).fetchall()
    chapter_ids = {row[0] for row in chapter_rows}
    image_sections = {
        row[0]
        for row in con.execute(
            """
            SELECT section_id FROM section
            WHERE chapter_id=? AND image_path IS NOT NULL AND trim(image_path)<>''
            """,
            (chapter,),
        )
    }
    image_question_ids = {
        row[0]
        for row in con.execute(
            """
            SELECT q.id
            FROM quiz q JOIN section s ON s.section_id=q.section_id
            WHERE s.chapter_id=? AND s.image_path IS NOT NULL AND trim(s.image_path)<>''
            """,
            (chapter,),
        )
    }
    con.close()

    if len(chapter_ids) != expect_reviewed:
        raise ValidationError(
            f"database chapter count {len(chapter_ids)} != expected {expect_reviewed}"
        )

    reviewed = 0
    item_count = 0
    severe_count = 0
    seen_ids = set()
    for patch_path in patch_paths:
        patch = read_json(patch_path)
        extra_top = set(patch) - TOP_KEYS
        if extra_top:
            raise ValidationError(f"unsupported patch keys: {sorted(extra_top)}")
        if not isinstance(patch.get("reviewed"), int) or patch["reviewed"] < 0:
            raise ValidationError(f"invalid reviewed count in {patch_path}")
        reviewed += patch["reviewed"]
        for item in patch.get("items", []):
            extra_item = set(item) - ITEM_KEYS
            if extra_item:
                raise ValidationError(f"unsupported item keys: {sorted(extra_item)}")
            qid = item.get("id")
            if qid not in chapter_ids:
                raise ValidationError(f"item id {qid} is outside chapter {chapter}")
            if qid in seen_ids:
                raise ValidationError(f"duplicate item id {qid}")
            seen_ids.add(qid)
            changed = [key for key in ("translation", "explanation") if key in item]
            if not changed:
                raise ValidationError(f"item id {qid} has no editable field")
            for key in changed:
                if not isinstance(item[key], str) or not item[key].strip():
                    raise ValidationError(f"item id {qid} has empty {key}")
            item_count += 1
        for severe in patch.get("severe", []):
            extra_severe = set(severe) - SEVERE_KEYS
            if extra_severe:
                raise ValidationError(
                    f"unsupported severe keys: {sorted(extra_severe)}"
                )
            if severe.get("id") not in chapter_ids:
                raise ValidationError(
                    f"severe id {severe.get('id')} is outside chapter {chapter}"
                )
            if not severe.get("type") or not severe.get("detail"):
                raise ValidationError("severe entry requires type and detail")
            severe_count += 1

    if reviewed != expect_reviewed:
        raise ValidationError(f"reviewed total {reviewed} != expected {expect_reviewed}")

    manifest = read_json(manifest_path)
    if manifest.get("chapter") != chapter:
        raise ValidationError("image manifest chapter does not match")
    if set(manifest.get("section_ids", [])) != image_sections:
        raise ValidationError("image section manifest does not match database")
    if set(manifest.get("question_ids", [])) != image_question_ids:
        raise ValidationError("image question manifest does not match database")

    return {
        "chapter": chapter,
        "reviewed": reviewed,
        "items": item_count,
        "severe": severe_count,
        "image_sections": len(image_sections),
        "image_questions": len(image_question_ids),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", required=True)
    parser.add_argument("--chapter", required=True, type=int)
    parser.add_argument("--patches", nargs="+", required=True)
    parser.add_argument("--image-manifest", required=True)
    parser.add_argument("--expect-reviewed", required=True, type=int)
    args = parser.parse_args()

    patch_paths = []
    for pattern in args.patches:
        patch_paths.extend(Path(path) for path in sorted(glob.glob(pattern)))
    if not patch_paths:
        raise ValidationError("no patch files matched")

    result = validate(
        args.db,
        args.chapter,
        patch_paths,
        args.image_manifest,
        args.expect_reviewed,
    )
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except ValidationError as exc:
        sys.exit(f"validation failed: {exc}")
```

- [ ] **Step 4: 运行校验器测试**

Run: `python tools/review/tests/test_validate_chapter.py -v`

Expected: 3 tests run, all `ok`.

- [ ] **Step 5: 单独提交校验工具**

```powershell
git add -- tools/review/validate_chapter.py tools/review/tests/test_validate_chapter.py
git commit -m "test: validate chapter review patches"
```

### Task 2: 建立数据库基线与 8 个只读分片

**Files:**
- Create: `assets/db/backup/quiz.chapter1-pre-review.20260826.db`
- Create: `tools/review/work/ch01/baseline/ch01_before.json`
- Create: `tools/review/work/ch01/exports/ch01_sec001-008.json`
- Create: `tools/review/work/ch01/exports/ch01_sec009-016.json`
- Create: `tools/review/work/ch01/exports/ch01_sec017-022.json`
- Create: `tools/review/work/ch01/exports/ch01_sec023-027.json`
- Create: `tools/review/work/ch01/exports/ch01_sec028-032.json`
- Create: `tools/review/work/ch01/exports/ch01_sec033-045.json`
- Create: `tools/review/work/ch01/exports/ch01_sec046-052.json`
- Create: `tools/review/work/ch01/exports/ch01_sec053-058.json`

- [ ] **Step 1: 验证主库并创建字节级备份**

Run:

```powershell
sqlite3 assets\db\quiz.db "PRAGMA quick_check;"
Copy-Item -LiteralPath assets\db\quiz.db -Destination assets\db\backup\quiz.chapter1-pre-review.20260826.db
Get-FileHash assets\db\quiz.db,assets\db\backup\quiz.chapter1-pre-review.20260826.db -Algorithm SHA256
```

Expected: `quick_check` 输出 `ok`；两个 SHA-256 完全相同。

- [ ] **Step 2: 导出全章基线**

Run:

```powershell
New-Item -ItemType Directory -Force -Path tools\review\work\ch01\baseline,tools\review\work\ch01\exports,tools\review\patches | Out-Null
python tools\review\export_chapter.py --chapter 1 --out tools\review\work\ch01\baseline\ch01_before.json
```

Expected: `sections=58`、`with image=7`、`questions=535`。

- [ ] **Step 3: 导出 8 个分片**

Run:

```powershell
python tools\review\export_chapter.py --chapter 1 --sec-from 1 --sec-to 8 --out tools\review\work\ch01\exports\ch01_sec001-008.json
python tools\review\export_chapter.py --chapter 1 --sec-from 9 --sec-to 16 --out tools\review\work\ch01\exports\ch01_sec009-016.json
python tools\review\export_chapter.py --chapter 1 --sec-from 17 --sec-to 22 --out tools\review\work\ch01\exports\ch01_sec017-022.json
python tools\review\export_chapter.py --chapter 1 --sec-from 23 --sec-to 27 --out tools\review\work\ch01\exports\ch01_sec023-027.json
python tools\review\export_chapter.py --chapter 1 --sec-from 28 --sec-to 32 --out tools\review\work\ch01\exports\ch01_sec028-032.json
python tools\review\export_chapter.py --chapter 1 --sec-from 33 --sec-to 45 --out tools\review\work\ch01\exports\ch01_sec033-045.json
python tools\review\export_chapter.py --chapter 1 --sec-from 46 --sec-to 52 --out tools\review\work\ch01\exports\ch01_sec046-052.json
python tools\review\export_chapter.py --chapter 1 --sec-from 53 --sec-to 58 --out tools\review\work\ch01\exports\ch01_sec053-058.json
```

Expected question counts in order: `76, 95, 58, 57, 52, 72, 61, 64`；合计 535。

### Task 3: 审校小节 1–8

**Files:**
- Read: `tools/review/work/ch01/exports/ch01_sec001-008.json`
- Create: `tools/review/patches/ch01_sec001-008.json`

- [ ] **Step 1: 逐题审校 76 道无图题**

逐条对照 `question`、`answer`、`translation`、`explanation`。准确内容保持不变；仅将确有问题的题加入 `items`，且只给出需要变化的 `translation` 和/或 `explanation`。

- [ ] **Step 2: 写入分片结果并自查**

结果文件固定使用以下顶层结构，`reviewed` 为 76：

```json
{
  "slice": "ch01_sec001-008",
  "reviewed": 76,
  "items": [],
  "severe": []
}
```

将实际发现的必要修改加入 `items`；只将答案矛盾、图片矛盾或数据映射冲突加入 `severe`。

### Task 4: 审校小节 9–16

**Files:**
- Read: `tools/review/work/ch01/exports/ch01_sec009-016.json`
- Create: `tools/review/patches/ch01_sec009-016.json`

- [ ] **Step 1: 逐题审校 95 道无图题**

重点区分平面交叉口、立体交叉口、高速公路、主要郊区道路、交通岛、人行横道、安全岛和步行区的定义边界；保持题目与答案不变。

- [ ] **Step 2: 写入分片结果**

使用 `slice=ch01_sec009-016`、`reviewed=95`，仅记录必要修改和严重问题。

### Task 5: 审校小节 17–22并完成前三张图片

**Files:**
- Read: `tools/review/work/ch01/exports/ch01_sec017-022.json`
- Read: `assets/images/quiz/20.gif`
- Read: `assets/images/quiz/21.gif`
- Read: `assets/images/quiz/22.gif`
- Create: `tools/review/patches/ch01_sec017-022.json`

- [ ] **Step 1: 查看 20、21、22 三张图片**

使用 `view_image` 分别查看三张图片，记录每张图的行车道数量、车道数量、双向/单向布局和分隔关系。

- [ ] **Step 2: 逐题审校 58 道题**

小节 20–22 的 26 道题必须逐题结合各自图片核对；小节 17–19 的 32 道题按无图题标准核对。不得把三张道路布局图的解析互相套用。

- [ ] **Step 3: 写入分片结果**

使用 `slice=ch01_sec017-022`、`reviewed=58`，仅记录必要修改和严重问题。

### Task 6: 审校小节 23–27

**Files:**
- Read: `tools/review/work/ch01/exports/ch01_sec023-027.json`
- Create: `tools/review/patches/ch01_sec023-027.json`

- [ ] **Step 1: 逐题审校 57 道无图题**

重点核对轻便摩托车、摩托车、机动三轮车、机动四轮车和机动车分类，以及排量、功率、速度和车轮数量等限定条件。

- [ ] **Step 2: 写入分片结果**

使用 `slice=ch01_sec023-027`、`reviewed=57`，仅记录必要修改和严重问题。

### Task 7: 审校小节 28–32

**Files:**
- Read: `tools/review/work/ch01/exports/ch01_sec028-032.json`
- Create: `tools/review/patches/ch01_sec028-032.json`

- [ ] **Step 1: 逐题审校 52 道无图题**

重点核对乘用车、旅居车、旅居挂车、挂车、半挂车、作业机械和农业机械的准确分类，避免把 `autocaravan` 与 `caravan` 混译。

- [ ] **Step 2: 写入分片结果**

使用 `slice=ch01_sec028-032`、`reviewed=52`，仅记录必要修改和严重问题。

### Task 8: 审校小节 33–45并完成四张车辆标牌图片

**Files:**
- Read: `tools/review/work/ch01/exports/ch01_sec033-045.json`
- Read: `assets/images/quiz/33.gif`
- Read: `assets/images/quiz/34.gif`
- Read: `assets/images/quiz/35.gif`
- Read: `assets/images/quiz/36.gif`
- Create: `tools/review/patches/ch01_sec033-045.json`

- [ ] **Step 1: 查看 33、34、35、36 四张图片**

使用 `view_image` 分别确认超长货物、危险品、超过 3.5 吨货车和超过 3.5 吨挂车的标牌形状、底色、边框和条纹。不得混淆红白斜纹方牌、橙色危险品矩形牌、红黄斜纹货车牌和黄底红边挂车牌。

- [ ] **Step 2: 逐题审校 72 道题**

小节 33–36 的 7 道题逐题结合图片核对；小节 37–45 的 65 道题按无图标准核对车辆反光条、限速标识和驾驶人义务。

- [ ] **Step 3: 写入分片结果**

使用 `slice=ch01_sec033-045`、`reviewed=72`，仅记录必要修改和严重问题。

### Task 9: 审校小节 46–52

**Files:**
- Read: `tools/review/work/ch01/exports/ch01_sec046-052.json`
- Create: `tools/review/patches/ch01_sec046-052.json`

- [ ] **Step 1: 逐题审校 61 道无图题**

重点核对驾驶人对行人、骑行者、摩托车驾驶人、儿童、盲人、聋盲人士、孕妇和推婴儿车人员的义务与谨慎要求。

- [ ] **Step 2: 写入分片结果**

使用 `slice=ch01_sec046-052`、`reviewed=61`，仅记录必要修改和严重问题。

### Task 10: 审校小节 53–58

**Files:**
- Read: `tools/review/work/ch01/exports/ch01_sec053-058.json`
- Create: `tools/review/patches/ch01_sec053-058.json`

- [ ] **Step 1: 逐题审校 64 道无图题**

重点核对老年人、信号灯处过街行人、占用行车道的行人与骑行者、人行横道、校车停靠区和出租车专用停车位附近的驾驶义务。

- [ ] **Step 2: 写入分片结果**

使用 `slice=ch01_sec053-058`、`reviewed=64`，仅记录必要修改和严重问题。

### Task 11: 建立图片审校清单并验证全部补丁

**Files:**
- Create: `tools/review/work/ch01/image_review_manifest.json`
- Read: `tools/review/patches/ch01_*.json`

- [ ] **Step 1: 写入精确图片审校清单**

在确认 7 张图片均已实际查看、33 道题均已结合图片核对后，创建：

```json
{
  "chapter": 1,
  "section_ids": [20, 21, 22, 33, 34, 35, 36],
  "question_ids": [
    204, 205, 206, 207, 208, 209, 210,
    211, 212, 213, 214, 215, 216, 217, 218,
    219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229,
    339, 340, 341, 342, 343, 344, 345
  ]
}
```

- [ ] **Step 2: 运行结构和覆盖率校验**

Run:

```powershell
python tools\review\validate_chapter.py --db assets\db\quiz.db --chapter 1 --patches "tools\review\patches\ch01_*.json" --image-manifest tools\review\work\ch01\image_review_manifest.json --expect-reviewed 535
```

Expected JSON fields: `reviewed=535`、`image_sections=7`、`image_questions=33`；命令退出码为 0。

- [ ] **Step 3: 运行写回 dry-run**

Run:

```powershell
python tools\review\apply_patch.py "tools\review\patches\ch01_*.json" --dry-run
```

Expected: 输出预计更新行数和无操作项数量；如有 severe，逐项输出但不修改数据库。

### Task 12: 单事务写回、数据库复验与章节交付

**Files:**
- Modify: `assets/db/quiz.db`
- Create or Modify: `tools/review/revision_log.jsonl`
- Create: `tools/review/work/ch01/verification.txt`
- Create: `tools/review/work/ch01/after/ch01_after.json`

- [ ] **Step 1: 应用全部已验证补丁**

Run:

```powershell
python tools\review\apply_patch.py "tools\review\patches\ch01_*.json"
```

Expected: 输出实际更新行数；该数字与 dry-run 的预计更新行数一致。

- [ ] **Step 2: 运行数据库完整性和边界检查**

Run:

```powershell
sqlite3 -header -column assets\db\quiz.db "ATTACH 'assets/db/backup/quiz.chapter1-pre-review.20260826.db' AS baseline; PRAGMA integrity_check; SELECT 'quiz_rows' AS check_name, (SELECT COUNT(*) FROM main.quiz) AS live_value, (SELECT COUNT(*) FROM baseline.quiz) AS baseline_value; SELECT 'missing_quiz_ids' AS check_name, COUNT(*) AS differing_rows FROM baseline.quiz b LEFT JOIN main.quiz q ON q.id=b.id WHERE q.id IS NULL; SELECT 'extra_quiz_ids' AS check_name, COUNT(*) AS differing_rows FROM main.quiz q LEFT JOIN baseline.quiz b ON b.id=q.id WHERE b.id IS NULL; SELECT 'chapter1_protected_fields' AS check_name, COUNT(*) AS differing_rows FROM main.quiz q JOIN baseline.quiz b ON b.id=q.id JOIN baseline.section s ON s.section_id=b.section_id WHERE s.chapter_id=1 AND (q.id IS NOT b.id OR q.section_id IS NOT b.section_id OR q.question_number IS NOT b.question_number OR q.question IS NOT b.question OR q.answer IS NOT b.answer); SELECT 'outside_chapter1' AS check_name, COUNT(*) AS differing_rows FROM main.quiz q JOIN baseline.quiz b ON b.id=q.id JOIN baseline.section s ON s.section_id=b.section_id WHERE s.chapter_id<>1 AND (q.question IS NOT b.question OR q.answer IS NOT b.answer OR q.section_id IS NOT b.section_id OR q.translation IS NOT b.translation OR q.explanation IS NOT b.explanation OR q.question_number IS NOT b.question_number); SELECT 'section_table' AS check_name, COUNT(*) AS differing_rows FROM main.section s JOIN baseline.section b ON b.id=s.id WHERE s.section_id IS NOT b.section_id OR s.chapter_id IS NOT b.chapter_id OR s.name IS NOT b.name OR s.image_path IS NOT b.image_path; SELECT 'chapter_table' AS check_name, COUNT(*) AS differing_rows FROM main.chapter c JOIN baseline.chapter b ON b.id=c.id WHERE c.chapter_id IS NOT b.chapter_id OR c.name IS NOT b.name OR c.image_path IS NOT b.image_path;"
```

Expected: `integrity_check=ok`；主库与基线题数均为 7193；`missing_quiz_ids`、`extra_quiz_ids`、`chapter1_protected_fields`、`outside_chapter1`、`section_table`、`chapter_table` 的 `differing_rows` 均为 0。

使用 `apply_patch` 创建 `tools/review/work/ch01/verification.txt`，逐项写入本次实际观察到的备份 SHA-256、补丁校验摘要、dry-run 行数、写回行数、上述 SQLite 检查结果和 Flutter 检查结果；不得预填或推测未运行命令的结论。

- [ ] **Step 3: 重新导出并复查所有修改题**

Run:

```powershell
New-Item -ItemType Directory -Force -Path tools\review\work\ch01\after | Out-Null
python tools\review\export_chapter.py --chapter 1 --out tools\review\work\ch01\after\ch01_after.json
```

逐条比较所有补丁项与 `ch01_after.json`，确认数据库值与补丁完全一致；确认 `revision_log.jsonl` 对每个实际修改 ID 记录了 before、after 和 note。

- [ ] **Step 4: 运行项目级检查**

Run:

```powershell
flutter test
```

Expected: 命令退出码为 0。若仓库当前没有 Flutter 测试，记录实际输出，不把“没有测试”表述为测试通过。

- [ ] **Step 5: 提交第 1 章审校结果**

仅在所有检查成功后执行：

```powershell
git add -- assets/db/quiz.db tools/review/patches/ch01_*.json tools/review/revision_log.jsonl tools/review/work/ch01/image_review_manifest.json tools/review/work/ch01/verification.txt
git commit -m "fix: review chapter 1 Chinese content"
```

不得暂存 `assets/db/backup/`、原有 `tools/review/out/` 或任何与本章无关的用户文件。

- [ ] **Step 6: 向用户交付章节结果**

报告第 1 章 535/535 已审校、7/7 图片小节与 33/33 带图题已核对、备份路径、数据库完整性结果和项目级检查结果。普通修改不逐条列出；只展开 severe 的题号、类型、修复/跳过状态和原因。
