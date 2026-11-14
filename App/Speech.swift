import AVFoundation
import Speech
import SwiftUI

// Распознаёт русскую речь прямо на телефоне и отдаёт текст.
@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published var text = ""
    @Published var isRecording = false
    @Published var error: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start() async {
        error = nil
        let speechOK = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        let micOK = await AVAudioApplication.requestRecordPermission()
        guard speechOK, micOK else {
            error = "Нужен доступ к микрофону и распознаванию речи: Настройки → AutoNote."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            error = "Распознавание речи сейчас недоступно."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            request = req

            Self.installTap(on: engine, request: req)
            engine.prepare()
            try engine.start()
            text = ""
            isRecording = true

            task = Self.recognize(with: recognizer, request: req) { [weak self] said, finished in
                Task { @MainActor in
                    guard let self else { return }
                    if let said { self.text = said }
                    if finished { self.stop() }
                }
            }
        } catch {
            self.error = "Не получилось включить микрофон: \(error.localizedDescription)"
            stop()
        }
    }

    // Эти колбэки iOS вызывает не на главном потоке, поэтому они вынесены из @MainActor.
    nonisolated private static func installTap(on engine: AVAudioEngine, request: SFSpeechAudioBufferRecognitionRequest) {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    nonisolated private static func recognize(with recognizer: SFSpeechRecognizer,
                                              request: SFSpeechAudioBufferRecognitionRequest,
                                              update: @escaping @Sendable (String?, Bool) -> Void) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, err in
            update(result?.bestTranscription.formattedString, err != nil || (result?.isFinal ?? false))
        }
    }

    func stop() {
        guard isRecording || engine.isRunning else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
