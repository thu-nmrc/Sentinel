import Foundation
import SwiftUI

struct DashboardStat: Identifiable {
    var id: String { title }
    let title: String
    let value: String
    let symbolName: String
    let tint: Color
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var stats: [DashboardStat] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    nonisolated init() {}

    func loadStats(using engine: AnalyticsEngine, for date: Date) {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let recording = try engine.totalRecordingTime(for: date)
                let apps = try engine.distinctAppsCount(for: date)
                let keys = try engine.totalKeystrokes(for: date)
                let clicks = try engine.totalMouseClicks(for: date)
                let shots = try engine.screenshotCount(for: date)
                let files = try engine.fileEventsCount(for: date)
                let ocr = try engine.ocrCount(for: date)

                let built: [DashboardStat] = [
                    DashboardStat(
                        title: "Total Recording Time",
                        value: Self.formatRecordingTime(recording),
                        symbolName: "record.circle.fill",
                        tint: .red
                    ),
                    DashboardStat(
                        title: "Apps Used",
                        value: Self.formatCount(apps),
                        symbolName: "app.fill",
                        tint: .blue
                    ),
                    DashboardStat(
                        title: "Keystrokes",
                        value: Self.formatCount(keys),
                        symbolName: "keyboard",
                        tint: .purple
                    ),
                    DashboardStat(
                        title: "Mouse Clicks",
                        value: Self.formatCount(clicks),
                        symbolName: "cursorarrow.click",
                        tint: .orange
                    ),
                    DashboardStat(
                        title: "Screenshots Taken",
                        value: Self.formatCount(shots),
                        symbolName: "camera.viewfinder",
                        tint: .teal
                    ),
                    DashboardStat(
                        title: "OCR Captures",
                        value: Self.formatCount(ocr),
                        symbolName: "text.viewfinder",
                        tint: .indigo
                    ),
                    DashboardStat(
                        title: "Files Changed",
                        value: Self.formatCount(files),
                        symbolName: "doc.badge.arrow.up",
                        tint: .green
                    )
                ]
                stats = built
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                stats = Self.placeholderStats
                isLoading = false
            }
        }
    }

    private static func formatRecordingTime(_ interval: TimeInterval) -> String {
        let secs = max(0, Int(interval.rounded(.towardZero)))
        let h = secs / 3600
        let m = (secs % 3600) / 60
        if h > 0, m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        if m > 0 { return "\(m)m" }
        if secs > 0 { return "\(secs)s" }
        return "0s"
    }

    private static func formatCount(_ n: Int) -> String {
        let v = max(0, n)
        if v >= 1_000_000 {
            return String(format: "%.1fM", Double(v) / 1_000_000)
        }
        if v >= 10_000 {
            return String(format: "%.1fk", Double(v) / 1000)
        }
        if v >= 1_000 {
            return String(format: "%.1fk", Double(v) / 1000)
        }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    private static var placeholderStats: [DashboardStat] {
        [
            DashboardStat(title: "Total Recording Time", value: "—", symbolName: "record.circle.fill", tint: .red),
            DashboardStat(title: "Apps Used", value: "—", symbolName: "app.fill", tint: .blue),
            DashboardStat(title: "Keystrokes", value: "—", symbolName: "keyboard", tint: .purple),
            DashboardStat(title: "Mouse Clicks", value: "—", symbolName: "cursorarrow.click", tint: .orange),
            DashboardStat(title: "Screenshots Taken", value: "—", symbolName: "camera.viewfinder", tint: .teal),
            DashboardStat(title: "OCR Captures", value: "—", symbolName: "text.viewfinder", tint: .indigo),
            DashboardStat(title: "Files Changed", value: "—", symbolName: "doc.badge.arrow.up", tint: .green)
        ]
    }
}
