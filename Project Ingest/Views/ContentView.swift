//
//  ContentView.swift
//  Project Ingest
//
//  Created by Bregas Satria Wicaksono on 04/07/25.
//

import SwiftUI

struct ContentView: View {
    
    @StateObject private var viewModel = ProjectIngestViewModel()
    @State private var selectedTab: Int = 0
    @State private var showCopyConfirmation: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 350, ideal: 450)
            } detail: {
                mainContent
            }
            
            Divider()
            
            statusBar
        }
        .onAppear {
            viewModel.loadInitialFolder()
        }
        .toolbar {
            toolbarItems
        }
        .frame(minWidth: 1000, minHeight: 750)
        .disabled(viewModel.isIngesting)
        .overlay {
            if viewModel.isIngesting {
                ProgressView { Text("Ingesting...") }
                    .scaleEffect(1.2)
                    .progressViewStyle(.circular)
                    .padding(25)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .overlay(alignment: .top) {
            if showCopyConfirmation {
                Label("Copied to Clipboard", systemImage: "checkmark.circle.fill")
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(.regularMaterial, in: Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                showCopyConfirmation = false
                            }
                        }
                    }
                    .padding(.top)
            }
        }
        // NEW: Add an alert modifier to present errors to the user.
        .alert(item: $viewModel.currentError) { error in
            Alert(
                title: Text(error.errorDescription ?? "An Error Occurred"),
                message: Text(error.recoverySuggestion ?? "Please try again."),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    // MARK: - Sidebar View
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading) {
                HStack {
                    Text("Source Folder").font(.headline)
                    Spacer()
                    
                    // Recents Menu
                    if !viewModel.recentFolders.isEmpty {
                        Menu {
                            ForEach(viewModel.recentFolders) { recent in
                                Button(recent.name) {
                                    viewModel.selectRecentFolder(recent)
                                }
                            }
                            Divider()
                            Button("Clear Recents", role: .destructive) {
                                viewModel.clearRecents()
                            }
                        } label: {
                            Label("Recents", systemImage: "clock.arrow.circlepath")
                                .labelStyle(.iconOnly)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Select a recent folder")
                    }
                    
                    Button("Browse...", action: viewModel.browseForFolder)
                }
                Text(viewModel.folderPath)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 8)
            
            Divider()
            
            List(viewModel.fileTree, children: \.children) { item in
                FileItemView(item: item)
                    .onTapGesture {
                        viewModel.toggleExclusion(for: item)
                    }
                    .contextMenu {
                        Button(item.isExcluded ? "Include Item" : "Exclude Item") {
                            viewModel.toggleExclusion(for: item)
                        }
                    }
            }
            .listStyle(.sidebar)

            VStack(alignment: .leading, spacing: 10) {
                DisclosureGroup("Exclude Patterns (gitignore style)") {
                    TextEditor(text: $viewModel.ignorePatterns)
                        .font(.monospaced(.body)())
                        .frame(height: 150)
                        .background(in: RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                }
                
                Toggle(isOn: $viewModel.includeProjectStructure) {
                    Text("Include project structure tree")
                }
            }
            .padding()
        }
    }

    // MARK: - Main Content View
    private var mainContent: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                Picker("View", selection: $selectedTab) {
                    Label("Ingested Content", systemImage: "doc.text.magnifyingglass").tag(0)
                    Label("Log", systemImage: "list.bullet.rectangle.portrait").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 250)
                .padding()
                
                ZStack {
                    AppKitTextView(text: viewModel.ingestedContent, isAutoScrolling: false)
                        .opacity(selectedTab == 0 ? 1 : 0)
                    
                    AppKitTextView(text: viewModel.logMessages, isAutoScrolling: true)
                        .opacity(selectedTab == 1 ? 1 : 0)
                }
                HStack{
                    Spacer()
                    Button("Ingest") {
                        viewModel.startIngest()
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .onHover { isHovering in
                        if isHovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .padding()
                }
                
            }
            
            .background(Color(nsColor: .textBackgroundColor))
            
           
        }
    }
    
    // MARK: - Status Bar
    private var statusBar: some View {
        HStack {
            Spacer()
            if viewModel.isIngesting {
                ProgressView(value: viewModel.progressValue, total: viewModel.progressTotal)
                    .frame(width: 150)
                Text("Ingesting... (\(Int(viewModel.progressValue))/\(Int(viewModel.progressTotal)))")
                    .font(.caption)
            } else if !viewModel.ingestedContent.isEmpty {
                 Text("Total Tokens: \(viewModel.ingestedTokenCount)")
                    .font(.caption.monospacedDigit())
            }
        }
        .padding(.horizontal)
        .frame(height: 28)
        .background(.bar)
    }

    // MARK: - Toolbar
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button(action: {
                if viewModel.copyToClipboard() {
                    withAnimation(.spring()) {
                        showCopyConfirmation = true
                    }
                }
            }) {
                Label("Copy", systemImage: "doc.on.clipboard")
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            
            Button(action: viewModel.saveToFile) {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: .command)
        }
    }
}

// MARK: - Previews
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
