// FILE: Sources/Tiktoken/Extensions/String+UInt8.swift
import Foundation

extension String {
    // Rename this to be explicit
    var utf8Bytes: [UInt8] { Array(self.utf8) }
    
    // The old buggy property
    // var uInt8: [UInt8] { utf16.map({ UInt8($0) }) }
}
