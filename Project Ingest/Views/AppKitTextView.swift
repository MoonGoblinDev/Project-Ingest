//
//  AppKitTextView.swift
//  Project Ingest
//
//  Created by Bregas Satria Wicaksono on 04/07/25.
//


import SwiftUI

struct AppKitTextView: NSViewRepresentable {
    var text: String
    var isAutoScrolling: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        
        let textView = NSTextView()
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        
        scrollView.documentView = textView
        
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else {
            return
        }
        
        if textView.string != self.text {
            textView.string = self.text
            if isAutoScrolling {
                textView.scrollToEndOfDocument(nil)
            }
        }
    }
}
