//
//  Microphone.swift
//

import Foundation
import AVFoundation
import AVKit
import AVFAudio
import TensorFlowLiteTaskAudio
import UIKit

class MicrophoneMonitor: ObservableObject
{
    // 1
    private var audioRecorder: AVAudioRecorder
    private var timer: Timer?

    private var audioEngine: AVAudioEngine

    // 2 - The SPICE model
    private var audioInterpreter: SPICE

    init?(audioInterpreter: SPICE)
    {
        var recorderSettings: [String:Any] =  [:]

        // 4 - Access the microphone
        let audioSession = AVAudioSession.sharedInstance()
        AVAudioApplication.requestRecordPermission {
            (isGranted) in
                if isGranted
                {
                    // Permission granted, proceed with accessing the microphone
                    recorderSettings = [
                        AVFormatIDKey: NSNumber(value: kAudioFormatAppleLossless),
                        AVSampleRateKey: 16000.0,
                        AVNumberOfChannelsKey: 1,
                        AVEncoderAudioQualityKey: AVAudioQuality.min.rawValue
                    ]
                }
                else
                {
                    fatalError("You must allow audio recording for this application to work")
                }
        }
        
                      do {
                            try AVAudioSession.sharedInstance().setAllowHapticsAndSystemSoundsDuringRecording(true)
                        } catch {}

        // 5 - Save the reference to the initialized SPICE model
        self.audioInterpreter = audioInterpreter

        // 6 - Set up a file to write the recording to (null in this case) and the recording settings
        let url = URL(fileURLWithPath: "/dev/null", isDirectory: true)

        // 7 Initialize the AudioEngine
        self.audioEngine = AVAudioEngine()

        // 8 - Set the recording settings and start monitoring
        do
        {
            audioRecorder = try AVAudioRecorder(url: url, settings: recorderSettings)
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [])
            try audioSession.setActive(true)

            startMonitoring()
        }
        catch
        {
            fatalError(error.localizedDescription)
        }
    }
    
    // 9 - function to start the monitoring
    private func startMonitoring()
    {
        // Try reading from Audio Engine node's buffer
        let inputNode = self.audioEngine.inputNode
        let bus = 0

        // Formats and alias for conversion
        let inputFormat = inputNode.inputFormat(forBus: bus)
        let desiredFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: true)
        let converter = AVAudioConverter(from: inputFormat, to: desiredFormat!)!

        // Tap the input node (microphone)
        inputNode.installTap(onBus: bus, bufferSize: 2048, format: inputFormat)
        {
            (buffer: AVAudioPCMBuffer!, _) in
                // Callback for triggering the conversion
                var newBufferAvailable = true
                let inputCallback: AVAudioConverterInputBlock = 
                    { inNumPackets, outStatus in
                        if newBufferAvailable {
                            outStatus.pointee = .haveData
                            newBufferAvailable = false
                            return buffer
                        } else {
                            outStatus.pointee = .noDataNow
                            return nil
                        }
                    }

                if (buffer != nil)
                {
                    // Conversion to 16 kHz sampling rate
                    var error: NSError?
                    let frameCapacity = AVAudioFrameCount(desiredFormat!.sampleRate)*buffer.frameLength / AVAudioFrameCount(buffer.format.sampleRate)
                    let convertedBuffer = AVAudioPCMBuffer(pcmFormat: desiredFormat!,
                                                           frameCapacity: frameCapacity)
                    let status = converter.convert(to: convertedBuffer!, error: &error, withInputFrom: inputCallback)
                    if (error != nil)
                    {
                        fatalError("Error converting buffer")
                    }
                    let convertedBufferLen = Int(convertedBuffer!.frameLength)

                    // Extract samples from the buffer
                    let floatBuffer = convertedBuffer!.floatChannelData![0]

                    // Run the SPICE model on the captured samples
                    do
                    {
                    if(status == AVAudioConverterOutputStatus.haveData)
                    {
                        let data = Data(bytes: floatBuffer, count: convertedBufferLen)
                        // Run SPICE model
//                        self.audioInterpreter.runModel(onBuffer: data)
                        // Run the pitch shifter
                        self.playbackWithPitchShift(buffer: buffer)
                        
                    }
                }
            }
        }

        do
        {
            try self.audioEngine.start()
        }
        catch
        {
            print("Error starting audio engine: \(error.localizedDescription)")
        }
        audioRecorder.isMeteringEnabled = true
        audioRecorder.record()

        // Set up a timer
        timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true, block:
            {
                (timer) in
                    // 9 - Update AVAudioRecorder meters and increment the number of samples
//                    self.audioRecorder.updateMeters()
//                    // TODO: model inference to get the current root frequency and update the colors
//                    self.powerSamples[self.currentSample] = self.audioRecorder.averagePower(forChannel: 0)
//                    self.currentSample = (self.currentSample + 1) % self.numPowerSamples
            }
        )
    }
    
    func pauseRecording()
    {
        audioRecorder.pause()
    }
    
    func stopRecording()
    {
        audioRecorder.stop()
    }
    
    
    func resumeRecording()
    {
        audioRecorder.record()
    }
    
    func playbackWithPitchShift(buffer: AVAudioPCMBuffer)
    {
        let url = audioRecorder.url

        do {
            let audioEngine = AVAudioEngine()
            let audioPlayerNode = AVAudioPlayerNode()
            let audioUnitTimePitch = AVAudioUnitTimePitch()

            audioEngine.attach(audioPlayerNode)
            audioEngine.attach(audioUnitTimePitch)
            
            let outputFormat = audioEngine.outputNode.outputFormat(forBus: 0)
            let bufferFormat = buffer.format
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: bufferFormat.sampleRate, channels: bufferFormat.channelCount, interleaved: bufferFormat.isInterleaved)
                
            audioEngine.connect(audioPlayerNode, to: audioUnitTimePitch, format: format) // Use audio file's format
            audioEngine.connect(audioUnitTimePitch, to: audioEngine.mainMixerNode, format: format) // Use audio file's format

            
            audioPlayerNode.scheduleBuffer(buffer, at: nil)

            let pitchShift: Float = 12.0 // 12 semitones = 1 octave
            audioUnitTimePitch.pitch = pitchShift

            try audioEngine.start()
            audioPlayerNode.play()

        } catch {
            print("Error playing audio with pitch shift: \(error.localizedDescription)")
        }
    }


    // 10 - deinitialize the class on exit
    deinit {
        timer?.invalidate()
        audioRecorder.stop()
    }
}
