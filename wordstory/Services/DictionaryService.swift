import Foundation
import SQLite3

/// Offline ECDICT lookup. The database lives at `Resources/ecdict.db` in the
/// app bundle (~40 MB, ~770k English headwords, Traditional Chinese
/// translations). English-headword indexed only — Chinese → English lookups
/// return nil and the caller falls through to the online endpoint.
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
    func lookup(_ word: String, direction: LanguageDirection) -> Hit? {
        // ECDICT is English-headword indexed; zh-to-en lookups always miss.
        guard direction == .enToZh else { return nil }

        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

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

    deinit {
        if let db { sqlite3_close(db) }
    }
}
