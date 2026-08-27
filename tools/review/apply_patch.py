import argparse, datetime, glob, json, os, shutil, sqlite3, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DB = os.path.join(ROOT, "assets", "db", "quiz.db")
LOG = os.path.join(ROOT, "tools", "review", "revision_log.jsonl")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("patches", nargs="+")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    files = []
    for p in a.patches:
        files.extend(sorted(glob.glob(p)))
    if not files:
        sys.exit("no patch files matched")

    con = sqlite3.connect(DB)
    con.row_factory = sqlite3.Row
    ts = datetime.datetime.now().isoformat(timespec="seconds")
    applied = skipped = 0
    logrows = []
    severe = []

    for fp in files:
        with open(fp, encoding="utf-8") as f:
            patch = json.load(f)
        for it in patch.get("items", []):
            qid = it["id"]
            cur = con.execute(
                "SELECT id, question, answer, translation, explanation FROM quiz WHERE id=?", (qid,)).fetchone()
            if cur is None:
                sys.exit("patch %s references missing quiz id %s" % (fp, qid))
            upd, before, after = {}, {}, {}
            for col in ("translation", "explanation"):
                if col in it and it[col] is not None:
                    new = str(it[col]).strip()
                    if new and new != (cur[col] or ""):
                        upd[col] = new
                        before[col] = cur[col]
                        after[col] = new
            if not upd:
                skipped += 1
                continue
            if not a.dry_run:
                sets = ", ".join("%s=?" % c for c in upd)
                con.execute("UPDATE quiz SET %s WHERE id=?" % sets, list(upd.values()) + [qid])
            applied += 1
            logrows.append({"ts": ts, "patch": os.path.basename(fp), "id": qid,
                            "question": cur["question"], "answer": cur["answer"],
                            "before": before, "after": after, "note": it.get("note")})
        for s in patch.get("severe", []):
            severe.append({"patch": os.path.basename(fp), **s})

    if a.dry_run:
        con.rollback()
        print("[DRY-RUN] would update %d rows, skip %d no-op" % (applied, skipped))
    else:
        con.commit()
        with open(LOG, "a", encoding="utf-8") as f:
            for r in logrows:
                f.write(json.dumps(r, ensure_ascii=False) + "\n")
        print("applied %d rows, skipped %d no-op -> %s" % (applied, skipped, DB))
    if severe:
        print("\n=== SEVERE (%d) ===" % len(severe))
        for s in severe:
            print(" -", json.dumps(s, ensure_ascii=False))

if __name__ == "__main__":
    main()
