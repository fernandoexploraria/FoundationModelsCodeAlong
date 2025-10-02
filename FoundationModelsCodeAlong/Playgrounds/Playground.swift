/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A Playground for testing Foundation Models framework features.
*/
import FoundationModels
import Playgrounds

#Playground {
    let landmark = ModelData.landmarks[0]
    let pointOfInterestTool = FindPointsOfInterestTool(landmark: landmark)
    
    let instructions = Instructions {
        "Your job is to create an itinerary for the user."
        "For each day, you must suggest one hotel and one restaurant."
        "Always use the 'findPointsOfInterest' tool to find hotels and restaurants in \(landmark.name)"
    }
    
    let session = LanguageModelSession(
        tools: [pointOfInterestTool],
        instructions: instructions
    )
    
    let prompt = Prompt {
        "Generate a 3-day itinerary to \(landmark.name)."
        "Give it a fun title and description."
    }
    
    let response = try await session.respond(to: prompt,
                                             generating: Itinerary.self,
                                             options: GenerationOptions(sampling: .greedy))
    
    let inspectSession = session
}
