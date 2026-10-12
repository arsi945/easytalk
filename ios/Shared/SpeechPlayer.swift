import Foundation
import AVFoundation

/// Uses installed system voices, never records audio or sends text to an AI speech API.
public final class SpeechPlayer: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var current: AVSpeechUtterance?
    private var ownsAudioSession = false
    public var onFinished: (() -> Void)?
    public override init() { super.init(); synth.delegate = self }
    @discardableResult public func speak(_ text: String, language: String = "en-US") -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let voice = AVSpeechSynthesisVoice(language: language) ?? AVSpeechSynthesisVoice.speechVoices().first(where: { $0.language.hasPrefix(String(language.prefix(2))) }) else { return false }
        current = nil; synth.stopSpeaking(at: .immediate)
        #if os(iOS)
        do { try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers]); try AVAudioSession.sharedInstance().setActive(true); ownsAudioSession = true }
        catch { return false }
        #endif
        let utterance = AVSpeechUtterance(string: text); utterance.voice = voice; utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        current = utterance; synth.speak(utterance); return true
    }
    public func stop() { current = nil; synth.stopSpeaking(at: .immediate); deactivate() }
    private func deactivate() {
        #if os(iOS)
        guard ownsAudioSession else { return }; ownsAudioSession = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif
    }
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { finish(utterance) }
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { finish(utterance) }
    private func finish(_ utterance: AVSpeechUtterance) { guard current === utterance else { return }; current = nil; deactivate(); onFinished?() }
}
