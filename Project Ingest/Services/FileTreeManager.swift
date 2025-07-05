//
//  FileTreeManager.swift
//  Project Ingest
//
//  Created by Bregas Satria Wicaksono on 05/07/25.
//

import Foundation

class FileTreeManager {
    
    /// Updates the exclusion state of all items in the tree based on both exclude and include patterns.
    /// - Parameters:
    ///   - rootItem: The root of the file tree.
    ///   - rootURL: The URL of the project's root folder.
    ///   - ignorePatterns: Newline-separated gitignore-style patterns for exclusion.
    ///   - includePatterns: Newline-separated gitignore-style patterns for inclusion.
    func updateExclusionStates(for rootItem: FileItem, rootURL: URL, ignorePatterns: String, includePatterns: String) {
        let excludePatternsArray = ignorePatterns.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.starts(with: "#") }
            .map { String($0) }
        
        let includePatternsArray = includePatterns.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.starts(with: "#") }
            .map { String($0) }
        
        // Start the recursive process. The return value is not needed at the top level.
        _ = recursivelyUpdateExclusion(for: rootItem, with: excludePatternsArray, and: includePatternsArray, relativeTo: rootURL)
    }
    
    /// Recursively updates the exclusion state and returns `true` if the item or any of its children are included.
    /// This post-order traversal allows a parent folder's state to be determined by its children's states.
    /// - Returns: `true` if the item should be visible (i.e., not excluded), `false` otherwise.
    private func recursivelyUpdateExclusion(for item: FileItem, with excludePatterns: [String], and includePatterns: [String], relativeTo rootURL: URL) -> Bool {
        var basePath = rootURL.path
        if !basePath.hasSuffix("/") {
            basePath += "/"
        }
        let relativePath = item.path.path.replacingOccurrences(of: basePath, with: "")
        
        // FIX: Special handling for the root item. It is the container and should never be excluded itself.
        // Its visibility is guaranteed; we only determine the visibility of its children.
        if relativePath.isEmpty {
            DispatchQueue.main.async { item.isExcluded = false }
            if let children = item.children {
                for child in children {
                    // Recurse on children to set their state, but we don't need the return value here.
                    _ = recursivelyUpdateExclusion(for: child, with: excludePatterns, and: includePatterns, relativeTo: rootURL)
                }
            }
            return true // The root container is always "kept".
        }
        
        // 1. Check exclude patterns first. They have the highest precedence.
        if IgnorePatternMatcher.isPathExcluded(relativePath: relativePath, isFolder: item.isFolder, by: excludePatterns) {
            forceExclude(item: item) // Mark this item and all descendants as excluded.
            return false // This item and its subtree are pruned.
        }

        // 2. If include patterns are not provided, everything not explicitly excluded is included.
        if includePatterns.isEmpty {
            DispatchQueue.main.async { item.isExcluded = false }
            if let children = item.children {
                for child in children {
                    // We still need to recurse to check children against exclude patterns.
                    _ = recursivelyUpdateExclusion(for: child, with: excludePatterns, and: includePatterns, relativeTo: rootURL)
                }
            }
            return true // This item is kept.
        }
        
        // 3. Include patterns ARE provided. An item must be explicitly included to be kept.
        if item.isFolder {
            // For a folder, it's kept if at least one of its children is kept.
            guard let children = item.children, !children.isEmpty else {
                DispatchQueue.main.async { item.isExcluded = true } // Exclude empty folders
                return false
            }
            
            var hasIncludedChild = false
            for child in children {
                // If any child is kept, the parent folder should also be kept.
                if recursivelyUpdateExclusion(for: child, with: excludePatterns, and: includePatterns, relativeTo: rootURL) {
                    hasIncludedChild = true
                }
            }
            
            DispatchQueue.main.async { item.isExcluded = !hasIncludedChild }
            return hasIncludedChild
        } else {
            // For a file, it must match an include pattern to be kept.
            let isIncluded = IgnorePatternMatcher.isPathExcluded(relativePath: relativePath, isFolder: false, by: includePatterns)
            DispatchQueue.main.async { item.isExcluded = !isIncluded }
            return isIncluded
        }
    }
    
    /// Helper to recursively mark an item and all its children as excluded on the main thread.
    private func forceExclude(item: FileItem) {
        DispatchQueue.main.async { item.isExcluded = true }
        if let children = item.children {
            for child in children {
                forceExclude(item: child)
            }
        }
    }
}
