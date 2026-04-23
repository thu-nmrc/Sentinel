import Foundation

// MARK: - User Behavior Insights

struct UserInsight: Identifiable, Equatable {
    let id = UUID()
    let category: InsightCategory
    let title: String
    let detail: String
    let confidence: Double
    let relatedApps: [String]
    let dataPoints: Int

    enum InsightCategory: String, CaseIterable {
        case devTool = "开发工具"
        case language = "编程语言"
        case workflow = "工作流模式"
        case platform = "平台与服务"
        case contentType = "内容类型"
        case collaboration = "协作沟通"

        var symbolName: String {
            switch self {
            case .devTool: return "hammer.fill"
            case .language: return "chevron.left.forwardslash.chevron.right"
            case .workflow: return "arrow.triangle.swap"
            case .platform: return "globe"
            case .contentType: return "doc.richtext"
            case .collaboration: return "person.2.fill"
            }
        }
    }

    static func == (lhs: UserInsight, rhs: UserInsight) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - OpenClaw Skill Recommendation

struct SkillRecommendation: Identifiable, Equatable {
    let id = UUID()
    let skillId: String
    let name: String
    let emoji: String
    let description: String
    let matchScore: Double
    let matchReasons: [String]
    let category: SkillCategory
    let isBuiltIn: Bool
    let skillMarkdown: String

    enum SkillCategory: String, CaseIterable {
        case coding = "编程开发"
        case devops = "DevOps"
        case design = "设计"
        case productivity = "效率工具"
        case communication = "沟通协作"
        case data = "数据分析"
        case content = "内容创作"
        case research = "调研搜索"

        var symbolName: String {
            switch self {
            case .coding: return "curlybraces"
            case .devops: return "server.rack"
            case .design: return "paintbrush.fill"
            case .productivity: return "bolt.fill"
            case .communication: return "bubble.left.and.bubble.right.fill"
            case .data: return "chart.bar.xaxis"
            case .content: return "pencil.and.outline"
            case .research: return "magnifyingglass"
            }
        }
    }

    static func == (lhs: SkillRecommendation, rhs: SkillRecommendation) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Export

struct SkillExportResult: Identifiable {
    let id = UUID()
    let skillId: String
    let path: String
    let success: Bool
    let error: String?
}
