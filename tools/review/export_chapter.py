import argparse, json, os, sqlite3, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DB = os.path.join(ROOT, "assets", "db", "quiz.db")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--chapter", type=int, required=True)
    ap.add_argument("--sec-from", type=int, default=None)
    ap.add_argument("--sec-to", type=int, default=None)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    con = sqlite3.connect(DB)
    con.row_factory = sqlite3.Row
    ch = con.execute("SELECT chapter_id, name FROM chapter WHERE chapter_id=?", (a.chapter,)).fetchone()
    if ch is None:
        sys.exit("no such chapter: %d" % a.chapter)

    sql = "SELECT section_id, name, image_path FROM section WHERE chapter_id=?"
    args = [a.chapter]
    if a.sec_from is not None:
        sql += " AND section_id>=?"; args.append(a.sec_from)
    if a.sec_to is not None:
        sql += " AND section_id<=?"; args.append(a.sec_to)
    sql += " ORDER BY section_id"

    out = {"chapter": {"chapter_id": ch["chapter_id"], "name": ch["name"]}, "sections": []}
    nq = 0
    for s in con.execute(sql, args):
        img = s["image_path"]
        qs = []
        for q in con.execute(
            "SELECT id, question_number, question, answer, translation, explanation "
            "FROM quiz WHERE section_id=? ORDER BY question_number", (s["section_id"],)):
            qs.append(dict(q)); nq += 1
        out["sections"].append({
            "section_id": s["section_id"],
            "name": s["name"],
            "image_path": img,
            "image_abs": os.path.join(ROOT, img.replace("/", os.sep)) if img else None,
            "questions": qs,
        })
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with open(a.out, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    withimg = sum(1 for s in out["sections"] if s["image_path"])
    print("chapter %d | sections=%d (with image=%d) | questions=%d -> %s"
          % (a.chapter, len(out["sections"]), withimg, nq, a.out))

if __name__ == "__main__":
    main()
