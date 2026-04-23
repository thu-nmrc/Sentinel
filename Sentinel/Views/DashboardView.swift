import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var analytics: AnalyticsEngine
    @StateObject private var viewModel = DashboardViewModel()

    @State private var refreshTimer: Timer?

    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 320), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if viewModel.isLoading, viewModel.stats.isEmpty {
                    ProgressView()
                        .scaleEffect(1.1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    if let message = viewModel.errorMessage {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(message)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.orange.opacity(0.12))
                        }
                    }
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(viewModel.stats) { stat in
                            statCard(stat)
                        }
                    }
                    .opacity(viewModel.isLoading ? 0.55 : 1)
                }
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            viewModel.loadStats(using: analytics, for: Date())
            startAutoRefresh()
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    private func startAutoRefresh() {
        refreshTimer?.invalidate()
        let t = Timer(timeInterval: 10, repeats: true) { _ in
            Task { @MainActor in
                viewModel.loadStats(using: analytics, for: Date())
            }
        }
        RunLoop.main.add(t, forMode: .common)
        refreshTimer = t
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today's Overview")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(Date(), format: .dateTime.weekday(.wide).month(.wide).day().year())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func statCard(_ stat: DashboardStat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: stat.symbolName)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(stat.tint)
                Spacer(minLength: 0)
            }
            Text(stat.value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.8)
                .lineLimit(1)
            Text(stat.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}
