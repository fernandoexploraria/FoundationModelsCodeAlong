/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A Playground for testing Foundation Models framework features.
*/
import FoundationModels
import Playgrounds

#Playground {
    let landmark = ModelData.landmarks[0]
   
    let instructions = Instructions {
        "Your job is to create a description for the \(landmark.name)."
    }
    
    let session = LanguageModelSession(
        instructions: instructions
    )
    
    let prompt = Prompt {
        "Generate an exciting description for \(landmark.name)."
    }
    
    let response = try await session.respond(to: prompt,
                                             generating: String.self,
                                             options: GenerationOptions(sampling: .greedy))
    
    let inspectSession = session
}
