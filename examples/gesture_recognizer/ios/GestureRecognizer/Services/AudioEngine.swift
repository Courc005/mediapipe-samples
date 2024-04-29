/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The class for handling AVAudioEngine.
*/

import AVFoundation
import Foundation

class AudioEngine {

    private var recordedFileURL = URL(fileURLWithPath: "input.mic", isDirectory: false, relativeTo: URL(fileURLWithPath: NSTemporaryDirectory()))

    // AV Audio player for the recorder voice input
    private var voiceBuffer =  AVAudioPCMBuffer()
    private var voicePlayer = AVAudioPlayerNode()

    // AV Audio player for the other chord degrees (TODO: Should be an array in the end)
    private var harmoniesBuffer = AVAudioPCMBuffer()
    private var harmoniesPlayer = AVAudioPlayerNode()
    private var harmoniesMixer = AVAudioMixerNode()

    private var avAudioEngine = AVAudioEngine()
    private var audioUnitTimePitch = AVAudioUnitTimePitch()

    private var isNewRecordingAvailable = false
    private var recordedFile: AVAudioFile?

    public private(set) var voiceIOFormat: AVAudioFormat
    public private(set) var isRecording = false
    public private(set) var isPlayingVoice = false
    public private(set) var isPlayingHarmonies = false

    enum AudioEngineError: Error {
        case bufferRetrieveError
        case fileFormatError
        case audioFileNotFound
    }

    enum ChordType: Error
    {
        case bufferRetrieveError
        case fileFormatError
        case audioFileNotFound
    }

    init() throws
    {
        print("Record file URL: \(recordedFileURL.absoluteString)")

        voiceIOFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                      sampleRate: 16000,
                                      channels: 1,
                                      interleaved: true)!


        NotificationCenter.default.addObserver(self,
                                               selector: #selector(configChanged(_:)),
                                               name: .AVAudioEngineConfigurationChange,
                                               object: avAudioEngine)
    }

    @objc
    func configChanged(_ notification: Notification)
    {
        checkEngineIsRunning()
    }

    private static func getBuffer(fileURL: URL) -> AVAudioPCMBuffer?
    {
        let file: AVAudioFile!
        do
        {
            try file = AVAudioFile(forReading: fileURL)
        } catch
        {
            print("Could not load file: \(error)")
            return nil
        }
        file.framePosition = 0
        
        // Add 100 ms to the capacity.
        let bufferCapacity = AVAudioFrameCount(file.length)
                + AVAudioFrameCount(file.processingFormat.sampleRate * 0.1)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: bufferCapacity) else { return nil }
        do
        {
            try file.read(into: buffer)
        } catch
        {
            print("Could not load file into buffer: \(error)")
            return nil
        }
        file.framePosition = 0
        return buffer
    }

    func setup()
    {
        let input = avAudioEngine.inputNode
        do
        {
            try input.setVoiceProcessingEnabled(true)
        } catch
        {
            print("Could not enable voice processing \(error)")
            return
        }

        let output = avAudioEngine.outputNode
        let mainMixer = avAudioEngine.mainMixerNode


        avAudioEngine.attach(harmoniesPlayer)
        avAudioEngine.attach(harmoniesMixer)
        avAudioEngine.attach(audioUnitTimePitch)
        avAudioEngine.attach(voicePlayer)

        avAudioEngine.connect(harmoniesPlayer, to: audioUnitTimePitch, format: voiceIOFormat)
        avAudioEngine.connect(audioUnitTimePitch, to: harmoniesMixer, format: voiceIOFormat)

        avAudioEngine.connect(voicePlayer, to: mainMixer, format: voiceIOFormat)
        avAudioEngine.connect(harmoniesMixer, to: mainMixer, format: voiceIOFormat)

        avAudioEngine.connect(mainMixer, to: output, format: voiceIOFormat)

        mainMixer.volume  = 1.0

        input.installTap(onBus: 0, bufferSize: 1024, format: voiceIOFormat)
        {
            buffer, when in
                self.voiceBuffer = buffer
                self.voicePlayerPlay()
                self.harmoniesPlayerPlay()

        }
        avAudioEngine.prepare()
    }

    func start()
    {
        do
        {
            try avAudioEngine.start()
        } catch
        {
            print("Could not start audio engine: \(error)")
        }
    }

    func checkEngineIsRunning()
    {
        if !avAudioEngine.isRunning
        {
            start()
        }
    }

    func setRecordingState(_ state: Bool)
    {
        self.isRecording = state
    }

    func stopRecordingAndPlayers()
    {
        if isRecording
        {
            isRecording = false
        }

        voicePlayer.stop()
        harmoniesPlayer.stop()
        self.isPlayingVoice = false
        self.isPlayingHarmonies = false
    }

    func voicePlayerPlay() 
    {
        if self.isPlayingVoice
        {
            voicePlayer.scheduleBuffer(voiceBuffer, at: nil)//, options: .loops)
            voicePlayer.play()
        }
    }

    func harmoniesPlayerPlay()
    {
        if self.isPlayingHarmonies
        {
            // Pitch up the recoded voice (TODO: according to chord degree)
            audioUnitTimePitch.pitch = Float(1200)
            let harmonyBuffer = voiceBuffer
            harmoniesPlayer.scheduleBuffer(harmonyBuffer, at: nil)//, options: .loops)
//            harmoniesPlayer.scheduleBuffer(voiceBuffer, at: nil)//, options: .loops)
            harmoniesPlayer.play()
        }
    }

    func setVoicePlayerState(_ state: Bool)
    {
        self.isPlayingVoice = state
    }

    func setHarmonyPlayerState(_ state: Bool)
    {
        self.isPlayingHarmonies = state
    }
}
