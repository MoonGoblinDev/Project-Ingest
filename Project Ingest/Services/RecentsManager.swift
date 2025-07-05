//
//  RecentsManager.swift
//  Project Ingest
//
//  Created by Bregas Satria Wicaksono on 05/07/25.
//

import Foundation

// The data model for a recent folder.
struct RecentFolder: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let bookmarkData: Data
    var name: String {
        url.lastPathComponent
    }

    // Custom Hashable conformance
    static func == (lhs: RecentFolder, rhs: RecentFolder) -> Bool {
        lhs.url == rhs.url
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}

class RecentsManager {
    private let recentFoldersKey = "recentFoldersBookmarkData"
    private let maxRecentsCount = 10
    
    private(set) var recentFolders: [RecentFolder] = []
    
    private let logHandler: (String) -> Void
    
    init(logHandler: @escaping (String) -> Void) {
        self.logHandler = logHandler
        loadRecents()
    }

    func loadRecents() {
        logHandler("Loading saved settings...")
        guard let savedBookmarks = UserDefaults.standard.array(forKey: recentFoldersKey) as? [Data] else {
            logHandler("No recent folders found.")
            return
        }

        var loadedRecents: [RecentFolder] = []
        for bookmarkData in savedBookmarks {
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
                loadedRecents.append(RecentFolder(url: url, bookmarkData: bookmarkData))
            } catch {
                logHandler("Could not resolve a recent folder bookmark during initial load. It may be invalid. Skipping.")
            }
        }
        self.recentFolders = loadedRecents
        logHandler("Loaded \(loadedRecents.count) recent folders.")
    }

    func add(url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)

            // Remove existing entry for the same URL, if any.
            recentFolders.removeAll { $0.url == url }

            let newRecent = RecentFolder(url: url, bookmarkData: bookmarkData)
            recentFolders.insert(newRecent, at: 0)

            if recentFolders.count > maxRecentsCount {
                recentFolders = Array(recentFolders.prefix(maxRecentsCount))
            }

            saveRecents()
        } catch {
            logHandler("⚠️ Could not create bookmark for \(url.path): \(error.localizedDescription)")
        }
    }
    
    func refreshBookmark(for url: URL) {
        // This is essentially the same as adding it again, which creates a new bookmark.
        add(url: url)
    }

    func moveToTop(_ recent: RecentFolder) {
        recentFolders.removeAll { $0 == recent }
        recentFolders.insert(recent, at: 0)
        saveRecents()
    }

    func remove(url: URL) {
        recentFolders.removeAll { $0.url == url }
        saveRecents()
    }

    func clear() {
        recentFolders.removeAll()
        UserDefaults.standard.removeObject(forKey: recentFoldersKey)
        logHandler("Cleared all recent folders.")
    }

    private func saveRecents() {
        let bookmarksToSave = recentFolders.map { $0.bookmarkData }
        UserDefaults.standard.set(bookmarksToSave, forKey: recentFoldersKey)
    }
}
