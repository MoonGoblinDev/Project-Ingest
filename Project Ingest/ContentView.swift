// ContentView.swift

import SwiftUI
import UniformTypeIdentifiers // For UTType.markdown

struct ContentView: View {
    
    @StateObject private var viewModel = ProjectIngestViewModel()
    @State private var selectedTab: Int = 0 // 0 for Content, 1 for Log

    var body: some View {
        // ADDED: A root VStack to hold the main content and the new status bar
        VStack(spacing: 0) {
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 350, ideal: 450)
            } detail: {
                mainContent
            }
            
            Divider()
            
            statusBar // The new status bar view
        }
        .toolbar {
            toolbarItems // The corrected toolbar content
        }
        .frame(minWidth: 1000, minHeight: 750)
        .disabled(viewModel.isIngesting)
        .overlay(
            viewModel.isIngesting ?
                ProgressView { Text("Ingesting...") }
                    .scaleEffect(1.2)
                    .progressViewStyle(.circular)
                    .padding(25)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                : nil
        )
    }
    
    // MARK: - Sidebar View
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading) {
                HStack {
                    Text("Source Folder").font(.headline)
                    Spacer()
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

            // Group the settings controls at the bottom
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
                
                // NEW: Toggle to include the project structure
                Toggle(isOn: $viewModel.includeProjectStructure) {
                    Text("Include project structure tree")
                }
            }
            .padding()
        }
    }

    // MARK: - Main Content View
    private var mainContent: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $selectedTab) {
                Label("Ingested Content", systemImage: "doc.text.magnifyingglass").tag(0)
                Label("Log", systemImage: "list.bullet.rectangle.portrait").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 250)
            .padding()
            
            // Use a ZStack to keep the view identity stable
            ZStack {
                AppKitTextView(text: viewModel.ingestedContent, isAutoScrolling: false)
                    .opacity(selectedTab == 0 ? 1 : 0)
                
                AppKitTextView(text: viewModel.logMessages, isAutoScrolling: true)
                    .opacity(selectedTab == 1 ? 1 : 0)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
    
    // MARK: - Status Bar (MOVED from Toolbar)
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

//            if !viewModel.isIngesting {
//                Text("Ready")
//                    .font(.caption)
//                    .foregroundColor(.secondary)
//            }
        }
        .padding(.horizontal)
        .frame(height: 28)
        .background(.bar)
    }


    // MARK: - Toolbar
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent { // FIXED: Return type is now 'some ToolbarContent'
        ToolbarItemGroup(placement: .automatic) {
            Picker("Model", selection: $viewModel.selectedModel) {
                ForEach(viewModel.availableModels, id: \.self) { modelName in
                    Text(modelName).tag(modelName)
                }
            }
            .pickerStyle(.menu)
            
            Spacer()
            
            Button(action: viewModel.copyToClipboard) {
                Label("Copy", systemImage: "doc.on.clipboard")
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            
            Button(action: viewModel.saveToFile) {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: .command)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: viewModel.startIngest) {
                Label("Ingest Project", systemImage: "arrow.down.doc.fill")
            }
            .keyboardShortcut("r", modifiers: .command)
            .buttonStyle(.borderedProminent)
        }
        
        // REMOVED: The bottom bar content was moved to the 'statusBar' view.
    }
}

// MARK: - File Item Row View
struct FileItemView: View {
    @ObservedObject var item: FileItem
    
    var body: some View {
        HStack {
            Image(systemName: item.isFolder ? "folder.fill" : "doc")
                .foregroundColor(item.isFolder ? .accentColor : .secondary)
            
            Text(item.name)
                .strikethrough(item.isExcluded, color: .primary)
                .opacity(item.isExcluded ? 0.5 : 1.0)
            
            Spacer()
            
            if !item.isFolder && item.tokenCount == nil && !item.isExcluded {
                ProgressView().scaleEffect(0.5)
            } else if item.displayTokenCount > 0 {
                Text("\(item.displayTokenCount)")
                    .font(.system(.body, design: .monospaced).weight(.light))
                    .foregroundColor(.secondary)
                    .opacity(item.isExcluded ? 0.5 : 1.0)
            }
        }
        .padding(.vertical, 2)
    }
}


// MARK: - Previews
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

// Add UTType conformance for the save panel
extension UTType {
    public static let markdown = UTType(exportedAs: "net.daringfireball.markdown")
}
