//
//  FileItemView.swift
//  Project Ingest
//
//  Created by Bregas Satria Wicaksono on 04/07/25.
//

import SwiftUI

/// A view that represents a single row in the file tree list.
struct FileItemView: View {
    @ObservedObject var item: FileItem
    
    var body: some View {
        HStack {
            Image(systemName: item.isFolder ? "folder.fill" : "doc")
                .foregroundColor(item.isFolder ? .accentColor : .secondary)
            
            Text(item.name)
                .strikethrough(item.isExcluded, color: .primary)
                .opacity(item.isExcluded ? 0.5 : 1.0)
            
            Spacer()
            
            if item.isCalculatingTokens {
                ProgressView().scaleEffect(0.5)
            } else if item.displayTokenCount > 0 {
                Text("\(item.displayTokenCount)")
                    .font(.system(.body, design: .monospaced).weight(.light))
                    .foregroundColor(.secondary)
                    .opacity(item.isExcluded ? 0.5 : 1.0)
            }
        }
        .padding(.vertical, 2)
    }
}
