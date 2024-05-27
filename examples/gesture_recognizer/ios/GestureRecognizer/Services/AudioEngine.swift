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

    // AV Audio player for the other chord degrees (TODO: Should be an array in the end)
//    private var harmoniesBuffer = [AVAudioPCMBuffer]()
//    private var harmoniesPlayer = [AVAudioPlayerNode]()
    private var harmoniesPlayer = AVAudioPlayerNode()
    private var harmoniesMixer = AVAudioMixerNode()
    private var harmoniesMixerArray = [AVAudioMixerNode]()
    
    var matrixMixer1 : AVAudioUnit?

    // Chord voicing number and cent offsets
    private var chordSize: Int
    private var chordPitchShifts: [Float]

    private var avAudioEngine = AVAudioEngine()
    private var audioUnitTimePitch = [AVAudioUnitTimePitch]()

//    private var audioRecorder = AVAudioRecorder()
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
            self.harmoniesMixerArray.append(AVAudioMixerNode())
//            self.harmoniesBuffer.append(AVAudioPCMBuffer())
//            self.harmoniesPlayer.append(AVAudioPlayerNode())
        }
        
        instantiateMatrixMixer()

//        self.audioRecorder = try AVAudioRecorder(url: recordedFileURL, format: self.voiceIOFormat)
//        self.audioRecorder.isMeteringEnabled = true
//        self.audioRecorder.prepareToRecord()

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
        // Pitch up the recoded voice
        for ix in 0..<min(self.chordSize-1, MAX_CHORD_VOICES)
        {
            audioUnitTimePitch[ix].pitch = self.chordPitchShifts[ix]
            //                harmoniesPlayer[ix].scheduleBuffer(harmoniesBuffer[ix], at: nil) //, options: .loops)
            //                harmoniesPlayer[ix].scheduleBuffer(voiceBuffer, at: nil) //, options: .loops)
            //                harmoniesPlayer[ix].play()
        }
    }

    func setChordMode(chordType: String)
    {
        chordGenerator(chordType: chordType)
        setupPitchShifters()
    }

    func instantiateMatrixMixer() 
    {
        
        let kAudioComponentFlag_SandboxSafe: UInt32 = 2
        let   mixerDesc =   AudioComponentDescription(componentType: kAudioUnitType_Mixer, componentSubType: kAudioUnitSubType_MatrixMixer, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: kAudioComponentFlag_SandboxSafe, componentFlagsMask: 0)
        
        
        AVAudioUnit.instantiate(with: mixerDesc)
        { avAudioUnit, error in
            
            self.matrixMixer1 = avAudioUnit
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
        
        let outputFormat = avAudioEngine.outputNode.outputFormat(forBus: 0)
        print("Channels count:", outputFormat.channelCount)

        let output = avAudioEngine.outputNode
        let mainMixer = avAudioEngine.mainMixerNode

        avAudioEngine.attach(voicePlayer)
//        avAudioEngine.attach(harmoniesMixer)
//        avAudioEngine.attach(matrixMixer1!)
//
////        for (harmPlayer, auPitchShift) in zip(harmoniesPlayer, audioUnitTimePitch)
////        {
////            avAudioEngine.attach(harmPlayer)
////            avAudioEngine.attach(auPitchShift)
////            avAudioEngine.connect(harmPlayer, to: auPitchShift, format: voiceIOFormat)
////            avAudioEngine.connect(auPitchShift, to: mainMixer, format: voiceIOFormat)
////
////        }
//        avAudioEngine.attach(harmoniesPlayer)
//        for ix in 0..<self.MAX_CHORD_VOICES
//        {
//            avAudioEngine.attach(harmoniesMixerArray[ix])
//            avAudioEngine.attach(audioUnitTimePitch[ix])
//            avAudioEngine.connect(harmoniesPlayer, to: audioUnitTimePitch[ix], format: voiceIOFormat)
//            avAudioEngine.connect(audioUnitTimePitch[ix], to: harmoniesMixerArray[ix], format: voiceIOFormat)
//            avAudioEngine.connect(harmoniesMixerArray[ix], to: mainMixer, format: voiceIOFormat)
//            
//
////            avAudioEngine.connect(auPitchShift, to: matrixMixer1!, format: voiceIOFormat)
//
//        }
//        harmoniesMixerArray[0].volume  = 0.2
//        harmoniesMixerArray[1].volume  = 1.0

        avAudioEngine.connect(voicePlayer, to: mainMixer, format: voiceIOFormat)

        for auPitchShift in audioUnitTimePitch
        {
            avAudioEngine.attach(auPitchShift)
            avAudioEngine.connect(voicePlayer, to: auPitchShift, format: voiceIOFormat)
            avAudioEngine.connect(auPitchShift, to: mainMixer, format: voiceIOFormat)
        }
//        avAudioEngine.attach(audioUnitTimePitch[0])
//        avAudioEngine.connect(harmoniesPlayer, to: audioUnitTimePitch[0], format: voiceIOFormat)
//        avAudioEngine.connect(audioUnitTimePitch[0], to: mainMixer, fromBus: 0, toBus: 0, format: voiceIOFormat)
//        
//        avAudioEngine.attach(audioUnitTimePitch[1])
//        avAudioEngine.connect(harmoniesPlayer, to: audioUnitTimePitch[1], format: voiceIOFormat)
//        avAudioEngine.connect(audioUnitTimePitch[1], to: mainMixer, fromBus: 0, toBus: 1, format: voiceIOFormat)
//
//        avAudioEngine.connect(harmoniesMixer, to: mainMixer, format: voiceIOFormat)

        avAudioEngine.connect(mainMixer, to: output, format: voiceIOFormat)

//        avAudioEngine.connect(matrixMixer1!, to: output, format: voiceIOFormat)

        mainMixer.volume  = 1.0
//        input.installTap(onBus: 0, bufferSize: 1024, format: voiceIOFormat)
//        {
//            buffer, when in
//                self.voiceBuffer = buffer
//
//                if (self.chordSize > 0)
//                {
////                    for ix in 0..<min(self.chordSize, self.MAX_CHORD_VOICES)
////                    {
////                        self.harmoniesBuffer[ix] = self.voiceBuffer.copy() as! AVAudioPCMBuffer
////                    }
//                }
//
//                self.harmoniesPlayer.prepare(withFrameCount: self.voiceBuffer.frameLength)
//            
//
//                AudioUnitSetParameter(self.matrixMixer1!.audioUnit, kMatrixMixerParam_Volume, kAudioUnitScope_Global, 0xFFFFFFFF, 1.0, 0);
//                for ix in 0..<self.MAX_CHORD_VOICES
//                {
//                    AudioUnitSetParameter(self.matrixMixer1!.audioUnit, kMatrixMixerParam_Volume, kAudioUnitScope_Output, AudioUnitElement(ix), 1.0, 0);
//                }
//                AudioUnitSetParameter(self.matrixMixer1!.audioUnit, kMatrixMixerParam_Volume, kAudioUnitScope_Output, 1, 1.0, 0);
//                AudioUnitSetParameter(self.matrixMixer1!.audioUnit, kMatrixMixerParam_Volume, kAudioUnitScope_Input, 0, 1.0, 0);
//
//                let matrixIn : UInt32 = 0
////                let matrixOut : UInt32 = 0
//                for matrixOut in 0..<self.MAX_CHORD_VOICES
//                {
//                    let crossPoint : UInt32  = UInt32((matrixIn << 16)) | UInt32((matrixOut & 0x0000FFFF));
//                    AudioUnitSetParameter(self.matrixMixer1!.audioUnit, kMatrixMixerParam_Volume, kAudioUnitScope_Global, crossPoint, 1.0, 0);
//                }
//                self.harmoniesPlayerPlay()
//        }
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

    func harmoniesPlayerPlay()
    {
        // Pitch up the recoded voice
        for ix in 0..<min(self.chordSize-1, MAX_CHORD_VOICES)
        {
            audioUnitTimePitch[ix].pitch = self.chordPitchShifts[ix]
//                harmoniesPlayer[ix].scheduleBuffer(harmoniesBuffer[ix], at: nil) //, options: .loops)
//                harmoniesPlayer[ix].scheduleBuffer(voiceBuffer, at: nil) //, options: .loops)
//                harmoniesPlayer[ix].play()
        }
//        harmoniesPlayer.scheduleBuffer(voiceBuffer, at: nil)
//        harmoniesPlayer.play()

//        for ix in min(self.chordSize-1, MAX_CHORD_VOICES)..<MAX_CHORD_VOICES
//        {
//            harmoniesPlayer[ix].play()
//        }
        self.setHarmonyPlayerState(true)
    }

    func harmoniesPlayerStop()
    {
        harmoniesPlayer.stop()
        self.setHarmonyPlayerState(false)
            //            for ix in min(self.chordSize, MAX_CHORD_VOICES)..<MAX_CHORD_VOICES
            //            {
            //                harmoniesPlayer[ix].stop()
            //            }
    }

    func startRecording()
    {
        // Reset the file pointer to the start of the file
//        self.audioRecorder.prepareToRecord()
        // Then start recording
//        self.audioRecorder.record()
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
        //        for harmPlayer in harmoniesPlayer
        //        {
        //            harmPlayer.stop()
        //        }
        harmoniesPlayer.stop()
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
}
