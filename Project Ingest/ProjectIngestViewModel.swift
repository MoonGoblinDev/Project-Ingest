// ProjectIngestViewModel.swift

import SwiftUI
import Foundation

// Using the C library for gitignore-style pattern matching
import Darwin.C

@MainActor // Ensures all methods in this class run on the main thread by default
class ProjectIngestViewModel: ObservableObject {
    
    // MARK: - Published Properties (State for the UI)
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
            // When the ignorePatterns text changes, re-evaluate the entire tree's exclusion state.
            updateAllExclusionStates()
        }
    }
    
    @Published var ingestedContent: String = ""
    @Published var logMessages: String = ""
    
    @Published var isIngesting: Bool = false
    @Published var progressValue: Double = 0.0
    @Published var progressTotal: Double = 1.0
    
    // Token count and model selection
    @Published var ingestedTokenCount: Int = 0
    @Published var selectedModel: String = "gpt-4o" {
        didSet {
            if oldValue != selectedModel && sourceFolderURL != nil {
                log("Model changed to \(selectedModel). Recalculating token counts...")
                Task {
                    // Recalculate for the entire tree
                    for rootItem in self.fileTree {
                        await self.recursivelyUpdateTokenCounts(for: rootItem)
                    }
                    await MainActor.run {
                        self.log("Token recalculation complete.")
                    }
                }
            }
        }
    }
    let availableModels = ["gpt-4o", "gpt-4o-mini", "gpt-4", "gpt-3.5-turbo"]
    
    // NEW: State for including the project structure tree
    @Published var includeProjectStructure: Bool = false

    private var sourceFolderURL: URL?
    
    // MARK: - UI Actions
    
    func browseForFolder() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.title = "Select Source Folder"
        
        if openPanel.runModal() == .OK {
            if let url = openPanel.url {
                self.sourceFolderURL = url
                self.folderPath = url.path
                log("Selected folder: \(url.path)")
                populateFileTree(from: url)
            }
        }
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
        
        // --- MODIFIED: The patterns are no longer needed here ---
        // The fileTree on the MainActor is now the single source of truth.
        Task.detached(priority: .userInitiated) {
            await self.performIngest(folderURL: sourceURL)
        }
    }
    
    func copyToClipboard() {
        guard !ingestedContent.isEmpty else {
            log("⚠️ No content to copy.")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ingestedContent, forType: .string)
        log("✅ Content copied to clipboard.")
    }
    
    func saveToFile() {
        guard !ingestedContent.isEmpty else {
            log("⚠️ No content to save.")
            return
        }

        let savePanel = NSSavePanel()
        savePanel.title = "Save Ingested Content As..."
        savePanel.allowedContentTypes = [.markdown, .text]
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = "ingested-project.md"

        if savePanel.runModal() == .OK {
            if let url = savePanel.url {
                do {
                    try ingestedContent.write(to: url, atomically: true, encoding: .utf8)
                    log("✅ Content saved to \(url.path)")
                } catch {
                    log("❌ Error saving file: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Private Logic
    
    // --- NEW HELPER FUNCTION ---
    /// Recursively traverses the FileItem tree and collects all files that are not excluded.
    private func collectFilesToProcess(from items: [FileItem], relativeTo rootURL: URL) -> [(url: URL, relativePath: String)] {
        var files: [(url: URL, relativePath: String)] = []

        for item in items {
            // If the item itself (and thus all its children) is excluded, skip it entirely.
            if item.isExcluded {
                continue
            }

            if item.isFolder, let children = item.children {
                // If it's a folder, recurse into its children.
                files.append(contentsOf: collectFilesToProcess(from: children, relativeTo: rootURL))
            } else if !item.isFolder {
                // It's a non-excluded file. Add it to the list.
                let relativePath = item.path.path.replacingOccurrences(of: rootURL.path + "/", with: "")
                files.append((url: item.path, relativePath: relativePath))
            }
        }
        return files
    }
    
    // --- REWRITTEN INGESTION LOGIC ---
    private func performIngest(folderURL: URL) async {
        let folderName = folderURL.lastPathComponent
        await MainActor.run { log("Processing project: \(folderName)") }
        
        // Get a copy of the file tree from the main actor.
        // This is now our single source of truth for what to ingest.
        let tree = await MainActor.run { self.fileTree }
        
        await MainActor.run { log("Collecting files based on UI exclusion rules...") }
        
        // Use the new helper function to get the definitive list of files.
        let filesToProcess = collectFilesToProcess(from: tree, relativeTo: folderURL)
            // Sort to ensure a consistent output order
            .sorted { $0.relativePath < $1.relativePath }
        
        await MainActor.run {
            log("Found \(filesToProcess.count) files to process (after filtering).")
            self.progressTotal = Double(filesToProcess.count)
        }

        var result = "# Project: \(folderName)\n\n"
        
        // NEW: Add project structure if requested
        if await MainActor.run(body: { self.includeProjectStructure }) {
            let treeString = generateFileTreeString()
            if !treeString.isEmpty {
                result.append(treeString)
                await MainActor.run { log("Added project structure to the output.") }
            }
        }

        for (index, file) in filesToProcess.enumerated() {
            await MainActor.run { self.progressValue = Double(index + 1) }

            do {
                let content = try String(contentsOf: file.url, encoding: .utf8)
                await MainActor.run { log("Processing (\(index+1)/\(filesToProcess.count)): \(file.relativePath)") }

                if content.contains("\0") {
                    await MainActor.run { log("  -> Skipping binary file: \(file.relativePath)") }
                    continue
                }
                
                let lang = file.url.pathExtension
                result.append("---\n\n")
                result.append("**File:** `\(file.relativePath)`\n\n")
                result.append("```\(lang)\n")
                result.append(content)
                result.append("\n```\n\n")
                
            } catch {
                await MainActor.run { log("  -> Could not read file \(file.relativePath): \(error.localizedDescription)") }
            }
        }
        
        let finalTokenCount = try? await getTokenCount(for: result, model: self.selectedModel)
        
        await MainActor.run {
            self.ingestedContent = result
            self.ingestedTokenCount = finalTokenCount ?? 0
            self.isIngesting = false
            self.progressValue = self.progressTotal
            log("✅ Ingestion complete! Content is ready.")
        }
    }
    
    private func populateFileTree(from url: URL) {
        Task.detached(priority: .userInitiated) {
            let rootItem = FileItem(url: url)
            await self.buildTree(for: rootItem, relativeTo: url)
            
            await MainActor.run {
                self.fileTree = [rootItem]
                self.log("File tree populated.")
                self.updateAllExclusionStates()
            }
            
            await self.recursivelyUpdateTokenCounts(for: rootItem)
            await MainActor.run {
                self.log("Initial token calculation complete.")
            }
        }
    }
    
    private func buildTree(for parentItem: FileItem, relativeTo rootURL: URL) {
        let fullRootPath = rootURL.path
        
        if parentItem.path.path == fullRootPath {
            parentItem.ignorePattern = ""
        } else {
            let relativePath = parentItem.path.path.replacingOccurrences(of: fullRootPath + "/", with: "")
            parentItem.ignorePattern = parentItem.isFolder ? "\(relativePath)/" : String(relativePath)
        }
        
        guard parentItem.isFolder else { return }
        
        do {
            let childURLs = try FileManager.default.contentsOfDirectory(at: parentItem.path, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            
            for url in childURLs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let childItem = FileItem(url: url)
                parentItem.children?.append(childItem)
                buildTree(for: childItem, relativeTo: rootURL)
            }
        } catch {
            let message = "Error reading directory \(parentItem.path): \(error.localizedDescription)"
            Task { await MainActor.run { self.log(message) } }
        }
    }
    
    private func updateAllExclusionStates() {
        guard let rootURL = self.sourceFolderURL else { return }
        
        let patterns = self.ignorePatterns.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.starts(with: "#") }
            .map { String($0) }
        
        for item in fileTree {
            recursivelyUpdateExclusion(for: item, with: patterns, relativeTo: rootURL, isParentExcluded: false)
        }
    }
    
    private func recursivelyUpdateExclusion(for item: FileItem, with patterns: [String], relativeTo rootURL: URL, isParentExcluded: Bool) {
        var isCurrentlyExcluded = isParentExcluded
        
        if !isCurrentlyExcluded {
            let relativePath = item.path.path.replacingOccurrences(of: rootURL.path + "/", with: "")
            for pattern in patterns {
                let flags = FNM_PATHNAME | FNM_LEADING_DIR
                let pathToCheck = item.isFolder ? (relativePath + "/") : relativePath
                if pathToCheck.hasPrefix(pattern) || fnmatch(pattern, relativePath, flags) == 0 {
                    isCurrentlyExcluded = true
                    break
                }
            }
        }
        
        item.isExcluded = isCurrentlyExcluded
        
        if let children = item.children {
            for child in children {
                recursivelyUpdateExclusion(for: child, with: patterns, relativeTo: rootURL, isParentExcluded: item.isExcluded)
            }
        }
    }
    
    private func recursivelyUpdateTokenCounts(for item: FileItem) async {
        if item.isFolder {
            if let children = item.children {
                await withTaskGroup(of: Void.self) { group in
                    for child in children {
                        group.addTask {
                            await self.recursivelyUpdateTokenCounts(for: child)
                        }
                    }
                }
            }
        } else {
            let count = await getTokenCountForFile(at: item.path)
            await MainActor.run {
                item.tokenCount = count
            }
        }
    }

    private func getTokenCountForFile(at url: URL) async -> Int {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return 0
        }
        if content.contains("\0") {
            return 0
        }
        do {
            return try await getTokenCount(for: content, model: self.selectedModel)
        } catch {
            await MainActor.run {
                self.log("⚠️ Could not count tokens for \(url.lastPathComponent): \(error.localizedDescription)")
            }
            return 0
        }
    }
    
    // NEW: Function to generate the file tree string
    private func generateFileTreeString() -> String {
        guard let rootItem = fileTree.first else { return "" }
        
        // Although the root cannot be excluded via UI, this is a safe check.
        if rootItem.isExcluded { return "" }
        
        var structure = "**Project Structure:**\n\n"
        structure += "```\n"
        structure += "\(rootItem.name)\n"
        
        if let children = rootItem.children {
            structure += generateTreeRecursive(from: children, prefix: "")
        }
        
        structure += "```\n\n"
        return structure
    }

    // NEW: Recursive helper for the file tree string generation
    private func generateTreeRecursive(from items: [FileItem], prefix: String) -> String {
        var result = ""
        // Filter out excluded items to correctly determine the last item for connector characters
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
