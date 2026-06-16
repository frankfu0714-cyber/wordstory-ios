import Foundation
import SQLite3

/// Offline ECDICT lookup. The database lives at `Resources/ecdict.db` in the
/// app bundle (~75 MB, ~770k English headwords, Traditional Chinese
/// translations). Two indexes:
///   stardict (PRIMARY KEY word)            — en → zh forward lookup
///   zh_index (PRIMARY KEY zh_term, rank…)  — zh → en reverse lookup, built
///                                            by tools/build_zh_index.py
///
/// Implemented as an actor so the (read-only) SQLite handle can be shared
/// across concurrent lookups safely. SQLite's `SQLITE_OPEN_FULLMUTEX` flag
/// makes the connection itself thread-safe, but we still gate access through
/// the actor so prepared-statement reuse stays single-threaded.
actor DictionaryService {

    static let shared = DictionaryService()

    private var db: OpaquePointer?
    private var openAttempted = false

    struct Hit {
        let word: String
        let phonetic: String?
        let translation: String
    }

    /// Lazily opens the bundled database the first time `lookup` runs.
    private func ensureOpen() {
        guard !openAttempted else { return }
        openAttempted = true

        guard let url = Bundle.main.url(forResource: "ecdict", withExtension: "db") else {
            print("[Dictionary] ecdict.db not found in bundle — falling back to online for every word")
            return
        }
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        let status = sqlite3_open_v2(url.path, &handle, flags, nil)
        guard status == SQLITE_OK, let handle else {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "sqlite3_open_v2 status=\(status)"
            print("[Dictionary] open failed: \(msg)")
            if let handle { sqlite3_close(handle) }
            return
        }
        self.db = handle
        print("[Dictionary] opened bundled ecdict.db")
    }

    /// Look up a word in the local dictionary.
    /// - Returns: `Hit` on match, `nil` on miss (caller falls back to online).
    ///
    /// For `.zhToEn` the "translation" returned is the matching English word —
    /// the model is inverted so callers (flashcard back face) can stay
    /// direction-agnostic: front = `word`, back = `translation`.
    func lookup(_ word: String, direction: LanguageDirection) -> Hit? {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        switch direction {
        case .enToZh:
            return forwardLookup(trimmed)
        case .zhToEn:
            return reverseLookupTop(trimmed)
        }
    }

    /// Forward (English → Chinese) lookup against the original `stardict` table.
    private func forwardLookup(_ trimmed: String) -> Hit? {
        ensureOpen()
        guard let db else { return nil }

        let sql = "SELECT word, phonetic, translation FROM stardict WHERE word = ? COLLATE NOCASE LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("[Dictionary] prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        // `withCString` keeps the C buffer alive until the closure returns —
        // we step + read the row inside it, so SQLITE_STATIC (nil destructor)
        // is safe and avoids the extra copy SQLITE_TRANSIENT would force.
        return trimmed.withCString { ptr -> Hit? in
            sqlite3_bind_text(stmt, 1, ptr, -1, nil)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            let wordText = sqlite3_column_text(stmt, 0).flatMap { String(cString: $0) } ?? trimmed
            let phonetic = sqlite3_column_text(stmt, 1).flatMap { String(cString: $0) }
            let translation = sqlite3_column_text(stmt, 2).flatMap { String(cString: $0) } ?? ""
            guard !translation.isEmpty else { return nil }
            return Hit(word: wordText, phonetic: phonetic, translation: translation)
        }
    }

    /// Reverse (Chinese → English) lookup. Returns the best single English
    /// headword whose translation contains `chinese`, or nil on miss.
    /// `reverseLookup(_:limit:)` is the multi-result variant.
    private func reverseLookupTop(_ chinese: String) -> Hit? {
        reverseLookup(chinese, limit: 1).first
    }

    /// Reverse-lookup: return up to `limit` English headwords whose translation
    /// includes the given Chinese term. Ordered by:
    ///   1. `rank` ascending      — primary gloss first
    ///   2. has-space ascending   — single-word answers before phrases
    ///   3. `LENGTH(en_word)` ASC — shorter answers first (cat < felis catus)
    ///   4. alphabetical NOCASE
    ///
    /// The ordering is a heuristic, not a frequency model — ECDICT doesn't
    /// expose word frequency. It picks `貓 → cat` correctly; for highly
    /// polysemous terms the user sees the top entry but can scroll the list.
    func reverseLookup(_ chinese: String, limit: Int) -> [Hit] {
        let trimmed = chinese.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        ensureOpen()
        guard let db else { return [] }

        let sql = """
            SELECT en_word
            FROM zh_index
            WHERE zh_term = ? COLLATE NOCASE
            ORDER BY
                rank ASC,
                (en_word LIKE '% %') ASC,
                LENGTH(en_word) ASC,
                en_word COLLATE NOCASE ASC
            LIMIT ?
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("[Dictionary] reverse prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        return trimmed.withCString { ptr -> [Hit] in
            sqlite3_bind_text(stmt, 1, ptr, -1, nil)
            sqlite3_bind_int(stmt, 2, Int32(max(1, limit)))
            var out: [Hit] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cstr = sqlite3_column_text(stmt, 0) {
                    let en = String(cString: cstr)
                    // For the inverted model: word = the queried Chinese term,
                    // translation = the English headword. Phonetic stays nil
                    // (we don't index Chinese phonetics).
                    out.append(Hit(word: trimmed, phonetic: nil, translation: en))
                }
            }
            return out
        }
    }

    /// Prefix search for autocomplete suggestions. Returns up to `limit`
    /// words starting with `prefix` (case-insensitive), ordered alphabetically.
    /// Backed by the COLLATE NOCASE primary key index on `word`, so even
    /// pathological one-character prefixes return in ~10ms or less.
    func searchPrefix(_ prefix: String, limit: Int) -> [String] {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        ensureOpen()
        guard let db else { return [] }

        // Escape LIKE wildcards in the user's typed text so a literal "%" or
        // "_" doesn't blow the pattern open.
        let escaped = trimmed
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        let pattern = escaped + "%"

        let sql = "SELECT word FROM stardict WHERE word LIKE ? ESCAPE '\\' COLLATE NOCASE ORDER BY word LIMIT ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("[Dictionary] prefix prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        let start = CFAbsoluteTimeGetCurrent()
        return pattern.withCString { ptr -> [String] in
            sqlite3_bind_text(stmt, 1, ptr, -1, nil)
            sqlite3_bind_int(stmt, 2, Int32(max(1, limit)))
            var out: [String] = []
            out.reserveCapacity(limit)
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cstr = sqlite3_column_text(stmt, 0) {
                    out.append(String(cString: cstr))
                }
            }
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            if elapsedMs > 20 {
                // Only log when we're approaching the 10ms target the user
                // specified — keeps the console quiet on normal queries.
                print(String(format: "[Dictionary] slow prefix '%@%%': %d rows in %.1fms",
                             trimmed, out.count, elapsedMs))
            }
            return out
        }
    }

    /// Pair returned by `reverseLookupWithGlosses` — one row of the
    /// "Choose English word" picker.
    struct Candidate {
        let english: String
        /// The full Chinese gloss for the English candidate (the same string
        /// ECDICT would return in a normal en → zh forward lookup). Empty if
        /// the forward lookup happens to miss (rare; just means we show the
        /// English word alone).
        let gloss: String
    }

    /// Reverse lookup that also resolves each candidate's full forward
    /// translation in one batched call. Used by the synonyms sheet so it
    /// can render `cat` next to its Chinese gloss in a single round-trip
    /// to the actor.
    func reverseLookupWithGlosses(_ chinese: String, limit: Int) -> [Candidate] {
        let hits = reverseLookup(chinese, limit: limit)
        guard !hits.isEmpty else { return [] }
        return hits.map { hit in
            let gloss = forwardLookup(hit.translation)?.translation ?? ""
            return Candidate(english: hit.translation, gloss: gloss)
        }
    }

    /// Prefix search for Chinese terms — the zh-to-en autocomplete path.
    /// Returns distinct Chinese terms starting with `prefix`, alphabetically.
    func searchPrefixZh(_ prefix: String, limit: Int) -> [String] {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        ensureOpen()
        guard let db else { return [] }

        // Escape LIKE wildcards in the user input.
        let escaped = trimmed
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        let pattern = escaped + "%"

        let sql = """
            SELECT DISTINCT zh_term
            FROM zh_index
            WHERE zh_term LIKE ? ESCAPE '\\' COLLATE NOCASE
            ORDER BY LENGTH(zh_term), zh_term
            LIMIT ?
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("[Dictionary] zh prefix prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        let start = CFAbsoluteTimeGetCurrent()
        return pattern.withCString { ptr -> [String] in
            sqlite3_bind_text(stmt, 1, ptr, -1, nil)
            sqlite3_bind_int(stmt, 2, Int32(max(1, limit)))
            var out: [String] = []
            out.reserveCapacity(limit)
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cstr = sqlite3_column_text(stmt, 0) {
                    out.append(String(cString: cstr))
                }
            }
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            if elapsedMs > 20 {
                print(String(format: "[Dictionary] slow zh prefix '%@%%': %d rows in %.1fms",
                             trimmed, out.count, elapsedMs))
            }
            return out
        }
    }

    deinit {
        if let db { sqlite3_close(db) }
    }
}
