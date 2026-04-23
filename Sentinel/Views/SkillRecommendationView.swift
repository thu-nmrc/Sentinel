import SwiftUI

struct SkillRecommendationView: View {
    @EnvironmentObject private var analytics: AnalyticsEngine
    @StateObject private var viewModel = SkillRecommendationViewModel()
    @State private var selectedSkill: SkillRecommendation?
    @State private var showExportAlert = false
    @State private var showPreview = false
    @State private var analysisDays = 7

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            if viewModel.isAnalyzing {
                analyzingView
            } else if viewModel.analysisComplete {
                HSplitView {
                    mainContent
                        .frame(minWidth: 420)
                    if let skill = selectedSkill {
                        skillDetailPanel(skill)
                            .frame(minWidth: 320, idealWidth: 380)
                    }
                }
            } else {
                emptyState
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Skill 智能推荐")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("分析你的使用习惯，推荐最适合的龙虾 Skills")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 12) {
                    Picker("分析范围", selection: $analysisDays) {
                        Text("3 天").tag(3)
                        Text("7 天").tag(7)
                        Text("14 天").tag(14)
                        Text("30 天").tag(30)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)

                    Button {
                        viewModel.analyze(using: analytics, days: analysisDays)
                    } label: {
                        Label(viewModel.analysisComplete ? "重新分析" : "开始分析",
                              systemImage: viewModel.analysisComplete ? "arrow.clockwise" : "sparkle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isAnalyzing)
                }
            }

            if viewModel.analysisComplete {
                insightChips
            }
        }
        .padding(24)
    }

    private var insightChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if !viewModel.primaryRole.isEmpty && viewModel.primaryRole != "通用" {
                    chipView(icon: "person.fill", text: viewModel.primaryRole, color: .purple)
                }
                ForEach(viewModel.insights.prefix(6)) { insight in
                    chipView(
                        icon: insight.category.symbolName,
                        text: insight.title,
                        color: colorForCategory(insight.category)
                    )
                }
            }
        }
    }

    private func chipView(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.12))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }

    // MARK: - Analyzing

    private var analyzingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.3)
            Text("正在分析最近 \(analysisDays) 天的使用数据...")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("分析应用使用、文件操作、窗口标题等痕迹")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "sparkle")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("基于你的使用习惯，智能推荐龙虾 Skills")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("点击「开始分析」，Sentinel 会分析你的应用使用、文件操作等数据\n然后推荐最适合你的 OpenClaw Skills")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button {
                viewModel.analyze(using: analytics, days: analysisDays)
            } label: {
                Label("开始分析", systemImage: "sparkle")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            categoryFilter
            Divider()
            ScrollView {
                LazyVStack(spacing: 12) {
                    if !viewModel.filteredRecommendations.isEmpty {
                        exportBar
                    }
                    ForEach(viewModel.filteredRecommendations) { skill in
                        skillCard(skill)
                            .onTapGesture { selectedSkill = skill }
                    }
                }
                .padding(16)
            }
        }
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterButton(title: "全部", category: nil)
                ForEach(viewModel.usedCategories, id: \.self) { cat in
                    filterButton(title: cat.rawValue, category: cat)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func filterButton(title: String, category: SkillRecommendation.SkillCategory?) -> some View {
        let isSelected = viewModel.selectedCategory == category
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.selectedCategory = category
            }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var exportBar: some View {
        HStack {
            let customCount = viewModel.filteredRecommendations.filter { !$0.isBuiltIn }.count
            Text("\(viewModel.filteredRecommendations.count) 个推荐 · \(customCount) 个可安装")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            if customCount > 0 {
                Button {
                    viewModel.exportAllCustom()
                    showExportAlert = true
                } label: {
                    Label("一键安装全部自定义 Skill", systemImage: "square.and.arrow.down.on.square")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isExporting)
                .alert("导出完成", isPresented: $showExportAlert) {
                    Button("好") {}
                } message: {
                    let success = viewModel.exportResults.filter(\.success).count
                    Text("\(success) 个 Skill 已安装到 ~/.openclaw/skills/\n重启龙虾即可使用")
                }
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Skill Card

    private func skillCard(_ skill: SkillRecommendation) -> some View {
        let installed = viewModel.isInstalled(skill)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(skill.emoji)
                    .font(.system(size: 24))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(skill.name)
                            .font(.system(size: 14, weight: .semibold))
                        if skill.isBuiltIn {
                            Text("内置")
                                .font(.system(size: 10))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.12))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }
                        if installed {
                            Text("已安装")
                                .font(.system(size: 10))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.12))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        }
                    }
                    Text(skill.description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    scoreRing(skill.matchScore)
                    Text(skill.category.rawValue)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 6) {
                ForEach(skill.matchReasons.prefix(2), id: \.self) { reason in
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.green)
                        Text(reason)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if !skill.isBuiltIn && !skill.skillMarkdown.isEmpty {
                    if installed {
                        Button {
                            viewModel.removeSkill(skill.skillId)
                        } label: {
                            Label("卸载", systemImage: "trash")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    } else {
                        Button {
                            viewModel.exportSkill(skill)
                        } label: {
                            Label("安装到龙虾", systemImage: "square.and.arrow.down")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    selectedSkill?.id == skill.id ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.06),
                    lineWidth: selectedSkill?.id == skill.id ? 1.5 : 1
                )
        }
    }

    private func scoreRing(_ score: Double) -> some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 3)
            Circle()
                .trim(from: 0, to: score)
                .stroke(scoreColor(score), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(score * 100))")
                .font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .frame(width: 36, height: 36)
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 0.8 { return .green }
        if score >= 0.6 { return .orange }
        return .yellow
    }

    // MARK: - Detail Panel

    private func skillDetailPanel(_ skill: SkillRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(skill.emoji)
                    .font(.system(size: 28))
                VStack(alignment: .leading) {
                    Text(skill.name)
                        .font(.system(size: 18, weight: .bold))
                    Text(skill.category.rawValue)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { selectedSkill = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    detailSection("匹配度", icon: "target") {
                        HStack(spacing: 12) {
                            scoreRing(skill.matchScore)
                                .frame(width: 48, height: 48)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(Int(skill.matchScore * 100))% 匹配")
                                    .font(.system(size: 16, weight: .semibold))
                                ForEach(skill.matchReasons, id: \.self) { reason in
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.green)
                                        Text(reason)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    detailSection("描述", icon: "doc.text") {
                        Text(skill.description)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    if !skill.isBuiltIn && !skill.skillMarkdown.isEmpty {
                        detailSection("SKILL.md 预览", icon: "doc.plaintext") {
                            Text(skill.skillMarkdown.prefix(800) + (skill.skillMarkdown.count > 800 ? "\n..." : ""))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    if !skill.isBuiltIn && !skill.skillMarkdown.isEmpty {
                        let installed = viewModel.isInstalled(skill)
                        if installed {
                            HStack(spacing: 8) {
                                Button {
                                    viewModel.removeSkill(skill.skillId)
                                } label: {
                                    Label("卸载", systemImage: "trash")
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                                Text("已安装到 ~/.openclaw/skills/\(skill.skillId)/")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Button {
                                viewModel.exportSkill(skill)
                            } label: {
                                Label("安装到龙虾", systemImage: "square.and.arrow.down")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                    }

                    if skill.isBuiltIn {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.blue)
                            Text("这是龙虾内置技能，已自动可用，无需安装")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(Color.blue.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(16)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func detailSection<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            content()
        }
    }

    // MARK: - Helpers

    private func colorForCategory(_ category: UserInsight.InsightCategory) -> Color {
        switch category {
        case .devTool: return .blue
        case .language: return .purple
        case .workflow: return .orange
        case .platform: return .teal
        case .contentType: return .green
        case .collaboration: return .pink
        }
    }
}
