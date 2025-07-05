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
        // Use URL to reliably get the last path component (the basename).
        let pathBasename = URL(fileURLWithPath: relativePath).lastPathComponent

        for pattern in patterns {
            let patternHasSlash = pattern.contains("/")
            
            // This is the core gitignore logic:
            // 1. If a pattern has NO slash, it matches a filename in ANY directory.
            //    Example: `*.swift` should match `App/Views/ContentView.swift`.
            if !patternHasSlash {
                // We test the pattern against just the basename of the path.
                if fnmatch(pattern, pathBasename, 0) == 0 {
                    return true
                }
            }
            // 2. If a pattern HAS a slash, it's matched against the full relative path from the project root.
            //    Example: `App/Models/` should match the path `App/Models/User.swift`.
            else {
                // We use FNM_PATHNAME to ensure slashes are treated as path separators.
                // We also check for directory prefix matches, e.g. pattern `build/` should match file `build/main.o`.
                let pathToCheck = isFolder ? (relativePath + "/") : relativePath
                if pathToCheck.hasPrefix(pattern) {
                    return true
                }

                if fnmatch(pattern, relativePath, FNM_PATHNAME) == 0 {
                    return true
                }
            }
        }
        return false
    }
}
