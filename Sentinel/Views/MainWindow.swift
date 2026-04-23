import SwiftUI

enum MainSidebarItem: String, CaseIterable, Identifiable {
    case dashboard
    case timeline
    case appUsage
    case screenshots
    case search
    case skillRecommendation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .timeline: return "Timeline"
        case .appUsage: return "App Usage"
        case .screenshots: return "Screenshots"
        case .search: return "Search"
        case .skillRecommendation: return "Skill 推荐"
        }
    }

    var symbolName: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .timeline: return "calendar.day.timeline.left"
        case .appUsage: return "chart.bar.doc.horizontal.fill"
        case .screenshots: return "photo.on.rectangle.angled"
        case .search: return "magnifyingglass"
        case .skillRecommendation: return "sparkle"
        }
    }
}

struct MainWindow: View {
    @State private var selection: MainSidebarItem = .dashboard

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(MainSidebarItem.allCases) { item in
                Button {
                    selection = item
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.symbolName)
                            .frame(width: 20)
                            .foregroundStyle(selection == item ? .white : .secondary)
                        Text(item.title)
                            .foregroundStyle(selection == item ? .white : .primary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selection == item ? Color.accentColor : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.top, 12)
        .padding(.horizontal, 8)
        .frame(width: 190)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .dashboard:
            DashboardView()
        case .timeline:
            ActivityTimelineView()
        case .appUsage:
            AppUsageView()
        case .screenshots:
            ScreenshotGalleryView()
        case .search:
            SearchView()
        case .skillRecommendation:
            SkillRecommendationView()
        }
    }
}
