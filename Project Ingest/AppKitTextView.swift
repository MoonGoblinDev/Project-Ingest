//
//  AppKitTextView.swift
//  Project Ingest
//
//  Created by Bregas Satria Wicaksono on 04/07/25.
//

// AppKitTextView.swift

import SwiftUI

struct AppKitTextView: NSViewRepresentable {
    // The text content to display.
    var text: String
    
    // A flag to control whether the view automatically scrolls to the end.
    // Useful for the log view.
    var isAutoScrolling: Bool

    // This method is called only once to create the AppKit view.
    func makeNSView(context: Context) -> NSScrollView {
        // 1. Create the scroll view, which will contain the text view.
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        
        // 2. Create the text view itself.
        let textView = NSTextView()
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isEditable = false // We only want to display text.
        textView.isSelectable = true // Allow user to copy text.
        textView.isRichText = false  // Plain text is faster.
        
        // 3. Configure the text view's layout behavior within the scroll view.
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true // Enable line wrapping.
        
        // 4. Set the text view as the document view of the scroll view.
        scrollView.documentView = textView
        
        return scrollView
    }

    // This method is called whenever the SwiftUI state changes (e.g., when `text` is updated).
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Safely get the text view from the scroll view.
        guard let textView = nsView.documentView as? NSTextView else {
            return
        }
        
        // Only update if the text has actually changed to prevent unnecessary work.
        if textView.string != self.text {
            textView.string = self.text
            
            // If auto-scrolling is enabled, scroll to the very end of the document.
            if isAutoScrolling {
                textView.scrollToEndOfDocument(nil)
            }
        }
    }
}
