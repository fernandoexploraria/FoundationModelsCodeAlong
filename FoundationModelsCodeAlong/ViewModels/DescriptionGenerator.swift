import Foundation
import FoundationModels
import Observation

@Observable
@MainActor
final class DescriptionGenerator {
    
    var error: Error?
    let name: String
    private var session: LanguageModelSession
    private(set) var description: String?
    init(name: String) {
        self.name = name
        let instructions = "Your job is to create a description for a landmark."
        self.session = LanguageModelSession(instructions: instructions)
    }
    func generateDescription() async {
        do {
            let prompt = "Generate a brief and exciting description for \(name)."
            let response = try await session.respond(to: prompt)
            self.description = response.content
        } catch {
            self.error = error
        }
    }

    func prewarmModel() {
        session.prewarm(promptPrefix: Prompt {"Generate a brief and exciting description for \(name)."})
    }
}
