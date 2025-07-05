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
    
    // REVAMPED: Add a weak reference to the parent to avoid retain cycles.
    // This is crucial for propagating updates up the tree.
    weak var parent: FileItem?
    
    // The gitignore-style pattern for this specific item.
    var ignorePattern: String = ""
    
    // REVAMPED: The didSet observer now triggers an update propagation.
    @Published var isExcluded: Bool = false {
        didSet {
            // If the exclusion state changes, notify ancestors to update their UI.
            if oldValue != isExcluded {
                self.propagateUpdate()
            }
        }
    }
    
    enum TokenizationState: Equatable {
        case idle
        case calculating
        case calculated(Int)
    }
    
    // REVAMPED: The didSet observer now triggers an update propagation.
    @Published var tokenState: TokenizationState = .idle {
        didSet {
            // If the token state changes, notify ancestors to update their UI.
            if oldValue != tokenState {
                self.propagateUpdate()
            }
        }
    }
    
    // Computed property to calculate total tokens, respecting exclusion and state.
    var displayTokenCount: Int {
        if isExcluded { return 0 }
        
        if isFolder, let children = children {
            return children.reduce(0) { $0 + $1.displayTokenCount }
        } else {
            if case .calculated(let count) = tokenState {
                return count
            }
            return 0
        }
    }
    
    // Computed property to determine if tokens are being calculated.
    var isCalculatingTokens: Bool {
        if isExcluded { return false }
        
        if isFolder, let children = children {
            return children.contains { !$0.isExcluded && $0.isCalculatingTokens }
        } else {
            return tokenState == .calculating
        }
    }
    
    // REVAMPED: This function tells SwiftUI that this object and all its ancestors
    // need to be re-evaluated and redrawn.
    private func propagateUpdate() {
        // Manually send the 'will change' signal to notify any observing views.
        self.objectWillChange.send()
        // Recursively call the same method on the parent, creating a chain reaction to the root.
        parent?.propagateUpdate()
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
