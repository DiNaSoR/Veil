#!/usr/bin/env python3
import argparse
import json
import sqlite3
from pathlib import Path

def read_text(p: Path) -> str:
    # tolerate BOM
    return p.read_text(encoding="utf-8-sig", errors="replace")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    args = ap.parse_args()

    repo = Path(args.repo)
    mem = repo / ".cursor" / "memory"
    lessons_dir = mem / "lessons"
    out_db = mem / "memory.sqlite"

    lessons_index = mem / "lessons-index.json"
    journal_index = mem / "journal-index.json"

    if not journal_index.exists():
        print("Missing journal-index.json. Run rebuild-memory-index.ps1 first.")
        return 2

    # Load lessons from JSON index
    lessons = []
    if lessons_index.exists():
        lessons_text = read_text(lessons_index).strip()
        if lessons_text:
            lessons = json.loads(lessons_text)
            if not isinstance(lessons, list):
                lessons = [lessons] if lessons else []

    # Load journal from JSON index
    journal_text = read_text(journal_index).strip()
    journal = json.loads(journal_text) if journal_text else []
    if not isinstance(journal, list):
        journal = [journal] if journal else []

    if out_db.exists():
        out_db.unlink()

    con = sqlite3.connect(str(out_db))
    cur = con.cursor()

    # FTS for fast local search over memory
    cur.execute("CREATE VIRTUAL TABLE memory_fts USING fts5(kind, id, date, tags, title, content, path);")

    # Insert memo + hot rules as single docs
    hot = mem / "hot-rules.md"
    memo = mem / "memo.md"
    if hot.exists():
        cur.execute("INSERT INTO memory_fts(kind,id,date,tags,title,content,path) VALUES (?,?,?,?,?,?,?)",
                    ("hot_rules","HOT",None,"","Hot Rules",read_text(hot),str(hot)))
    if memo.exists():
        cur.execute("INSERT INTO memory_fts(kind,id,date,tags,title,content,path) VALUES (?,?,?,?,?,?,?)",
                    ("memo","MEMO",None,"","Memo",read_text(memo),str(memo)))

    # Lessons (now from individual files)
    for l in lessons:
        tags = " ".join(l.get("Tags") or [])
        applies = ", ".join(l.get("AppliesTo") or [])
        lesson_file = l.get("File", "")
        lesson_path = lessons_dir / lesson_file if lesson_file else mem / "lessons.md"
        
        # Read full lesson content if file exists
        content = f"{l.get('Title','')}\nRule: {l.get('Rule','')}\nAppliesTo: {applies}"
        if lesson_path.exists():
            content = read_text(lesson_path)
        
        cur.execute("INSERT INTO memory_fts(kind,id,date,tags,title,content,path) VALUES (?,?,?,?,?,?,?)",
                    ("lesson", l.get("Id"), l.get("Introduced"), tags, l.get("Title"), content, str(lesson_path)))

    # Journal entries
    for e in journal:
        tags = " ".join(e.get("Tags") or [])
        files_list = e.get("Files")
        if isinstance(files_list, dict):
            files_list = []  # Handle empty object {}
        files = ", ".join(files_list or [])
        content = f"{e.get('Title','')}\nFiles: {files}"
        cur.execute("INSERT INTO memory_fts(kind,id,date,tags,title,content,path) VALUES (?,?,?,?,?,?,?)",
                    ("journal", None, e.get("Date"), tags, e.get("Title"), content, str(mem / "journal" / e.get("MonthFile",""))))

    con.commit()
    con.close()

    print(f"Built: {out_db}")

if __name__ == "__main__":
    raise SystemExit(main())