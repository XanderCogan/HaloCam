//
//  VoiceCommandController.swift
//

import Foundation
import Speech
import AVFoundation

final class VoiceCommandController: NSObject {
    
    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    private let audioSession = AVAudioSession.sharedInstance()
    
    /// Called on main thread when we successfully map a command.
    var onIntentDetected: ((DroneIntent) -> Void)?
    
    private(set) var isListening: Bool = false
    
    // MARK: - Public
    
    func startListening() {
        if isListening { return }
        
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard let self = self else { return }
            
            guard status == .authorized else {
                print("Speech recognition not authorized: \(status.rawValue)")
                return
            }
            
            DispatchQueue.main.async {
                do {
                    try self.startRecognitionSession()
                    self.isListening = true
                } catch {
                    print("Failed to start recognition session: \(error)")
                    self.isListening = false
                }
            }
        }
    }
    
    func stopListening() {
        if !isListening { return }
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
    }
    
    // MARK: - Private
    
    private func startRecognitionSession() throws {
        // Cleanup any existing session
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Configure audio session for recording
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw NSError(domain: "VoiceCommandController",
                          code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create recognition request"])
        }
        
        recognitionRequest.shouldReportPartialResults = false
        
        let inputNode = audioEngine.inputNode
        
        // Ensure no duplicate taps
        inputNode.removeTap(onBus: 0)
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] (buffer, _) in
            self?.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            var isFinal = false
            
            if let result = result {
                isFinal = result.isFinal
                if result.isFinal {
                    let text = result.bestTranscription.formattedString
                    self.handleRecognizedText(text)
                }
            }
            
            if error != nil || isFinal {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                
                self.recognitionRequest = nil
                self.recognitionTask = nil
                self.isListening = false
                
                do {
                    try self.audioSession.setActive(false, options: .notifyOthersOnDeactivation)
                } catch {
                    print("Failed to deactivate audio session: \(error)")
                }
            }
        }
    }
    
    private func handleRecognizedText(_ text: String) {
        print("Recognized: \(text)")
        if let intent = DroneIntentParser.parse(text: text) {
            DispatchQueue.main.async {
                self.onIntentDetected?(intent)
            }
        } else {
            print("No intent matched for: \(text)")
        }
    }
}

