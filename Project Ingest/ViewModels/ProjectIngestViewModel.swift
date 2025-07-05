//
//  ProjectIngestViewModel.swift
//  Project Ingest
//
//  Created by Bregas Satria Wicaksono on 04/07/25.
//

import SwiftUI
import Foundation


@MainActor
class ProjectIngestViewModel: ObservableObject {
    
    // MARK: - Recents Data Structure
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
    
    // MARK: - UserDefaults Keys
    private let recentFoldersKey = "recentFoldersBookmarkData"
    private let lastIgnorePatternsKey = "lastIgnorePatterns"
    private let maxRecentsCount = 10
    
    // MARK: - Published Properties (UI State)
    @Published var folderPath: String = "No Folder Selected"
    @Published var fileTree: [FileItem] = []
    @Published var ignorePatterns: String = """
    # Exclude files/folders
    .git/
    *.pyc
    __pycache__/
    *.entitlements
    Resources/
    *.xcodeproj/
    *.scn
    *.dae
    *.scnassets/
    *.xcassets/
    *.lproj/
    .DS_Store
    """ {
        didSet {
            // Save the patterns whenever they are changed.
            if let url = sourceFolderURL {
                let key = lastIgnorePatternsKey + "-\(url.path.hashValue)"
                UserDefaults.standard.set(ignorePatterns, forKey: key)
            }
            updateAllExclusionStates()
            clearIngestedContent()
        }
    }
    
    @Published var ingestedContent: String = ""
    @Published var logMessages: String = ""
    
    @Published var isIngesting: Bool = false
    @Published var progressValue: Double = 0.0
    @Published var progressTotal: Double = 1.0
    
    @Published var ingestedTokenCount: Int = 0
    
    @Published var selectedModel: String = "gpt-4o"
    
    @Published var includeProjectStructure: Bool = false {
        didSet {
            clearIngestedContent()
        }
    }
    
    @Published var recentFolders: [RecentFolder] = []
    
    // NEW: Published property for presenting alerts
    @Published var currentError: AppError?


    // MARK: - Private Properties
    private var sourceFolderURL: URL?
    /// This property holds the URL that currently has an active security scope.
    private var activeScopedURL: URL?
    /// The service for handling file system interactions.
    private let fileService = FileService()


    // MARK: - Initialization
    init() {
        // Only perform lightweight setup here. Load the list of recents but don't access the file system yet.
        loadRecentsFromUserDefaults()
    }
    
    // MARK: - UI Actions
    
    /// Called by the view's .onAppear to trigger the initial folder load.
    func loadInitialFolder() {
        if let mostRecent = recentFolders.first, sourceFolderURL == nil {
            selectRecentFolder(mostRecent)
        }
    }
    
    func browseForFolder() {
        guard let url = fileService.selectFolder() else { return }
        addFolderToRecents(url)
        
        Task {
            await loadFolder(url: url, isFromBookmark: false)
        }
    }
    
    func selectRecentFolder(_ recent: RecentFolder) {
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: recent.bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            
            if isStale {
                log("Bookmark for \(recent.name) is stale. It will be refreshed upon gaining access.")
            }
            
            moveRecentToTop(recent)
            Task {
                await loadFolder(url: url, isFromBookmark: true, isStale: isStale)
            }
            
        } catch {
            let appError = AppError.bookmarkResolutionFailed(error)
            log("⚠️ Error resolving bookmark for \(recent.name): \(error.localizedDescription). Removing from recents.")
            self.currentError = appError
            removeRecentFolder(basedOn: recent.url)
        }
    }
    
    func clearRecents() {
        recentFolders.removeAll()
        UserDefaults.standard.removeObject(forKey: recentFoldersKey)
        log("Cleared all recent folders.")
    }
    
    func toggleExclusion(for item: FileItem) {
        guard item.id != self.fileTree.first?.id else {
            log("⚠️ Cannot exclude the root project folder.")
            return
        }

        let patternToToggle = item.ignorePattern
        
        var currentPatterns = self.ignorePatterns
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        
        if currentPatterns.contains(patternToToggle) {
            currentPatterns.removeAll { $0 == patternToToggle }
            self.ignorePatterns = currentPatterns.joined(separator: "\n")
            log("Included '\(patternToToggle)'")
        } else {
            self.ignorePatterns.append("\n\(patternToToggle)")
            log("Excluded '\(patternToToggle)'")
        }
    }
    
    func startIngest() {
        guard let sourceURL = sourceFolderURL else {
            log("Error: Please select a source folder first.")
            return
        }

        isIngesting = true
        ingestedContent = ""
        ingestedTokenCount = 0
        logMessages = ""
        progressValue = 0
        progressTotal = 1
        log("Starting ingest...")
        
        // Use a regular Task, not .detached, to inherit actor context and priority.
        Task {
            await self.performIngest(folderURL: sourceURL)
        }
    }
    
    func copyToClipboard() -> Bool {
        guard !ingestedContent.isEmpty else {
            log("⚠️ No content to copy.")
            return false
        }
        ClipboardService.copy(text: ingestedContent)
        log("✅ Content copied to clipboard.")
        return true
    }
    
    func saveToFile() {
        guard !ingestedContent.isEmpty else {
            log("⚠️ No content to save.")
            return
        }

        do {
            try fileService.save(content: ingestedContent, suggestedName: "ingested-project.md")
            log("✅ Content saved successfully.")
        } catch let error as AppError {
            self.currentError = error
            log("Save operation failed: \(error.localizedDescription)")
        } catch {
             // Catch any other unexpected errors
            self.currentError = .fileSaveFailed(error)
            log("An unexpected error occurred during save: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Helper Methods

    private func clearIngestedContent() {
        if !ingestedContent.isEmpty {
            ingestedContent = ""
            ingestedTokenCount = 0
            log("Project settings changed. Please re-ingest for updated output.")
        }
    }
    
    private func loadRecentsFromUserDefaults() {
        log("Loading saved settings...")
        guard let savedBookmarks = UserDefaults.standard.array(forKey: recentFoldersKey) as? [Data] else {
            log("No recent folders found.")
            return
        }
        
        var loadedRecents: [RecentFolder] = []
        for bookmarkData in savedBookmarks {
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
                loadedRecents.append(RecentFolder(url: url, bookmarkData: bookmarkData))
            } catch {
                log("Could not resolve a recent folder bookmark during initial load. It may be invalid. Skipping.")
            }
        }
        self.recentFolders = loadedRecents
        log("Loaded \(loadedRecents.count) recent folders.")
    }
    
    private func addFolderToRecents(_ url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            
            var updatedRecents = self.recentFolders
            updatedRecents.removeAll { $0.url == url }
            
            let newRecent = RecentFolder(url: url, bookmarkData: bookmarkData)
            updatedRecents.insert(newRecent, at: 0)
            
            if updatedRecents.count > maxRecentsCount {
                updatedRecents = Array(updatedRecents.prefix(maxRecentsCount))
            }
            
            self.recentFolders = updatedRecents
            
            let bookmarksToSave = updatedRecents.map { $0.bookmarkData }
            UserDefaults.standard.set(bookmarksToSave, forKey: recentFoldersKey)
            
        } catch {
            log("⚠️ Could not create bookmark for \(url.path): \(error.localizedDescription)")
            // This is a non-critical error, so we just log it.
        }
    }
    
    private func moveRecentToTop(_ recent: RecentFolder) {
        var updatedRecents = self.recentFolders
        updatedRecents.removeAll { $0 == recent }
        updatedRecents.insert(recent, at: 0)
        self.recentFolders = updatedRecents
        
        let bookmarksToSave = updatedRecents.map { $0.bookmarkData }
        UserDefaults.standard.set(bookmarksToSave, forKey: recentFoldersKey)
    }

    
    private func removeRecentFolder(basedOn url: URL) {
        recentFolders.removeAll { $0.url == url }
        let bookmarksToSave = recentFolders.map { $0.bookmarkData }
        UserDefaults.standard.set(bookmarksToSave, forKey: recentFoldersKey)
    }
    
    /// The centralized function to handle loading a folder and managing its security scope.
    private func loadFolder(url: URL, isFromBookmark: Bool, isStale: Bool = false) async {
        // 1. Stop access to any previously active folder.
        activeScopedURL?.stopAccessingSecurityScopedResource()
        activeScopedURL = nil
        log("Released access to previous folder if any.")
        
        var accessGranted = false
        if isFromBookmark {
            // 2. Gain security access for the new folder.
            accessGranted = url.startAccessingSecurityScopedResource()
        } else {
            // Access from NSOpenPanel is granted for the session.
            accessGranted = true
        }
        
        guard accessGranted else {
            log("⛔️ Could not gain access to \(url.lastPathComponent). Please re-select it using 'Browse...'.")
            self.currentError = .folderAccessFailed(url)
            removeRecentFolder(basedOn: url)
            return
        }
        
        // 3. If access was granted, store this as the currently active URL.
        if isFromBookmark {
            self.activeScopedURL = url
            log("Security access GRANTED for \(url.lastPathComponent).")
        }

        // 4. If the bookmark was stale, refresh it now that we have access.
        if isStale {
            log("Refreshing stale bookmark...")
            addFolderToRecents(url)
        }
        
        // 5. With access active, populate the file tree.
        await self.populateFileTree(for: url)
    }
    
    /// This async function performs the file system scan. It assumes security scope is already active.
    private func populateFileTree(for url: URL) async {
        self.clearIngestedContent()
        self.sourceFolderURL = url
        self.folderPath = url.path
        
        let key = self.lastIgnorePatternsKey + "-\(url.path.hashValue)"
        if let savedPatterns = UserDefaults.standard.string(forKey: key) {
            self.ignorePatterns = savedPatterns
            self.log("Loaded ignore patterns for '\(url.lastPathComponent)'.")
        }
        log("Loading folder contents: \(url.path)")
        
        let rootItem = self.fileService.buildFileTree(from: url)
        
        self.fileTree = [rootItem]
        self.log("File tree populated.")
        self.updateAllExclusionStates()

        if rootItem.children?.isEmpty == false {
            await self.recursivelyUpdateTokenCounts(for: rootItem)
            self.log("Initial token calculation complete.")
        }
    }
    
    private func performIngest(folderURL: URL) async {
        let folderName = folderURL.lastPathComponent
        log("Processing project: \(folderName)")
        
        let filesToProcess = self.collectFilesToProcess(from: self.fileTree)
        
        log("Found \(filesToProcess.count) files to process (after filtering).")
        self.progressTotal = Double(filesToProcess.count)

        var result = "# Project: \(folderName)\n\n"
        
        if self.includeProjectStructure {
            let treeString = generateFileTreeString()
            if !treeString.isEmpty {
                result.append(treeString)
                log("Added project structure to the output.")
            }
        }

        for (index, item) in filesToProcess.enumerated() {
            self.progressValue = Double(index + 1)

            let fileURL = item.path
            let relativePath = fileURL.path.replacingOccurrences(of: folderURL.path + "/", with: "")
            
            do {
                let content = try String(contentsOf: fileURL, encoding: .utf8)
                log("Processing (\(index+1)/\(filesToProcess.count)): \(relativePath)")

                if content.contains("\0") {
                    log("  -> Skipping binary file: \(relativePath)")
                    continue
                }
                
                let lang = fileURL.pathExtension
                result.append("---\n\n")
                result.append("**File:** `\(relativePath)`\n\n")
                result.append("```\(lang)\n")
                result.append(content)
                result.append("\n```\n\n")
                
            } catch {
                log("  -> Could not read file \(relativePath): \(error.localizedDescription)")
            }
        }
        
        let finalTokenCount = try? await getTokenCount(for: result, model: self.selectedModel)
        
        self.ingestedContent = result
        self.ingestedTokenCount = finalTokenCount ?? 0
        self.isIngesting = false
        self.progressValue = self.progressTotal
        log("✅ Ingestion complete! Content is ready.")
    }
    
    private func updateAllExclusionStates() {
        guard let rootURL = self.sourceFolderURL, !fileTree.isEmpty else { return }
        
        let patterns = self.ignorePatterns.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.starts(with: "#") }
            .map { String($0) }
        
        recursivelyUpdateExclusion(for: fileTree[0], with: patterns, relativeTo: rootURL, isParentExcluded: false)
    }
    
    private func recursivelyUpdateExclusion(for item: FileItem, with patterns: [String], relativeTo rootURL: URL, isParentExcluded: Bool) {
        var isCurrentlyExcluded = isParentExcluded
        
        if !isCurrentlyExcluded {
            // Prepare a base path for creating relative paths. Ensure it ends with a slash.
            var basePath = rootURL.path
            if !basePath.hasSuffix("/") {
                basePath += "/"
            }
            let relativePath = item.path.path.replacingOccurrences(of: basePath, with: "")
            
            isCurrentlyExcluded = IgnorePatternMatcher.isPathExcluded(
                relativePath: relativePath,
                isFolder: item.isFolder,
                by: patterns
            )
        }
        
        item.isExcluded = isCurrentlyExcluded
        
        if let children = item.children {
            for child in children {
                recursivelyUpdateExclusion(for: child, with: patterns, relativeTo: rootURL, isParentExcluded: item.isExcluded)
            }
        }
    }
    
    private func recalculateAllTokenCounts() {
        guard !fileTree.isEmpty else { return }
        Task {
            await recursivelyUpdateTokenCounts(for: self.fileTree[0])
            self.log("Token recalculation complete.")
        }
    }
    
    private func recursivelyUpdateTokenCounts(for item: FileItem) async {
        if item.isFolder, let children = item.children {
            await withTaskGroup(of: Void.self) { group in
                for child in children {
                    group.addTask {
                        await self.recursivelyUpdateTokenCounts(for: child)
                    }
                }
            }
        } else if !item.isFolder {
            let count = await getTokenCountForFile(at: item.path)
            await MainActor.run {
                item.tokenCount = count
            }
        }
    }

    private func getTokenCountForFile(at url: URL) async -> Int {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            guard !content.contains("\0") else { return 0 }
            return try await getTokenCount(for: content, model: self.selectedModel)
        } catch {
             await MainActor.run {
                self.log("⚠️ Could not count tokens for \(url.lastPathComponent): \(error.localizedDescription)")
            }
            return 0
        }
    }
    
    private func collectFilesToProcess(from items: [FileItem]) -> [FileItem] {
        var files: [FileItem] = []
        for item in items {
            if item.isExcluded { continue }

            if item.isFolder, let children = item.children {
                files.append(contentsOf: collectFilesToProcess(from: children))
            } else if !item.isFolder {
                files.append(item)
            }
        }
        return files.sorted(by: { $0.path.path < $1.path.path })
    }
    
    private func generateFileTreeString() -> String {
        guard let rootItem = fileTree.first, !rootItem.isExcluded else { return "" }
        
        var structure = "**Project Structure:**\n\n"
        structure += "```\n"
        structure += "\(rootItem.name)\n"
        
        if let children = rootItem.children {
            structure += generateTreeRecursive(from: children, prefix: "")
        }
        
        structure += "```\n\n"
        return structure
    }

    private func generateTreeRecursive(from items: [FileItem], prefix: String) -> String {
        var result = ""
        let visibleItems = items.filter { !$0.isExcluded }
        
        for (index, item) in visibleItems.enumerated() {
            let isLast = index == visibleItems.count - 1
            let connector = isLast ? "└── " : "├── "
            
            result += prefix + connector + item.name + "\n"
            
            if item.isFolder, let children = item.children {
                let newPrefix = prefix + (isLast ? "    " : "│   ")
                result += generateTreeRecursive(from: children, prefix: newPrefix)
            }
        }
        return result
    }

    private func log(_ message: String) {
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        logMessages.append("[\(timestamp)] \(message)\n")
    }
}
