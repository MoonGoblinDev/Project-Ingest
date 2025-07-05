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
    
    @Published var selectedModel: String = "gpt-4o" {
        didSet {
            // If the model changes and a folder is loaded, recalculate all tokens.
            if oldValue != selectedModel, let rootItem = fileTree.first {
                log("Model changed to \(selectedModel). Recalculating all token counts.")
                Task {
                    // Reset all counts to the .idle state
                    await resetAllTokenStates(for: rootItem)
                    // Start the new calculation
                    await tokenizationService.calculateTokensForAllItems(in: rootItem, model: selectedModel)
                }
            }
        }
    }
    
    @Published var includeProjectStructure: Bool = false {
        didSet {
            clearIngestedContent()
        }
    }
    
    @Published var recentFolders: [RecentFolder] = []
    @Published var currentError: AppError?


    // MARK: - Private Properties
    private var sourceFolderURL: URL?
    /// This property holds the URL that currently has an active security scope.
    private var activeScopedURL: URL?
    private let lastIgnorePatternsKey = "lastIgnorePatterns"
    
    // MARK: - Services
    private let fileService = FileService()
    private let fileTreeManager = FileTreeManager()
    private lazy var recentsManager = RecentsManager(logHandler: { [weak self] in self?.log($0) })
    private lazy var ingestService = IngestService(logHandler: { [weak self] in self?.log($0) })
    private lazy var tokenizationService = TokenizationService(logHandler: { [weak self] in self?.log($0) })


    // MARK: - Initialization
    init() {
        // Load recents and update the published property.
        self.recentFolders = recentsManager.recentFolders
    }
    
    // MARK: - UI Actions
    
    /// Called by the view's .onAppear to trigger the initial folder load.
    func loadInitialFolder() {
        if let mostRecent = recentsManager.recentFolders.first, sourceFolderURL == nil {
            selectRecentFolder(mostRecent)
        }
    }
    
    func browseForFolder() {
        guard let url = fileService.selectFolder() else { return }
        recentsManager.add(url: url)
        self.recentFolders = recentsManager.recentFolders
        
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
            
            recentsManager.moveToTop(recent)
            self.recentFolders = recentsManager.recentFolders
            
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
        recentsManager.clear()
        self.recentFolders = recentsManager.recentFolders
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
        guard let sourceURL = sourceFolderURL, let rootItem = fileTree.first else {
            log("Error: Please select a source folder first.")
            return
        }

        isIngesting = true
        ingestedContent = ""
        ingestedTokenCount = 0
        logMessages = ""
        log("Starting ingest...")
        
        Task {
            do {
                let content = try await ingestService.ingestProject(
                    rootItem: rootItem,
                    rootURL: sourceURL,
                    includeStructure: self.includeProjectStructure,
                    progressUpdate: { [weak self] current, total async in
                        // This closure is now async, and because the ViewModel is a MainActor,
                        // these property updates are safely published on the main thread.
                        self?.progressValue = Double(current)
                        self?.progressTotal = Double(total)
                    }
                )
                
                let finalTokenCount = try? await getTokenCount(for: content, model: self.selectedModel)
                
                self.ingestedContent = content
                self.ingestedTokenCount = finalTokenCount ?? 0
                log("✅ Ingestion complete! Content is ready.")
                
            } catch {
                log("❌ Ingestion failed: \(error.localizedDescription)")
            }
            
            self.isIngesting = false
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
    
    private func removeRecentFolder(basedOn url: URL) {
        recentsManager.remove(url: url)
        self.recentFolders = recentsManager.recentFolders
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
            recentsManager.refreshBookmark(for: url)
            self.recentFolders = recentsManager.recentFolders
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
            await self.tokenizationService.calculateTokensForAllItems(in: rootItem, model: selectedModel)
        }
    }
    
    private func updateAllExclusionStates() {
        guard let rootItem = self.fileTree.first, let rootURL = self.sourceFolderURL else { return }
        
        fileTreeManager.updateExclusionStates(for: rootItem, rootURL: rootURL, ignorePatterns: ignorePatterns)
    }
    
    /// REVAMPED: Recursively sets the token state of an item and its children back to .idle.
    private func resetAllTokenStates(for item: FileItem) async {
        // This must be on the MainActor because it modifies a published property.
        item.tokenState = .idle
        
        if item.isFolder, let children = item.children {
            // Concurrently reset children.
            await withTaskGroup(of: Void.self) { group in
                for child in children {
                    group.addTask {
                        await self.resetAllTokenStates(for: child)
                    }
                }
            }
        }
    }

    private func log(_ message: String) {
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        logMessages.append("[\(timestamp)] \(message)\n")
    }
}
