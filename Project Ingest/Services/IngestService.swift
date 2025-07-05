//
//  IngestService.swift
//  Project Ingest
//
//  Created by Bregas Satria Wicaksono on 05/07/25.
//

import Foundation

class IngestService {
    
    private let logHandler: (String) -> Void
    
    init(logHandler: @escaping (String) -> Void) {
        self.logHandler = logHandler
    }

    func ingestProject(
        rootItem: FileItem,
        rootURL: URL,
        includeStructure: Bool,
        progressUpdate: @escaping (Int, Int) async -> Void
    ) async throws -> String {
        let folderName = rootItem.name
        logHandler("Processing project: \(folderName)")
        
        let filesToProcess = self.collectFilesToProcess(from: [rootItem])
        let totalFiles = filesToProcess.count
        logHandler("Found \(totalFiles) files to process (after filtering).")
        
        // Initial progress update
        await progressUpdate(0, totalFiles)

        var result = "# Project: \(folderName)\n\n"
        
        if includeStructure {
            let treeString = generateFileTreeString(from: rootItem)
            if !treeString.isEmpty {
                result.append(treeString)
                logHandler("Added project structure to the output.")
            }
        }
        
        for (index, item) in filesToProcess.enumerated() {
            let fileURL = item.path
            let relativePath = fileURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
            
            do {
                let content = try String(contentsOf: fileURL, encoding: .utf8)
                logHandler("Processing (\(index+1)/\(totalFiles)): \(relativePath)")

                if content.contains("\0") {
                    logHandler("  -> Skipping binary file: \(relativePath)")
                    continue
                }
                
                let lang = fileURL.pathExtension
                result.append("---\n\n")
                result.append("**File:** `\(relativePath)`\n\n")
                result.append("```\(lang)\n")
                result.append(content)
                result.append("\n```\n\n")
                
            } catch {
                logHandler("  -> Could not read file \(relativePath): \(error.localizedDescription)")
            }
            
            // Update progress after processing each file
            await progressUpdate(index + 1, totalFiles)
        }
        
        return result
    }

    func collectFilesToProcess(from items: [FileItem]) -> [FileItem] {
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
    
    private func generateFileTreeString(from rootItem: FileItem) -> String {
        guard !rootItem.isExcluded else { return "" }
        
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
}
