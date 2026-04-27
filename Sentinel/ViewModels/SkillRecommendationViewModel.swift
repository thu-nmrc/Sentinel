import Foundation
import SwiftUI

@MainActor
final class SkillRecommendationViewModel: ObservableObject {
    @Published var insights: [UserInsight] = []
    @Published var recommendations: [SkillRecommendation] = []
    @Published var exportResults: [SkillExportResult] = []
    @Published var installedSkillIds: Set<String> = []
    @Published var isAnalyzing = false
    @Published var isExporting = false
    @Published var analysisComplete = false
    @Published var errorMessage: String?
    @Published var analyzedDays = 7
    @Published var primaryRole = ""
    @Published var selectedCategory: SkillRecommendation.SkillCategory?
    @Published var generationStatus: String = ""
    @Published var lastGenerationMode: GenerationMode = .ruleBased

    enum GenerationMode {
        case ruleBased
        case llm(model: String)

        var label: String {
            switch self {
            case .ruleBased: return "规则推荐"
            case .llm(let m): return "LLM · \(m)"
            }
        }
    }

    private var insightEngine: InsightEngine?

    func analyze(using analytics: AnalyticsEngine, days: Int = 7) {
        isAnalyzing = true
        errorMessage = nil
        analysisComplete = false
        generationStatus = "正在分析使用画像…"

        let engine = InsightEngine(analytics: analytics)
        insightEngine = engine

        Task {
            let result = await engine.analyze(days: days)

            insights = result.insights
            analyzedDays = result.analyzedDays
            primaryRole = result.workflowProfile.primaryRole

            let llmEnabled = UserDefaults.standard.bool(forKey: SentinelConstants.UserDefaultsKeys.llmEnabled)
            let model = UserDefaults.standard.string(forKey: SentinelConstants.UserDefaultsKeys.llmModel)
                ?? SentinelConstants.LLMDefaults.defaultModel
            let apiKey = KeychainHelper.get(account: KeychainAccount.openAIAPIKey) ?? ""

            if llmEnabled && !apiKey.isEmpty {
                generationStatus = "正在调用 \(model) 为你定制 Skills…"
                let client = OpenAIClient(apiKey: apiKey, model: model)
                do {
                    let llmRecs = try await SkillCatalog.recommendWithLLM(
                        from: result, analytics: analytics, days: days, client: client
                    )
                    recommendations = llmRecs
                    lastGenerationMode = .llm(model: model)
                    generationStatus = "由 \(model) 生成"
                } catch {
                    errorMessage = "LLM 生成失败，已回退到规则推荐：\(error.localizedDescription)"
                    recommendations = SkillCatalog.recommend(from: result)
                    lastGenerationMode = .ruleBased
                    generationStatus = "规则推荐（LLM 调用失败）"
                }
            } else {
                if llmEnabled && apiKey.isEmpty {
                    errorMessage = "已开启 LLM 模式但未配置 API Key，使用规则推荐。"
                }
                recommendations = SkillCatalog.recommend(from: result)
                lastGenerationMode = .ruleBased
                generationStatus = "规则推荐"
            }

            installedSkillIds = SkillGenerator.installedSkillIds()
            isAnalyzing = false
            analysisComplete = true
        }
    }

    var filteredRecommendations: [SkillRecommendation] {
        guard let cat = selectedCategory else { return recommendations }
        return recommendations.filter { $0.category == cat }
    }

    var usedCategories: [SkillRecommendation.SkillCategory] {
        let cats = Set(recommendations.map(\.category))
        return SkillRecommendation.SkillCategory.allCases.filter { cats.contains($0) }
    }

    func exportSkill(_ skill: SkillRecommendation) {
        let result = SkillGenerator.exportSkill(skill)
        exportResults.append(result)
        if result.success {
            installedSkillIds.insert(skill.skillId)
        }
    }

    func exportAllCustom() {
        isExporting = true
        let customs = recommendations.filter { !$0.isBuiltIn && !$0.skillMarkdown.isEmpty }
        let results = SkillGenerator.exportAll(customs)
        exportResults.append(contentsOf: results)
        for r in results where r.success {
            installedSkillIds.insert(r.skillId)
        }
        isExporting = false
    }

    func removeSkill(_ skillId: String) {
        if SkillGenerator.removeSkill(skillId) {
            installedSkillIds.remove(skillId)
        }
    }

    func isInstalled(_ skill: SkillRecommendation) -> Bool {
        installedSkillIds.contains(skill.skillId)
    }
}
