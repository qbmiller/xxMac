import AppKit
import Foundation
import Vision

extension Notification.Name {
    static let clipboardOCRDidUpdate = Notification.Name("ClipboardOCRDidUpdate")
}

protocol ClipboardOCRRecognizing {
    func recognizeText(in imageURL: URL, languages: [String]) async throws -> String
}

final class VisionClipboardOCRRecognizer: ClipboardOCRRecognizing {
    func recognizeText(in imageURL: URL, languages: [String]) async throws -> String {
        guard let image = NSImage(contentsOf: imageURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ""
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            if !languages.isEmpty {
                request.recognitionLanguages = languages
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

final class ClipboardOCRManager {
    static let shared = ClipboardOCRManager()

    private let recognizer: ClipboardOCRRecognizing
    private let storage: ClipboardStorageManager
    private let notificationCenter: NotificationCenter

    init(
        recognizer: ClipboardOCRRecognizing = VisionClipboardOCRRecognizer(),
        storage: ClipboardStorageManager = .shared,
        notificationCenter: NotificationCenter = .default
    ) {
        self.recognizer = recognizer
        self.storage = storage
        self.notificationCenter = notificationCenter
    }

    func enqueueImageOCR(itemID: UUID, imageURL: URL, languages: [String]) {
        Task.detached(priority: .utility) { [recognizer, storage, notificationCenter] in
            do {
                let text = try await recognizer.recognizeText(in: imageURL, languages: languages)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                storage.updateImageOCR(
                    id: itemID,
                    text: text.isEmpty ? nil : text,
                    status: text.isEmpty ? .skipped : .ready
                )
            } catch {
                storage.updateImageOCR(id: itemID, text: nil, status: .failed)
            }

            notificationCenter.post(name: .clipboardOCRDidUpdate, object: nil)
        }
    }

    func recognizeImageNow(itemID: UUID, imageURL: URL, languages: [String]) async {
        do {
            let text = try await recognizer.recognizeText(in: imageURL, languages: languages)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            storage.updateImageOCR(
                id: itemID,
                text: text.isEmpty ? nil : text,
                status: text.isEmpty ? .skipped : .ready
            )
        } catch {
            storage.updateImageOCR(id: itemID, text: nil, status: .failed)
        }

        notificationCenter.post(name: .clipboardOCRDidUpdate, object: nil)
    }
}
