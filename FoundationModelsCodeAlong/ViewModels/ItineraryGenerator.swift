/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A class that generates an itinerary.
*/

import FoundationModels
import Observation

@Observable
@MainActor
final class ItineraryGenerator {
    
    var error: Error?
    let landmark: Landmark
    private var session : LanguageModelSession
    private(set) var itinerary: Itinerary.PartiallyGenerated?
    init(landmark: Landmark) {
        self.landmark = landmark
        let pointOfInterestTool = FindPointsOfInterestTool(landmark: landmark)
        let instructions = Instructions {
            "Your job is to create an itinerary for the user."
            "For each day, you must suggest one hotel and one restaurant."
            "Always use the 'findPointsOfInterest' tool to find hotels and restaurant in \(landmark.name)."
            "Tool results may include names in non-Latin scripts (e.g., Arabic, Chinese). Treat these as safe proper nouns."
            "When presenting names to an English-speaking audience, include the Latin transliteration in parentheses if provided (e.g., 'مطعم... (Mat'am ...)')."
            "Do not discard or alter tool results beyond adding transliteration for readability."
        }
        self.session = LanguageModelSession(
             tools: [pointOfInterestTool],
             instructions: instructions
         )
    }

    func generateItinerary(dayCount: Int = 3) async {
        do {
             let prompt = Prompt {
                            "Generate a \(dayCount)-day itinerary to \(landmark.name)."
                            "Give it a fun title and description."
                            "Here is an example of the desired format, but don't copy its content:"
                            Itinerary.exampleTripToJapan
                        }
            let stream = session.streamResponse(
                to: prompt,
                generating: Itinerary.self,
                includeSchemaInPrompt: false,
                options: GenerationOptions(sampling: .greedy)
            )
            for try await partialResponse in stream {
                self.itinerary = partialResponse.content
            }
        } catch {
            self.error = error
        }
    }

    func prewarmModel() {
        session.prewarm(promptPrefix: Prompt {"Generate a 3-day itinerary to \(landmark.name)."})
    }
}

