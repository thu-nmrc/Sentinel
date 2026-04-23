import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var analytics: AnalyticsEngine

    @State private var query = ""
    @State private var results: SearchResults?
    @State private var isSearching = false

    private var hasResults: Bool {
        guard let r = results else { return false }
        return !r.appUsageResults.isEmpty || !r.clipboardResults.isEmpty
            || !r.fileEventResults.isEmpty || !r.ocrResults.isEmpty
            || !r.keystrokeResults.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search window titles, clipboard, files, screen text, keystrokes…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .onSubmit { performSearch() }
                if isSearching {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            .padding(16)

            Divider()

            if results == nil {
                ContentUnavailableView {
                    Label("Search your activity", systemImage: "magnifyingglass")
                } description: {
                    Text("Search across window titles, clipboard, files, screen text (OCR), and keyboard input.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !hasResults {
                ContentUnavailableView {
                    Label("No results", systemImage: "magnifyingglass")
                } description: {
                    Text("Try a different search term.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let r = results, !r.ocrResults.isEmpty {
                            searchSection("Screen Content (OCR)", systemImage: "text.viewfinder", tint: .indigo) {
                                ForEach(r.ocrResults, id: \.timestamp) { record in
                                    ocrResultRow(record)
                                }
                            }
                        }
                        if let r = results, !r.keystrokeResults.isEmpty {
                            searchSection("Keyboard Input", systemImage: "keyboard", tint: .pink) {
                                ForEach(r.keystrokeResults, id: \.timestamp) { record in
                                    keystrokeResultRow(record)
                                }
                            }
                        }
                        if let r = results, !r.appUsageResults.isEmpty {
                            searchSection("App Activity", systemImage: "app.fill", tint: .blue) {
                                ForEach(r.appUsageResults, id: \.startTime) { record in
                                    appUsageResultRow(record)
                                }
                            }
                        }
                        if let r = results, !r.clipboardResults.isEmpty {
                            searchSection("Clipboard", systemImage: "doc.on.clipboard", tint: .green) {
                                ForEach(r.clipboardResults, id: \.timestamp) { record in
                                    clipboardResultRow(record)
                                }
                            }
                        }
                        if let r = results, !r.fileEventResults.isEmpty {
                            searchSection("File Events", systemImage: "doc.text", tint: .orange) {
                                ForEach(r.fileEventResults, id: \.timestamp) { record in
                                    fileEventResultRow(record)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func performSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isSearching = true
        Task { @MainActor in
            do {
                results = try analytics.search(query: q, limit: 50)
            } catch {
                results = SearchResults(appUsageResults: [], clipboardResults: [], fileEventResults: [], ocrResults: [], keystrokeResults: [])
            }
            isSearching = false
        }
    }

    @ViewBuilder
    private func searchSection<Content: View>(
        _ title: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
        }
    }

    private func ocrResultRow(_ record: ScreenshotRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let nsImage = NSImage(contentsOfFile: record.filePath) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(record.activeApp)
                    .font(.system(.body, weight: .medium))
                if let ocrText = record.ocrText, !ocrText.isEmpty {
                    Text(String(ocrText.prefix(300)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(record.timestamp, style: .date)
                    .font(.caption)
                Text(record.timestamp, style: .time)
                    .font(.caption)
            }
            .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
    }

    private func keystrokeResultRow(_ record: KeystrokeRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.activeApp)
                    .font(.system(.body, weight: .medium))
                Text("\"\(record.characters)\"")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(record.timestamp, style: .date)
                    .font(.caption)
                Text(record.timestamp, style: .time)
                    .font(.caption)
            }
            .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
    }

    private func appUsageResultRow(_ record: AppUsageRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.appName)
                    .font(.system(.body, weight: .medium))
                if let title = record.windowTitle, !title.isEmpty {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(record.startTime, style: .date)
                    .font(.caption)
                Text(record.startTime, style: .time)
                    .font(.caption)
            }
            .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
    }

    private func clipboardResultRow(_ record: ClipboardRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.contentType.capitalized)
                    .font(.system(.body, weight: .medium))
                if let text = record.textContent, !text.isEmpty {
                    Text(String(text.prefix(300)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(record.timestamp, style: .date)
                    .font(.caption)
                Text(record.timestamp, style: .time)
                    .font(.caption)
            }
            .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
    }

    private func fileEventResultRow(_ record: FileEventRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.eventType.capitalized)
                    .font(.system(.body, weight: .medium))
                Text(record.path)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Text(record.timestamp, style: .time)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
    }
}
