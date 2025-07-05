//
//  UTType+Extensions.swift
//  Project Ingest
//
//  Created by Bregas Satria Wicaksono on 04/07/25.
//

import UniformTypeIdentifiers

// Add UTType conformance for the save panel
extension UTType {
    public static let markdown = UTType(exportedAs: "net.daringfireball.markdown")
}
