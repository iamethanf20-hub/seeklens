//
//  SpeechRecognizer.swift
//  Findly
//
//  Created by Lingling on 5/27/26.
//

import Foundation
import Speech
import AVFoundation

@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    @Published var errorText: String? = nil

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // MARK: - Permission

    func requestAuthorization() async -> Bool {
        let speechStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else { return false }

        let micStatus = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        return micStatus
    }

    // MARK: - Recording

    func start() async {
        guard !isRecording else { return }
        errorText = nil
        transcript = ""

        let ok = await requestAuthorization()
        guard ok else {
            errorText = "Microphone or speech permission denied. Enable in Settings."
            return
        }

        guard let recognizer = recognizer, recognizer.isAvailable else {
            errorText = "Speech recognizer unavailable."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            self.request = req

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true

            task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                guard let self = self else { return }
                if let result = result {
                    Task { @MainActor in
                        self.transcript = result.bestTranscription.formattedString
                    }
                }
                if error != nil || (result?.isFinal ?? false) {
                    Task { @MainActor in self.stop() }
                }
            }
        } catch {
            errorText = "Could not start recording: \(error.localizedDescription)"
            stop()
        }
    }

    func stop() {
        guard isRecording else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Query extraction (regex strip)

    /// Strips common command prefixes from a voice transcript.
    /// "find my keys" -> "keys"
    /// "where are the red pencils" -> "red pencils"
    /// "show me all erasers" -> "erasers"
    static func extractQuery(from transcript: String) -> String {
        var s = transcript.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Order matters: longest/most-specific phrases first.
        let prefixes = [
            "can you find me all of the",
            "can you find me all the",
            "can you find me a",
            "can you find me the",
            "can you find me",
            "can you find all of the",
            "can you find all the",
            "can you find the",
            "can you find a",
            "can you find",
            "can you show me all the",
            "can you show me the",
            "can you show me",
            "please find me all of the",
            "please find me all the",
            "please find me the",
            "please find me a",
            "please find me",
            "please find all of the",
            "please find all the",
            "please find the",
            "please find a",
            "please find",
            "find me all of the",
            "find me all the",
            "find me the",
            "find me a",
            "find me",
            "find all of the",
            "find all the",
            "find all",
            "find the",
            "find a",
            "find my",
            "find",
            "show me all of the",
            "show me all the",
            "show me the",
            "show me",
            "where are all of the",
            "where are all the",
            "where are the",
            "where are my",
            "where are",
            "where is the",
            "where is my",
            "where is",
            "where's the",
            "where's my",
            "where's",
            "locate the",
            "locate my",
            "locate",
            "look for all the",
            "look for the",
            "look for my",
            "look for"
        ]

        for p in prefixes {
            if s.hasPrefix(p + " ") {
                s = String(s.dropFirst(p.count + 1))
                break
            }
            if s == p {
                s = ""
                break
            }
        }

        // Trim trailing filler ("please", punctuation, etc.)
        let trailingTrash = [" please", " thanks", " thank you"]
        for t in trailingTrash {
            if s.hasSuffix(t) { s = String(s.dropLast(t.count)) }
        }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: " .,!?"))

        return s
    }
}
