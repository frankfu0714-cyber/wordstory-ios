#!/usr/bin/env python3
"""
Build a reverse-lookup index (Chinese term -> English headword) for ecdict.db.

The bundled ECDICT only indexes English headwords. To support offline zh-to-en
lookups (and zh prefix autocomplete) the app needs an additional table mapping
each Chinese term that appears in a translation back to the source English
word.

Usage: tools/build_zh_index.py Resources/ecdict.db

The script is idempotent: it DROPs and recreates zh_index every run, so it's
safe to re-run after edits.
"""

from __future__ import annotations

import re
import sqlite3
import sys
import time
from pathlib import Path

POS_TOKEN = re.compile(r"^(?:[a-zA-Z]{1,5}\.\s+)+")
DOMAIN_TAG = re.compile(r"\[[^\]]{1,8}\]\s*")
TERM_SPLIT = re.compile(r"[;；，、,]")
# Translation lines are joined with a literal backslash-n in the source data,
# not an actual newline byte. See the ecdict CSV format.
LINE_SPLIT = re.compile(r"\\n")
CJK = re.compile(r"[一-鿿㐀-䶿]")

# Strip trailing "的" / "地" / "之" when they would obscure a noun stem? No —
# leave terms as-is. The user wants exact-match lookup, not stemming.

MAX_TERM_LEN = 24  # in characters — anything longer is descriptive text, not a gloss
MAX_TERMS_PER_ENTRY = 24  # cap so pathological rows (e.g. "set") don't bloat the index

# Inline parentheticals like "貓 (家養)" — strip the parenthetical so "貓" matches.
PAREN = re.compile(r"[（(][^()）]{0,32}[)）]")

def parse_translation(translation: str) -> list[str]:
    """Return the ordered list of Chinese terms extracted from a translation."""
    terms: list[str] = []
    seen: set[str] = set()
    for line in LINE_SPLIT.split(translation):
        line = POS_TOKEN.sub("", line)
        line = DOMAIN_TAG.sub("", line)
        for raw in TERM_SPLIT.split(line):
            term = PAREN.sub("", raw).strip()
            # Strip stray leading punctuation that may remain after the POS / domain
            # trim (e.g. "- 貓" → "貓").
            term = term.strip(" \t-—–·*")
            if not term:
                continue
            if len(term) > MAX_TERM_LEN:
                continue
            if not CJK.search(term):
                continue
            if term in seen:
                continue
            seen.add(term)
            terms.append(term)
            if len(terms) >= MAX_TERMS_PER_ENTRY:
                return terms
    return terms


def build(db_path: Path) -> None:
    if not db_path.exists():
        sys.exit(f"db not found: {db_path}")
    con = sqlite3.connect(db_path)
    con.execute("PRAGMA journal_mode = MEMORY")
    con.execute("PRAGMA synchronous = OFF")
    con.execute("PRAGMA temp_store = MEMORY")

    print(f"[zh_index] dropping existing index/table")
    con.execute("DROP INDEX IF EXISTS idx_zh_term_prefix")
    con.execute("DROP TABLE IF EXISTS zh_index")
    # WITHOUT ROWID + compound PRIMARY KEY (zh_term, rank, en_word) gives us a
    # single B-tree that serves both the equality lookup ("WHERE zh_term = ?
    # ORDER BY rank") and the prefix scan ("WHERE zh_term LIKE 'X%'") — no
    # secondary index needed, which saves ~24MB on the bundle.
    con.execute("""
        CREATE TABLE zh_index (
            zh_term TEXT NOT NULL COLLATE NOCASE,
            rank    INTEGER NOT NULL,
            en_word TEXT NOT NULL,
            PRIMARY KEY (zh_term, rank, en_word)
        ) WITHOUT ROWID
    """)

    total_rows = con.execute("SELECT COUNT(*) FROM stardict").fetchone()[0]
    print(f"[zh_index] scanning {total_rows:,} stardict rows")

    started = time.time()
    cur = con.execute("SELECT word, translation FROM stardict")
    batch: list[tuple[str, str, int]] = []
    BATCH_SIZE = 50_000
    processed = 0
    pairs = 0
    for word, translation in cur:
        processed += 1
        if not translation:
            continue
        for rank, term in enumerate(parse_translation(translation), start=1):
            batch.append((term, rank, word))
            pairs += 1
        if len(batch) >= BATCH_SIZE:
            con.executemany("INSERT OR IGNORE INTO zh_index VALUES (?, ?, ?)", batch)
            batch.clear()
        if processed % 100_000 == 0:
            elapsed = time.time() - started
            print(f"[zh_index]   {processed:,}/{total_rows:,} rows, {pairs:,} pairs ({elapsed:.1f}s)")
    if batch:
        con.executemany("INSERT OR IGNORE INTO zh_index VALUES (?, ?, ?)", batch)
    con.commit()
    print(f"[zh_index] inserted {pairs:,} (zh_term, rank, en_word) pairs")

    print(f"[zh_index] running VACUUM to reclaim space")
    con.execute("VACUUM")
    con.commit()
    con.close()

    size_mb = db_path.stat().st_size / (1024 * 1024)
    elapsed = time.time() - started
    print(f"[zh_index] done in {elapsed:.1f}s; ecdict.db is now {size_mb:.1f} MB")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: build_zh_index.py <path/to/ecdict.db>")
    build(Path(sys.argv[1]))
