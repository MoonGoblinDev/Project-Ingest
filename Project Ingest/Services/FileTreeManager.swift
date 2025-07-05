//
//  FileTreeManager.swift
//  Project Ingest
//
//  Created by Bregas Satria Wicaksono on 05/07/25.
//

import Foundation

class FileTreeManager {
    
    func updateExclusionStates(for rootItem: FileItem, rootURL: URL, ignorePatterns: String) {
        let patterns = ignorePatterns.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.starts(with: "#") }
            .map { String($0) }
        
        recursivelyUpdateExclusion(for: rootItem, with: patterns, relativeTo: rootURL, isParentExcluded: false)
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
        
        // This must be on the main actor because it triggers UI updates
        DispatchQueue.main.async {
             item.isExcluded = isCurrentlyExcluded
        }
       
        if let children = item.children {
            for child in children {
                recursivelyUpdateExclusion(for: child, with: patterns, relativeTo: rootURL, isParentExcluded: item.isExcluded)
            }
        }
    }
}
