//
//  TokenHelper.swift
//  Novel Translator
//
//  Created by Bregas Satria Wicaksono on 15/06/25.
//

import Foundation

func getTokenCount(for text: String, model: String) async throws -> Int {
    guard let encoder = try await Tiktoken.shared.getEncoding(model) else {
                print("Could not retrieve encoder for model: \(model)")
                return 0
            }
    let tokens = encoder.encode(value: text)
    return tokens.count
}
