import SwiftUI

struct TimelineEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let category: TimelineCategory
    let title: String
    let subtitle: String?
    let iconName: String
    let tint: Color
    var screenshotPath: String?
    var ocrText: String?
}

enum TimelineCategory: String, CaseIterable {
    case appUsage, screenshot, fileEvent, clipboard, keyboardInput, ocrCapture

    var label: String {
        switch self {
        case .appUsage: return "Apps"
        case .screenshot: return "Screenshots"
        case .fileEvent: return "Files"
        case .clipboard: return "Clipboard"
        case .keyboardInput: return "Keyboard"
        case .ocrCapture: return "OCR"
        }
    }
}

struct ActivityTimelineView: View {
    @EnvironmentObject private var analytics: AnalyticsEngine

    @State private var selectedDate = Date()
    @State private var visibleCategories: Set<TimelineCategory> = Set(TimelineCategory.allCases)
    @State private var entries: [TimelineEntry] = []
    @State private var isLoading = false
    @State private var refreshTimer: Timer?

    private let calendar = Calendar.current

    private var filteredEntries: [TimelineEntry] {
        entries.filter { visibleCategories.contains($0.category) }
    }

    private var hourGroups: [(hour: Int, items: [TimelineEntry])] {
        let grouped = Dictionary(grouping: filteredEntries) { calendar.component(.hour, from: $0.timestamp) }
        return grouped.keys.sorted(by: >).map { hour in
            (hour, grouped[hour]!.sorted { $0.timestamp > $1.timestamp })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            Divider()
            if isLoading && entries.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredEntries.isEmpty {
                ContentUnavailableView {
                    Label("No activity", systemImage: "calendar.badge.exclamationmark")
                } description: {
                    Text(entries.isEmpty ? "Nothing recorded for this day." : "Turn on filters to see events.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(hourGroups, id: \.hour) { group in
                            Section {
                                timelineSection(items: group.items)
                            } header: {
                                hourHeader(group.hour)
                            }
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            loadTimeline()
            startAutoRefresh()
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
        .onChange(of: selectedDate) { _, _ in loadTimeline() }
    }

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker("Day", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.field)
                .labelsHidden()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TimelineCategory.allCases, id: \.self) { cat in
                        categoryChip(cat)
                    }
                }
            }
        }
        .padding(16)
    }

    private func categoryChip(_ category: TimelineCategory) -> some View {
        let on = visibleCategories.contains(category)
        return Button {
            if on {
                visibleCategories.remove(category)
            } else {
                visibleCategories.insert(category)
            }
        } label: {
            Text(category.label)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(on ? categoryTint(category).opacity(0.2) : Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(on ? categoryTint(category).opacity(0.5) : Color.secondary.opacity(0.25), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func hourHeader(_ hour: Int) -> some View {
        HStack {
            Text(formattedHour(hour))
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.92))
    }

    private func timelineSection(items: [TimelineEntry]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(items) { entry in
                timelineRow(entry: entry)
            }
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.secondary.opacity(0.28))
                .frame(width: 2)
                .padding(.leading, 13)
        }
    }

    private func timelineRow(entry: TimelineEntry) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .frame(width: 28, height: 28)
                Circle()
                    .fill(entry.tint.opacity(0.22))
                    .frame(width: 24, height: 24)
                Image(systemName: entry.iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(entry.tint)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.timestamp, style: .time)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 10) {
                    if entry.category == .screenshot || entry.category == .ocrCapture,
                       let path = entry.screenshotPath,
                       let nsImage = NSImage(contentsOfFile: path) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 72, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title)
                            .font(.body.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                        if let sub = entry.subtitle, !sub.isEmpty {
                            Text(sub)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(6)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let ocrText = entry.ocrText, !ocrText.isEmpty {
                            Text(ocrText)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(4)
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                )
                        }
                    }
                }
            }
            .padding(.bottom, 2)
        }
    }

    private func loadTimeline() {
        isLoading = true
        let day = selectedDate
        Task { @MainActor in
            do {
                let appUsage = try analytics.appUsageRecords(for: day)
                let shots = try analytics.screenshots(from: day, to: day)
                let files = try analytics.fileEvents(for: day)
                let clips = try analytics.clipboardRecords(for: day)
                let keystrokeGroups = try analytics.keystrokeGroups(for: day)

                var built: [TimelineEntry] = []
                built.append(contentsOf: appUsage.map(makeAppEntry))
                for shot in shots {
                    if let ocrText = shot.ocrText, !ocrText.isEmpty {
                        built.append(makeOCREntry(shot))
                    } else {
                        built.append(makeScreenshotEntry(shot))
                    }
                }
                built.append(contentsOf: files.map(makeFileEntry))
                built.append(contentsOf: clips.map(makeClipboardEntry))
                built.append(contentsOf: keystrokeGroups.map(makeKeystrokeGroupEntry))
                built.sort { $0.timestamp > $1.timestamp }

                entries = built
                isLoading = false
            } catch {
                entries = []
                isLoading = false
            }
        }
    }

    private func makeAppEntry(_ r: AppUsageRecord) -> TimelineEntry {
        let window = (r.windowTitle?.isEmpty == false) ? r.windowTitle! : "—"
        let dur = formatDuration(r.duration)
        return TimelineEntry(
            timestamp: r.startTime,
            category: .appUsage,
            title: r.appName,
            subtitle: "\(window) · \(dur)",
            iconName: "app.fill",
            tint: .blue
        )
    }

    private func makeScreenshotEntry(_ r: ScreenshotRecord) -> TimelineEntry {
        TimelineEntry(
            timestamp: r.timestamp,
            category: .screenshot,
            title: r.activeApp,
            subtitle: r.windowTitle,
            iconName: "camera.viewfinder",
            tint: .purple,
            screenshotPath: r.filePath
        )
    }

    private func makeOCREntry(_ r: ScreenshotRecord) -> TimelineEntry {
        let preview = r.ocrText.map { String($0.prefix(300)) }
        return TimelineEntry(
            timestamp: r.timestamp,
            category: .ocrCapture,
            title: "Screen Content — \(r.activeApp)",
            subtitle: r.windowTitle,
            iconName: "text.viewfinder",
            tint: .indigo,
            screenshotPath: r.filePath,
            ocrText: preview
        )
    }

    private func makeFileEntry(_ r: FileEventRecord) -> TimelineEntry {
        TimelineEntry(
            timestamp: r.timestamp,
            category: .fileEvent,
            title: r.eventType,
            subtitle: r.path,
            iconName: "doc.text",
            tint: .orange
        )
    }

    private func makeClipboardEntry(_ r: ClipboardRecord) -> TimelineEntry {
        let preview: String?
        if let t = r.textContent, !t.isEmpty {
            preview = String(t.prefix(200))
        } else {
            preview = nil
        }
        let sub = [r.contentType, preview].compactMap { $0 }.joined(separator: " · ")
        return TimelineEntry(
            timestamp: r.timestamp,
            category: .clipboard,
            title: "Clipboard",
            subtitle: sub.isEmpty ? nil : sub,
            iconName: "doc.on.clipboard",
            tint: .green
        )
    }

    private func makeKeystrokeGroupEntry(_ g: KeystrokeGroup) -> TimelineEntry {
        let preview = String(g.text.prefix(200))
        let sub = "\(g.windowTitle ?? "—") · \(g.keystrokeCount) keys"
        return TimelineEntry(
            timestamp: g.startTime,
            category: .keyboardInput,
            title: "\(g.activeApp) — typed:",
            subtitle: "\(sub)\n\"\(preview)\"",
            iconName: "keyboard",
            tint: .pink
        )
    }

    private func formattedHour(_ hour: Int) -> String {
        var c = DateComponents()
        c.hour = hour
        c.minute = 0
        guard let date = calendar.date(from: c) else { return "\(hour):00" }
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let s = Int(interval.rounded())
        if s < 60 { return "\(s)s" }
        let m = s / 60
        if m < 60 { return "\(m)m" }
        let h = m / 60
        let rem = m % 60
        return rem > 0 ? "\(h)h \(rem)m" : "\(h)h"
    }

    private func startAutoRefresh() {
        refreshTimer?.invalidate()
        let t = Timer(timeInterval: 15, repeats: true) { _ in
            Task { @MainActor in
                loadTimeline()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        refreshTimer = t
    }

    private func categoryTint(_ c: TimelineCategory) -> Color {
        switch c {
        case .appUsage: return .blue
        case .screenshot: return .purple
        case .fileEvent: return .orange
        case .clipboard: return .green
        case .keyboardInput: return .pink
        case .ocrCapture: return .indigo
        }
    }
}
