//
//  FileItem.swift
//  Project Ingest
//
//  Created by Bregas Satria Wicaksono on 04/07/25.
//


import Foundation

class FileItem: Identifiable, Hashable, ObservableObject {
    let id: URL
    let name: String
    let path: URL
    let isFolder: Bool
    var children: [FileItem]?
    
    // The gitignore-style pattern for this specific item.
    var ignorePattern: String = ""
    
    // @Published allows the UI to automatically update when this value changes.
    @Published var isExcluded: Bool = false
    
    // The number of tokens for this file, calculated asynchronously.
    @Published var tokenCount: Int? = nil

    // Computed property to calculate total tokens, respecting exclusion.
    var displayTokenCount: Int {
        if isExcluded { return 0 }
        
        if isFolder, let children = children {
            // Sum of children's displayTokenCount
            return children.reduce(0) { $0 + $1.displayTokenCount }
        } else {
            // Return own token count, or 0 if not yet calculated
            return tokenCount ?? 0
        }
    }

    init(url: URL) {
        self.id = url
        self.path = url
        self.name = url.lastPathComponent
        
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        self.isFolder = isDir.boolValue
        
        if self.isFolder {
            self.children = []
        }
    }
    
    // Conformance to Hashable protocol
    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
