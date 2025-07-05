# Project Ingest

![Icon-iOS-Default-512x512@1x](https://github.com/user-attachments/assets/316783c5-cbc0-4519-90e0-8d27f0d77e88)


A powerful macOS utility to prepare entire source code projects for use with Large Language Models (LLMs).

[![Platform](https://img.shields.io/badge/platform-macOS-lightgrey.svg)](https://www.apple.com/macos)
[![UI Framework](https://img.shields.io/badge/UI-SwiftUI-blue.svg)](https://developer.apple.com/xcode/swiftui/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

<img width="1147" alt="Screenshot 2025-07-05 at 22 33 17" src="https://github.com/user-attachments/assets/172fd16d-43b9-4bb0-8f55-ed66b89a0e62" />


---

## Description

Project Ingest streamlines the process of providing code to LLMs. It scans a project directory, lets you filter out irrelevant files, and consolidates all the code into a single, clean markdown file. This saves you from tedious manual copy-pasting and helps you make the most of your LLM's context window.

## Features

*   **🌲 Interactive File Tree:** Visualize and browse your entire project structure.
*   **✅ Smart Filtering:**
    *   Click any file or folder to instantly exclude or include it from the output.
    *   Use `.gitignore`-style patterns (e.g., `*.log`, `build/`) for advanced filtering.
*   **🤖 Accurate Token Counting:**
    *   Instantly see the token count for each file and the entire project total.
    *   Uses `Tiktoken` to calculate token using `gpt-4o` tokenizer.
*   **🏗️ Include Project Structure:** Optionally add a directory tree to the output to give the LLM better context.
*   **🚀 Modern & Responsive:** Built with SwiftUI & Appkit, native macOS experience that handles large projects with ease.
*   **📋 Quick Output:**
    *   Copy the entire generated content to your clipboard with one click (⌘+⇧+C).
    *   Save the output as a markdown file (⌘+S).

## Usage

1.  **Select Folder:** Click **"Browse..."** and choose your project's root directory.
2.  **Filter Files:** Click files/folders in the sidebar to exclude them, or edit the patterns below.
3.  **Ingest:** Click the **"Ingest"** button to process the files.
4.  **Copy or Save:** Use the toolbar buttons to get your formatted output.

