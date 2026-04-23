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

    private var insightEngine: InsightEngine?

    func analyze(using analytics: AnalyticsEngine, days: Int = 7) {
        isAnalyzing = true
        errorMessage = nil
        analysisComplete = false

        let engine = InsightEngine(analytics: analytics)
        insightEngine = engine

        Task {
            let result = await engine.analyze(days: days)

            insights = result.insights
            analyzedDays = result.analyzedDays
            primaryRole = result.workflowProfile.primaryRole

            recommendations = SkillCatalog.recommend(from: result)
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
