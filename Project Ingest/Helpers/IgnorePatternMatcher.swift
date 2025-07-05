//
//  IgnorePatternMatcher.swift
//  Project Ingest
//
//  Created by Bregas Satria Wicaksono on 04/07/25.
//

import Foundation
import Darwin.C

/// A helper struct to perform gitignore-style pattern matching.
struct IgnorePatternMatcher {
    
    /// Checks if a given relative path matches any of the gitignore-style patterns.
    /// - Parameters:
    ///   - relativePath: The path of the file or folder relative to the project root.
    ///   - isFolder: A boolean indicating if the path is for a folder.
    ///   - patterns: An array of gitignore-style patterns.
    /// - Returns: `true` if the path matches a pattern, `false` otherwise.
    static func isPathExcluded(relativePath: String, isFolder: Bool, by patterns: [String]) -> Bool {
        for pattern in patterns {
            let flags = FNM_PATHNAME | FNM_LEADING_DIR
            
            let pathToCheck = isFolder ? (relativePath + "/") : relativePath
            if pathToCheck.hasPrefix(pattern) {
                return true
            }

            if fnmatch(pattern, relativePath, flags) == 0 {
                return true
            }
        }
        return false
    }
}
