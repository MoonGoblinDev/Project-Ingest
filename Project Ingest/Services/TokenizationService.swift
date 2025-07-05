//
//  TokenizationService.swift
//  Project Ingest
//
//  Created by Bregas Satria Wicaksono on 05/07/25.
//

import Foundation
import Tiktoken

class TokenizationService {
    
    private let logHandler: (String) -> Void
    
    init(logHandler: @escaping (String) -> Void) {
        self.logHandler = logHandler
    }

    /// The main entry point for token calculation.
    /// It orchestrates fetching the tokenizer once, then starts the recursive processing.
    func calculateTokensForAllItems(in rootItem: FileItem, model: String) async {
        await MainActor.run { logHandler("Loading tokenizer for \(model)...") }
        
        // 1. Load the tokenizer ONCE before any processing begins. This is the key optimization.
        guard let encoder = try? await Tiktoken.shared.getEncoding(model) else {
            await MainActor.run { logHandler("❌ FATAL: Could not load tokenizer for model \(model). Token calculation aborted.") }
            return
        }

        await MainActor.run { logHandler("Starting token calculation...") }
        
        // 2. Start the single, efficient, recursive process, passing the pre-loaded encoder.
        await processItem(item: rootItem, encoder: encoder)
        
        await MainActor.run { logHandler("Token calculation complete.") }
    }

    /// The single recursive function that traverses the file tree.
    /// It processes folders and files concurrently using the same pre-loaded encoder.
    private func processItem(item: FileItem, encoder: Encoding) async {
        // Skip any items that are marked as excluded.
        guard !item.isExcluded else { return }

        if item.isFolder, let children = item.children {
            // For folders, create a task group to process all children concurrently.
            await withTaskGroup(of: Void.self) { group in
                for child in children {
                    group.addTask {
                        // Pass the same encoder down to each child task.
                        await self.processItem(item: child, encoder: encoder)
                    }
                }
            }
        } else if !item.isFolder {
            // For files, perform the token calculation.
            
            // Immediately set the state to .calculating on the main thread for instant UI feedback.
            await MainActor.run {
                if item.tokenState == .idle {
                    item.tokenState = .calculating
                }
            }
            
            // Only proceed if the state was successfully changed to .calculating.
            guard item.tokenState == .calculating else { return }

            // Calculate the final token state for the file.
            let finalState = await calculateTokensForFile(at: item.path, using: encoder)
            
            // Update the UI with the final calculated state.
            await MainActor.run {
                item.tokenState = finalState
            }
        }
    }

    /// Calculates the token count for a single file using the pre-loaded encoder.
    /// This function reads the file and performs the encoding synchronously.
    /// It returns a definitive final state to prevent infinite loading bugs.
    private func calculateTokensForFile(at url: URL, using encoder: Encoding) async -> FileItem.TokenizationState {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            // Skip binary files by returning a count of 0.
            guard !content.contains("\0") else { return .calculated(0) }
            
            // Use the passed-in encoder directly. This is synchronous and very fast.
            let count = encoder.encode(value: content).count
            return .calculated(count)
        } catch {
            await MainActor.run {
                logHandler("⚠️ Could not count tokens for \(url.lastPathComponent): \(error.localizedDescription)")
            }
            return .calculated(0)
        }
    }
}

func getTokenCount(for text: String, model: String) async throws -> Int {
    guard let encoder = try await Tiktoken.shared.getEncoding(model) else {
                print("Could not retrieve encoder for model: \(model)")
                return 0
            }
    let tokens = encoder.encode(value: text)
    return tokens.count
}
