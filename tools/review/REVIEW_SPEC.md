# 题库审校规范（子 agent 必读）

## 任务
核对意大利驾照题库的**中文翻译**与**中文解析**。数据库：`assets/db/quiz.db` 表 `quiz`。

## 铁律（绝对不可违反）
1. **`question`（意大利语题干）绝对正确，禁止修改、禁止质疑。**
2. **`answer`（0=否/False，1=是/True）绝对正确，禁止修改、禁止质疑。**
3. 你只能修改两个字段：`translation`（中文翻译）、`explanation`（中文解析）。
4. **解析的结论必须与 `answer` 一致。** 这是最高优先级的检查项。
   - `answer=1` → 解析必须论证该说法**成立/正确**。
   - `answer=0` → 解析必须论证该说法**不成立/错误**，并说明正确情况是什么。
   - 若发现解析在论证与 `answer` 相反的结论，这是**严重错误**，必须改写并计入 severe 清单。

## 审校标准

### translation（翻译）
- 忠实、准确、通顺的简体中文，不遗漏不增添语义。
- 保留专业含义。术语首次出现可用「中文（意大利语）」形式，如「加速车道（corsia di accelerazione）」。
- 原文若已准确，**跳过不改**。不要为了措辞偏好而改动。
- 注意易错术语：
  - `strada` 道路 / `carreggiata` 行车道 / `corsia` 车道（三者层级不同，不可混用）
  - `banchina` 路肩 / `marciapiede` 人行道 / `pista ciclabile` 自行车道
  - `sosta` 停放 / `fermata` 临时停车 / `arresto` 停车（临时性停止）
  - `preavviso` 预告 / `preannuncia` 预示
  - `autocarro` 货车 / `rimorchio` 挂车 / `semirimorchio` 半挂车 / `autotreno` 汽车列车
  - `massa a pieno carico` 满载总质量
  - 「行驶」应写作「行驶」→ 正确写法是**行驶**（注意：正确中文为「行驶」，即 xíng shǐ，写作「行驶」）。统一使用「行驶」。

### explanation（解析）
- 简体中文，2–4 句，先给结论再给依据。
- 结论必须与 `answer` 一致（见铁律 4）。
- `answer=0` 时应指出错在哪里、正确的是什么。
- 引用意大利交规实质规则，不要空泛复述题干。
- 禁止只是把题干翻译一遍当解析（如解析内容与 translation 几乎相同且无任何补充信息，应改写补充依据）。
- 原文若已准确且有实质内容，**跳过不改**。

### 带图题（image_path 非空）
- **必须先用 view_image 查看图片**，再判断解析是否与图像一致。
- 解析必须描述图中标志/场景的实际特征（形状、颜色、符号、车道布局等），并据此论证结论。
- 常见坑：同一题干出现在多个小节，配图不同，答案随图而变。**绝不能凭题干套用其他小节的解析**，必须按本节配图重新判断。
- 若图像与题干+答案的组合无法自圆其说，记入 severe，不要强行编造。

## 意大利标志体系速查
- `segnale di pericolo` 危险标志：**三角形、白底红边**
- `segnale di divieto` 禁令标志：**圆形、白底红边**
- `segnale di obbligo` 强制标志：**圆形、蓝底白图案**
- `segnale di precedenza` 优先标志：三角形（让行，尖端朝下）、八角形（停车让行）、菱形（优先道路）等
- `segnale di indicazione` 指示标志：**矩形**（颜色随道路类型：绿=高速，蓝=主要郊区道路，白=市区，黄=临时/施工）
- `segnale di prescrizione` 规定标志 = 优先标志 + 禁令标志 + 强制标志的**统称**（危险标志和指示标志不属于此类）
- 货车（>3.5t）后部标志板：**红黄斜条纹**横长方形
- 挂车/半挂车（>3.5t）后部标志板：**黄底红边**长方形
- 超长货物标志板：**红白斜条纹**方形

## 输出格式
写入 `tools/review/patches/<你的分片名>.json`，UTF-8，结构：

```json
{
  "slice": "ch01_sec001-020",
  "reviewed": 120,
  "items": [
    {
      "id": 343,
      "translation": "……（仅在需要改时给出，否则省略该键）",
      "explanation": "……（仅在需要改时给出，否则省略该键）",
      "note": "解析结论与答案矛盾，已改写"
    }
  ],
  "severe": [
    {
      "id": 343,
      "type": "answer_contradiction",
      "detail": "原解析论证该说法成立，但 answer=0；图中为货车红黄斜条纹板，非挂车黄底红边板"
    }
  ]
}
```

规则：
- `items` 只包含**确实需要修改**的题；无需修改的题不要出现在 `items` 里。
- 同一题若只改解析，就只给 `explanation` 键，不要给 `translation`。
- `severe` 只记录：解析与答案矛盾、解析与图片矛盾、疑似题库数据本身有冲突。普通措辞优化不算 severe。
- `reviewed` 填你实际逐题看过的题目总数。

## 严禁
- 严禁修改 `question`、`answer`、`id`、`section_id`、`question_number`。
- 严禁跳过带图题的看图步骤。
- 严禁凭猜测填写解析。
- 严禁直接写数据库，只能产出 patch JSON。
