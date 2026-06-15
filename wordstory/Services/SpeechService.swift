import AVFoundation

/// Speaks vocabulary words using the built-in iOS speech synthesizer.
/// Offline, free, and supports both English and Traditional Chinese voices.
///
/// We pin the audio session to `.playback` with `.spokenAudio` mode so the
/// user hears the pronunciation even with the silent switch on — the user
/// just explicitly tapped a speaker button, they want the sound.
@MainActor
final class SpeechService {

    static let shared = SpeechService()

    private let synth = AVSpeechSynthesizer()

    private init() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers, .mixWithOthers]
            )
        } catch {
            // Not fatal — speech will still try, the session will just stay
            // in the default (.soloAmbient) and may be silenced by the ring
            // switch on some devices. Log so it's visible if it ever matters.
            print("[Speech] audio session config failed: \(error.localizedDescription)")
        }
    }

    /// Speak `text` in the given BCP-47 language code (e.g. "en-US" / "zh-TW").
    /// Cuts off any in-progress utterance so rapid taps feel responsive.
    func speak(_ text: String, language: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        synth.stopSpeaking(at: .immediate)

        do {
            try AVAudioSession.sharedInstance().setActive(true, options: [])
        } catch {
            print("[Speech] session activate failed: \(error.localizedDescription)")
        }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
            ?? AVSpeechSynthesisVoice(language: "en-US")
        // Read rate from UserDefaults so a future Settings slider can tune
        // without changes here. UserDefaults.double returns 0.0 when unset,
        // so we treat that as "not configured" and fall back to the default.
        let stored = UserDefaults.standard.double(forKey: "speechRate")
        utterance.rate = stored > 0 ? Float(stored) : 0.45

        synth.speak(utterance)
    }

    /// Used by the front-face speaker button to give a brief feedback pulse
    /// regardless of whether the audio actually starts (no permissions, no
    /// async setup). Exposed so callers can drive the visual independently.
    func stop() {
        synth.stopSpeaking(at: .immediate)
    }
}
