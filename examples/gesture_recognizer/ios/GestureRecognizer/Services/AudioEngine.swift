/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The class for handling AVAudioEngine.
*/

import AVFoundation
import Foundation

class AudioEngine
{
    private let MAX_CHORD_VOICES = 8

    private var recordedFileURL = URL(fileURLWithPath: "input.mic", isDirectory: false, relativeTo: URL(fileURLWithPath: NSTemporaryDirectory()))

    // AV Audio player for the recorder voice input
    private var voiceBuffer =  AVAudioPCMBuffer()
    private var voicePlayer = AVAudioPlayerNode()

    // AV Audio player for the other chord degrees (TODO: Should be an array in the end)
    private var harmoniesBuffer = [AVAudioPCMBuffer()]
    private var harmoniesPlayer = [AVAudioPlayerNode()]
    private var harmoniesMixer = AVAudioMixerNode()

    // Chord voicing number and cent offsets
    private var chordSize: Int
    private var chordPitchShifts: [Float]

    private var avAudioEngine = AVAudioEngine()
    private var audioUnitTimePitch = [AVAudioUnitTimePitch()]

    private var isNewRecordingAvailable = false
    private var recordedFile: AVAudioFile?

    public private(set) var voiceIOFormat: AVAudioFormat
    public private(set) var isRecording = false
    public private(set) var isPlayingVoice = false
    public private(set) var isPlayingHarmonies = false

    enum AudioEngineError: Error
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

        self.chordSize = 0
        self.chordPitchShifts = Array(repeating: 0.0, count: MAX_CHORD_VOICES)
        self.audioUnitTimePitch = Array(repeating: AVAudioUnitTimePitch(), count: MAX_CHORD_VOICES)
        self.harmoniesBuffer = Array(repeating: AVAudioPCMBuffer(), count: MAX_CHORD_VOICES)
        self.harmoniesPlayer = Array(repeating: AVAudioPlayerNode(), count: MAX_CHORD_VOICES)

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

    func chordGenerator(chordType: String)
    {
        switch (chordType)
        {
            // Chord size includes root note, pitch shifts do not
            case "Major":
                self.chordSize = 3
                self.chordPitchShifts = [400, 700]

            case "Minor":
                self.chordSize = 3
                self.chordPitchShifts = [300, 700]

            case "Dom7":
                self.chordSize = 4
                self.chordPitchShifts = [400, 700, 1000]

            case "Dim7":
                self.chordSize = 4
                self.chordPitchShifts = [300, 600, 900];

            default:
                self.chordSize = 1
                self.chordPitchShifts = [0]
        }
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

        avAudioEngine.attach(harmoniesMixer)

        for (harmPlayer, auPitchShift) in zip(harmoniesPlayer, audioUnitTimePitch)
        {
            avAudioEngine.attach(harmPlayer)
            avAudioEngine.attach(auPitchShift)
            avAudioEngine.connect(harmPlayer, to: auPitchShift, format: voiceIOFormat)
            avAudioEngine.connect(auPitchShift, to: harmoniesMixer, format: voiceIOFormat)

        }

        avAudioEngine.connect(harmoniesMixer, to: mainMixer, format: voiceIOFormat)

        avAudioEngine.connect(mainMixer, to: output, format: voiceIOFormat)

        mainMixer.volume  = 1.0

        input.installTap(onBus: 0, bufferSize: 1024, format: voiceIOFormat)
        {
            buffer, when in
                self.voiceBuffer = buffer
//                self.voicePlayerPlay()
                if (self.chordSize > 0)
                {
                    for ix in 0..<self.chordSize-1
                    {
                        self.harmoniesBuffer[ix] = self.voiceBuffer.copy() as! AVAudioPCMBuffer
                    }
                }
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
        for harmPlayer in harmoniesPlayer
        {
            harmPlayer.stop()
        }
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
            // Pitch up the recoded voice
            for ix in 0...0//chordPitchShifts.indices
            {
                audioUnitTimePitch[ix].pitch = self.chordPitchShifts[ix]
                harmoniesPlayer[ix].scheduleBuffer(harmoniesBuffer[ix], at: nil) //, options: .loops)
                harmoniesPlayer[ix].play()
            }
            for ix in self.chordSize-1..<MAX_CHORD_VOICES
            {
                harmoniesPlayer[ix].stop()
            }
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
