//
//  ClipboardService.swift
//  Project Ingest
//
//  Created by Bregas Satria Wicaksono on 04/07/25.
//

import AppKit

/// A utility struct for interacting with the system clipboard.
struct ClipboardService {
    /// Clears the clipboard and sets its content to the provided text.
    /// - Parameter text: The string to copy to the clipboard.
    static func copy(text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
