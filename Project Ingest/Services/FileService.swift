//
//  FileService.swift
//  Project Ingest
//
//  Created by Bregas Satria Wicaksono on 04/07/25.
//

import SwiftUI
import UniformTypeIdentifiers

/// A service class for handling file system interactions like opening dialogs and building file trees.
class FileService {

    /// Presents a system open panel to allow the user to select a single directory.
    /// - Returns: The `URL` of the selected folder, or `nil` if the user cancels.
    func selectFolder() -> URL? {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.title = "Select Source Folder"
        
        if openPanel.runModal() == .OK {
            return openPanel.url
        }
        return nil
    }

    /// Recursively builds a file tree structure from a given root URL using a security-scope-aware enumerator.
    /// - Parameter rootURL: The starting URL of the directory to scan. Must be a security-scoped URL if outside the sandbox.
    /// - Returns: A `FileItem` representing the root of the scanned directory tree.
    func buildFileTree(from rootURL: URL) -> FileItem {
        let rootItem = FileItem(url: rootURL)
        let fileManager = FileManager.default
        
        // Use an enumerator to get all descendant URLs. These URLs inherit the security scope from rootURL.
        // This is the correct way to traverse a sandboxed directory.
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
            options: [.skipsHiddenFiles],
            errorHandler: { url, error -> Bool in
                print("Enumerator error at \(url.path): \(error.localizedDescription)")
                return true
            }
        ) else {
            print("Failed to create file enumerator for \(rootURL.path). Check permissions.")
            return rootItem
        }

        var pathToItemMap: [URL: FileItem] = [rootURL: rootItem]

        // Prepare a base path for creating relative paths. Ensure it ends with a slash.
        var basePath = rootURL.path
        if !basePath.hasSuffix("/") {
            basePath += "/"
        }
        
        // Iterate over all the files and folders provided by the enumerator.
        for case let fileURL as URL in enumerator {
            let parentURL = fileURL.deletingLastPathComponent()
            guard let parentItem = pathToItemMap[parentURL] else {
                print("Warning: Could not find parent for \(fileURL.path). Skipping.")
                continue
            }

            let newItem = FileItem(url: fileURL)
            
            newItem.parent = parentItem
            
            let relativePath = fileURL.path.replacingOccurrences(of: basePath, with: "")
            newItem.ignorePattern = newItem.isFolder ? "\(relativePath)/" : String(relativePath)

            parentItem.children?.append(newItem)
            
            if newItem.isFolder {
                pathToItemMap[fileURL] = newItem
            }
        }
        
        for item in pathToItemMap.values {
            item.children?.sort(by: { $0.name < $1.name })
        }

        return rootItem
    }
    
    /// Presents a system save panel to allow the user to save content to a file.
    /// - Parameters:
    ///   - content: The string content to save.
    ///   - suggestedName: The default file name to show in the save panel.
    /// - Throws: An `AppError.fileSaveFailed` if the write operation fails.
    func save(content: String, suggestedName: String) throws {
        let savePanel = NSSavePanel()
        savePanel.title = "Save Ingested Content As..."
        savePanel.allowedContentTypes = [.markdown, .text]
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = suggestedName

        guard savePanel.runModal() == .OK, let url = savePanel.url else {
            return
        }
        
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            // Propagate the error to the ViewModel to show an alert.
            print("Error saving file: \(error.localizedDescription)")
            throw AppError.fileSaveFailed(error)
        }
    }
}
