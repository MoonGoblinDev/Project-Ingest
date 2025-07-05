//
//  AppError.swift
//  Project Ingest
//
//  Created by Bregas Satria Wicaksono on 05/07/25.
//

import SwiftUI
import Foundation

// MARK: - Custom Error Type for User-Facing Alerts
enum AppError: Error, LocalizedError, Identifiable {
    case folderAccessFailed(URL)
    case bookmarkResolutionFailed(Error)
    case fileSaveFailed(Error)
    
    var id: String { localizedDescription }
    
    var errorDescription: String? {
        switch self {
        case .folderAccessFailed(_):
            return "Access Denied"
        case .bookmarkResolutionFailed:
            return "Failed to Open Recent Folder"
        case .fileSaveFailed:
            return "Save Failed"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .folderAccessFailed(let url):
            return "Could not gain access to \(url.lastPathComponent). Please try selecting the folder again using the 'Browse...' button."
        case .bookmarkResolutionFailed(let error):
            return "Could not open the selected folder. It may have been moved or deleted. The app will remove it from Recents.\n\nDetails: \(error.localizedDescription)"
        case .fileSaveFailed(let error):
            return "The file could not be saved. Please check permissions and try again.\n\nDetails: \(error.localizedDescription)"
        }
    }
}
