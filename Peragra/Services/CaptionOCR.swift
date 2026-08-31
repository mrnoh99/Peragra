import UIKit
import Vision

/// On-device text recognition (Apple's Vision framework — no network call,
/// no API key) for reading an Instagram caption off a screenshot, so people
/// can snap a photo of the caption instead of copy-pasting it by hand.
enum CaptionOCR {
    enum OCRError: LocalizedError, Equatable {
        case invalidImage
        case noText

        var errorDescription: String? {
            switch self {
            case .invalidImage:
                return "Couldn't read that image."
            case .noText:
                return "Couldn't find any readable text in that image."
            }
        }
    }

    static func recognizeText(in image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        let text: String = try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ko-KR", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OCRError.noText
        }
        return text
    }
}
