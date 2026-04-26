import Foundation
import UIKit

@Observable
@MainActor
final class GenerationViewModel {
    private(set) var suggestedChores: [ChoreDraft] = []
    private(set) var isGenerating = false
    private(set) var isSaving = false
    var jobId: String?
    var error: APIError?

    private let client = APIClient.shared

    func generateFromText(prompt: String, householdId: String) async {
        isGenerating = true
        defer { isGenerating = false }
        do {
            let response: GenerationResponse = try await client.send(
                path: "/households/\(householdId)/generate/text",
                method: "POST",
                body: TextGenerationBody(prompt: prompt, roomId: nil)
            )
            jobId = response.jobId
            suggestedChores = response.suggestedChores
        } catch let err as APIError {
            error = err
        } catch {
            self.error = .server(code: "INTERNAL", message: error.localizedDescription)
        }
    }

    func generateFromImage(_ image: UIImage, householdId: String) async {
        isGenerating = true
        defer { isGenerating = false }

        guard let imageData = resizeImageIfNeeded(image).jpegData(compressionQuality: 0.8) else {
            error = .server(code: "INTERNAL", message: "Could not encode image.")
            return
        }

        let base64 = imageData.base64EncodedString()
        do {
            let response: GenerationResponse = try await client.send(
                path: "/households/\(householdId)/generate/image",
                method: "POST",
                body: ImageGenerationBody(imageBase64: base64, mimeType: "image/jpeg", roomId: nil)
            )
            jobId = response.jobId
            suggestedChores = response.suggestedChores
        } catch let err as APIError {
            error = err
        } catch {
            self.error = .server(code: "INTERNAL", message: error.localizedDescription)
        }
    }

    func acceptChores(selectedIndices: Set<Int>, householdId: String) async -> [APIChore]? {
        guard let jobId else { return nil }
        isSaving = true
        defer { isSaving = false }
        do {
            let chores: [APIChore] = try await client.send(
                path: "/households/\(householdId)/generate/\(jobId)/accept",
                method: "POST",
                body: AcceptGenerationBody(acceptedIndices: Array(selectedIndices).sorted())
            )
            return chores
        } catch let err as APIError {
            error = err
            return nil
        } catch {
            self.error = .server(code: "INTERNAL", message: error.localizedDescription)
            return nil
        }
    }

    private func resizeImageIfNeeded(_ image: UIImage, maxDimension: CGFloat = 1280) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
