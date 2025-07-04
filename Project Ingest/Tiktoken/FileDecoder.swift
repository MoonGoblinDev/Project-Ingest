// FILE: Sources/Tiktoken/FileDecoder.swift
import Foundation

struct FileDecoder {
    func decode(_ data: Data) -> [[UInt8]: Int] {
        guard let decoded = String(data: data, encoding: .utf8) else { return [:] }
        var result: [[UInt8]: Int] = .init()
        decoded.split(separator: "\n").forEach({
            let lineSplit = $0.split(separator: " ")
            guard lineSplit.count == 2,
                  let first = lineSplit.first,
                  let value = lineSplit.last,
                  let keyData = Data(base64Encoded: String(first)), // Directly decode to Data
                  let intValue = Int(value)
            else {
                return
            }
            // The key is the raw bytes from the decoded data
            result[[UInt8](keyData)] = intValue
        })
        return result
    }
}
