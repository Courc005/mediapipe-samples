/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The class for handling AVAudioEngine.
*/

import AVFoundation
import Foundation

class AudioEngine
{
    private let MAX_CHORD_VOICES = 3

    private var recordedFileURL = URL(fileURLWithPath: "input.mic", isDirectory: false, relativeTo: URL(fileURLWithPath: NSTemporaryDirectory()))

    // AV Audio player for the recorder voice input
    private var voiceBuffer =  AVAudioPCMBuffer()
    private var voicePlayer = AVAudioPlayerNode()

    // Chord voicing number and cent offsets
    private var chordName: String = "root"
    private var chordSize: Int
    private var chordPitchShifts: [Float]

    private var avAudioEngine = AVAudioEngine()
    private var audioUnitTimePitch = [AVAudioUnitTimePitch]()

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

        for _ in 0..<MAX_CHORD_VOICES
        {
            self.chordPitchShifts.append(0.0)
            self.audioUnitTimePitch.append(AVAudioUnitTimePitch())
        }

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(configChanged(_:)),
                                               name: .AVAudioEngineConfigurationChange,
                                               object: avAudioEngine)
    }

    private func getBuffer(fileURL: URL) -> AVAudioPCMBuffer?
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
        guard let buffer = AVAudioPCMBuffer(pcmFormat: voiceIOFormat,
                                            frameCapacity: bufferCapacity) else { return nil }
        do
        {
            try file.read(into: buffer)
        }
        catch
        {
            print("Could not load file into buffer: \(error)")
            return nil
        }
        file.framePosition = 0
        return buffer
    }

    @objc
    func configChanged(_ notification: Notification)
    {
        checkEngineIsRunning()
    }

    private func chordGenerator(chordType: String)
    {
        switch (chordType)
        {
            case "Major":
                self.chordSize = 3
                self.chordPitchShifts = [0, 400, 700]
                self.setHarmonyPlayerState(true)

            case "Minor":
                self.chordSize = 3
                self.chordPitchShifts = [0, 300, 700]
                self.setHarmonyPlayerState(true)

            case "Dom7":
                self.chordSize = 4
                self.chordPitchShifts = [0, 400, 700, 1000]
                self.setHarmonyPlayerState(true)

            case "Dim7":
                self.chordSize = 4
                self.chordPitchShifts = [0, 300, 600, 900];
                self.setHarmonyPlayerState(true)

            default:
                self.chordSize = 1
                self.chordPitchShifts = [0]
        }
    }

    private func setupPitchShifters()
    {
        // Connection points to all pitch shifters
        var connections: [AVAudioConnectionPoint] = Array(repeating: AVAudioConnectionPoint(node: voicePlayer, bus: 0), count: 0)

        avAudioEngine.disconnectNodeOutput(voicePlayer, bus: 0)
        for ix in 0..<MAX_CHORD_VOICES
        {
            // Disconnect existing pitch shifters
            if (avAudioEngine.attachedNodes.contains(audioUnitTimePitch[ix]))
            {
                avAudioEngine.disconnectNodeInput(audioUnitTimePitch[ix])
                avAudioEngine.disconnectNodeOutput(audioUnitTimePitch[ix])
            }

            // Pitch up the recoded voice
            if (ix < min(self.chordSize, MAX_CHORD_VOICES))
            {
                if (!avAudioEngine.attachedNodes.contains(audioUnitTimePitch[ix]))
                {
                    avAudioEngine.attach(audioUnitTimePitch[ix])
                }
                audioUnitTimePitch[ix].pitch = self.chordPitchShifts[ix]
                avAudioEngine.connect(audioUnitTimePitch[ix], to: avAudioEngine.mainMixerNode, format: voiceIOFormat)
                connections.append(AVAudioConnectionPoint(node: audioUnitTimePitch[ix], bus: 0))
            }
        }
        if (!connections.isEmpty)
        {
            avAudioEngine.connect(voicePlayer, to: connections, fromBus: 0, format: voiceIOFormat)
        }
    }

    func setChordMode(chordType: String)
    {
        self.chordName = chordType
        chordGenerator(chordType: self.chordName)
        setupPitchShifters()
        voicePlayerPlay()
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
        
        let outputFormat = avAudioEngine.outputNode.outputFormat(forBus: 0)
        print("Channels count:", outputFormat.channelCount)

        let output = avAudioEngine.outputNode
        let mainMixer = avAudioEngine.mainMixerNode

        avAudioEngine.attach(voicePlayer)

        avAudioEngine.attach(audioUnitTimePitch[0])
        avAudioEngine.connect(self.voicePlayer, to: audioUnitTimePitch[0], format: voiceIOFormat)
        avAudioEngine.connect(audioUnitTimePitch[0], to: mainMixer, fromBus: 0, toBus: 0, format: voiceIOFormat)

        avAudioEngine.connect(mainMixer, to: output, format: voiceIOFormat)

        mainMixer.volume  = 1.0

        self.avAudioEngine.prepare()
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

    func stopRecordingAndPlayers()
    {
        self.stopRecording()
        self.stopPlayers()
    }

    func voicePlayerPlay() 
    {
        voiceBuffer = self.getBuffer(fileURL: recordedFileURL)!
        voicePlayer.scheduleBuffer(voiceBuffer, at: nil, options: .loops)
        voicePlayer.play()
        self.setVoicePlayerState(true)
    }

    func voicePlayerStop()
    {
        voicePlayer.stop()
        self.setVoicePlayerState(false)
    }

    func startRecording()
    {

        if (!isRecording)
        {
            do
            {
                recordedFile = try AVAudioFile(forWriting: recordedFileURL, settings: voiceIOFormat.settings)
            }
            catch
            {
                print("Could not record file: \(error)")
            }
            avAudioEngine.inputNode.installTap(onBus: 0, bufferSize: 8192, format: voiceIOFormat)
            {
                buffer, when in
                if self.isRecording
                {
                    do
                    {
                        try self.recordedFile?.write(from: buffer)
                    }
                    catch
                    {
                        print("Could not write buffer: \(error)")
                    }
                }
            }
            self.setRecordingState(true)
        }
    }

    func stopRecording()
    {
        if (isRecording)
        {
            self.recordedFile = nil // close the file
            avAudioEngine.inputNode.removeTap(onBus: 0)
            self.setRecordingState(false)
        }
    }

    func stopPlayers()
    {
        voicePlayer.stop()
        self.setVoicePlayerState(false)
        self.setHarmonyPlayerState(false)
    }

    func setRecordingState(_ state: Bool)
    {
        self.isRecording = state
    }

    func setVoicePlayerState(_ state: Bool)
    {
        self.isPlayingVoice = state
    }

    func setHarmonyPlayerState(_ state: Bool)
    {
        self.isPlayingHarmonies = state
    }

    func getChordType() -> String
    {
        return self.chordName
    }
}
