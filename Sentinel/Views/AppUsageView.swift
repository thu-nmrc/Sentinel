import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct AppUsageRow: Identifiable {
    let id = UUID()
    let bundleId: String
    let appName: String
    let totalDuration: TimeInterval
}

struct AppUsageView: View {
    @EnvironmentObject private var analytics: AnalyticsEngine
    @State private var selectedDate = Date()
    @State private var rows: [AppUsageRow] = []
    @State private var isLoading = false

    private var maxDuration: TimeInterval {
        rows.first?.totalDuration ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("App Usage")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                    .labelsHidden()
                    .frame(maxWidth: 200)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            if isLoading && rows.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rows.isEmpty {
                ContentUnavailableView {
                    Label("No app usage data", systemImage: "chart.bar.doc.horizontal")
                } description: {
                    Text("No activity recorded for this day.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(rows) { row in
                    AppUsageRowView(row: row, maxDuration: maxDuration)
                        .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { loadData() }
        .onChange(of: selectedDate) { _, _ in loadData() }
    }

    private func loadData() {
        isLoading = true
        let date = selectedDate
        Task { @MainActor in
            do {
                let breakdown = try analytics.appUsageBreakdown(for: date)
                rows = breakdown.map {
                    AppUsageRow(bundleId: $0.bundleId, appName: $0.appName, totalDuration: $0.totalDuration)
                }
            } catch {
                rows = []
            }
            isLoading = false
        }
    }
}

private struct AppUsageRowView: View {
    let row: AppUsageRow
    let maxDuration: TimeInterval

    private var icon: NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: row.bundleId) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }

    private var fraction: CGFloat {
        guard maxDuration > 0 else { return 0 }
        return CGFloat(row.totalDuration / maxDuration)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(row.appName)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                    Spacer()
                    Text(row.totalDuration.formattedDuration)
                        .font(.system(.subheadline, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.blue.opacity(0.85), .cyan.opacity(0.65)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, geo.size.width * fraction))
                    }
                }
                .frame(height: 8)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
    }
}
