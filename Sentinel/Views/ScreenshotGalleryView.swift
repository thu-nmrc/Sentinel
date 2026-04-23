import AppKit
import SwiftUI

@MainActor
final class ScreenshotThumbnailCache {
    static let shared = ScreenshotThumbnailCache()
    private var cache: [String: NSImage] = [:]

    func cachedThumbnail(for path: String) -> NSImage? {
        cache[path]
    }

    func loadThumbnail(path: String, maxSide: CGFloat = 220) async -> NSImage? {
        if let existing = cache[path] { return existing }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let scaled = await Task.detached(priority: .userInitiated) {
            guard let full = NSImage(contentsOfFile: path) else { return nil as NSImage? }
            return Self.downsample(image: full, maxSide: maxSide)
        }.value
        if let scaled {
            cache[path] = scaled
        }
        return scaled
    }

    nonisolated private static func downsample(image: NSImage, maxSide: CGFloat) -> NSImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let maxDim = max(size.width, size.height)
        guard maxDim > maxSide else { return image }
        let scale = maxSide / maxDim
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        let img = NSImage(size: newSize)
        img.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1
        )
        img.unlockFocus()
        return img
    }
}

private struct GalleryDetailItem: Identifiable {
    var id: String { record.filePath }
    let record: ScreenshotRecord
}

struct ScreenshotGalleryView: View {
    @EnvironmentObject private var analytics: AnalyticsEngine

    @State private var rangeStart = Date()
    @State private var rangeEnd = Date()
    @State private var records: [ScreenshotRecord] = []
    @State private var isLoading = false
    @State private var detailSelection: GalleryDetailItem?

    private let columns = [GridItem(.adaptive(minimum: 200), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    DatePicker("From", selection: $rangeStart, displayedComponents: .date)
                        .datePickerStyle(.field)
                    DatePicker("To", selection: $rangeEnd, displayedComponents: .date)
                        .datePickerStyle(.field)
                    Spacer()
                    Text("\(records.count) screenshot\(records.count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)

            Divider()

            if isLoading && records.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if records.isEmpty {
                ContentUnavailableView {
                    Label("No screenshots", systemImage: "photo.on.rectangle.angled")
                } description: {
                    Text("No captures for the selected range.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(records, id: \.filePath) { record in
                            ScreenshotGalleryCell(record: record) {
                                detailSelection = GalleryDetailItem(record: record)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { load() }
        .onChange(of: rangeStart) { _, _ in load() }
        .onChange(of: rangeEnd) { _, _ in load() }
        .sheet(item: $detailSelection) { item in
            ScreenshotDetailSheet(record: item.record)
        }
    }

    private func load() {
        isLoading = true
        let start = min(rangeStart, rangeEnd)
        let end = max(rangeStart, rangeEnd)
        Task { @MainActor in
            do {
                records = try analytics.screenshots(from: start, to: end)
                isLoading = false
            } catch {
                records = []
                isLoading = false
            }
        }
    }
}

private struct ScreenshotGalleryCell: View {
    let record: ScreenshotRecord
    var onSelect: () -> Void

    @State private var thumbnail: NSImage?

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.15))
                            .overlay {
                                ProgressView()
                                    .scaleEffect(0.85)
                            }
                    }
                }
                .frame(minHeight: 140)
                .frame(maxWidth: .infinity)
                .clipped()

                LinearGradient(
                    colors: [.black.opacity(0.65), .black.opacity(0)],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .frame(height: 72)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                VStack(alignment: .leading, spacing: 2) {
                    Text(record.timestamp, style: .time)
                        .font(.caption.weight(.semibold))
                    Text(record.activeApp)
                        .font(.caption2)
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .shadow(radius: 2)
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .task(id: record.filePath) {
            let cache = ScreenshotThumbnailCache.shared
            if let c = cache.cachedThumbnail(for: record.filePath) {
                thumbnail = c
                return
            }
            thumbnail = await cache.loadThumbnail(path: record.filePath)
        }
    }
}

private struct ScreenshotDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let record: ScreenshotRecord

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let image = NSImage(contentsOfFile: record.filePath) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity)
                    } else {
                        ContentUnavailableView {
                            Label("Image unavailable", systemImage: "exclamationmark.triangle")
                        }
                        .frame(height: 200)
                    }

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        detailRow("Time") {
                            Text(record.timestamp.formatted(date: .abbreviated, time: .shortened))
                        }
                        detailRow("App") {
                            Text(record.activeApp)
                        }
                        detailRow("Window") {
                            Text(record.windowTitle ?? "—")
                        }
                        detailRow("Display") {
                            Text(String(record.displayId))
                        }
                        detailRow("Path") {
                            Text(record.filePath)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(20)
            }
            .frame(minWidth: 520, minHeight: 480)
            .navigationTitle("Screenshot")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func detailRow<V: View>(_ title: LocalizedStringKey, @ViewBuilder value: () -> V) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            value()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
