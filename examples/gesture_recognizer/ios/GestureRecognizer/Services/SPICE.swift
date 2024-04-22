//
//  SPICE.swift
//  SoundVisualizer
//
//  Created by Claire Courchene on 2/27/24.
//

import Foundation
import TensorFlowLite
import TensorFlowLiteTaskAudio

// Information about a model file or labels file.
typealias FileInfo = (name: String, extension: String)

class SPICE
{
    // Interpreter
    private let interpreter: Interpreter

    // SPICE outputs and derived values
    var currentFreq : Double?
    var currentCents : Double?

    var currentNoteNumber : Int?
    var currentNoteDegree : Int?
    var currentOctave : Int?
    var currentNoteName : String?

    private var classificationResultPitch: Data?
    private var classificationResultConf: Data?
    private var classificationTime: TimeInterval?

    @Published public var currentPitch : Float32 = 0
    {
        didSet
        {
        NotificationCenter.default.post(name: Notification.Name("AttributeDidChange"), object: nil)
        }
    }
    @Published public var currentConf : Float32 = 0
    {
        didSet
        {
        NotificationCenter.default.post(name: Notification.Name("AttributeDidChange"), object: nil)
        }
    }

    // A failable initializer for `SPICE`. A new instance is created if the model and
    init?(modelFileInfo: FileInfo, threadCount: Int, resultCount: Int, scoreThreshold: Float)
    {
        let modelFilename = modelFileInfo.name

        // Getting model path
        guard
            let modelPath = Bundle.main.path(forResource: modelFilename, ofType: modelFileInfo.extension)
        else
        {
            print("Failed to load the model file with name: \(modelFilename).")
            return nil
        }

        do
        {
            // Initialize an interpreter with the model.
            self.interpreter = try Interpreter(modelPath: modelPath)

            // Allocate memory for the model's input `Tensor`s.
            try interpreter.allocateTensors()
        }
        catch let error
        {
            print("Failed to create the classifier with error: \(error.localizedDescription)")
            return nil
        }
    }

    func runModel(onBuffer inputData: Data)
    {
        var inferenceTime = TimeInterval()
        do
        {
            let size = min(512, inputData.count/4)
            try interpreter.resizeInput(at: 0, to: Tensor.Shape([size/4]))
            try interpreter.allocateTensors()

            // Copy the input data to the input `Tensor`.
            try self.interpreter.copy(inputData.subdata(in: 0..<size), toInputAt: 0)

            // Get time before inference
            let startTime = Date().timeIntervalSince1970

            // Run inference by invoking the `Interpreter`.
            try self.interpreter.invoke()

            // Get the output `Tensor`
            let outputTensorPitch = try self.interpreter.output(at: 0)
            let outputTensorConf = try self.interpreter.output(at: 1)
        
            // Output SPICE results
            self.currentPitch = self.convertToFloat(data: outputTensorPitch.data)
            self.currentConf = self.convertToFloat(data: outputTensorConf.data)

            // Calculate inference time
            self.classificationTime = Date().timeIntervalSince1970 - startTime

        } catch let error {
            print("Failed to run the classifier with error: \(error.localizedDescription)")
        }
    }

    func output2hz(pitch: Float32) -> Double
    {
        let PT_OFFSET = 25.58
        let PT_SLOPE = 63.07
        let FMIN = 10.0
        let BINS_PER_OCTAVE = 12.0
        let cqt_bin = Double(pitch) * PT_SLOPE + PT_OFFSET
        return FMIN * pow(2,1.0 * cqt_bin / BINS_PER_OCTAVE)
    }

    func hz2NoteNumber(freq: Double) -> (Int?)
    {
        if freq == 0
        {
            return nil
        }
        let A4 = 440
        let C0 = Double(A4) * pow(2, -4.75)

        return Int(12 * log2(freq/C0)) + 1 // TODO: Revisit if necessary (+1?)
    }

    func noteNumber2DegOctCents(freq: Double, noteNumber: Int) -> (Int?, Int?, Double?)
    {
        let noteFreq = [16.35, 17.32, 18.35, 19.45, 20.6, 21.83, 23.12, 24.5, 25.96, 27.5, 29.14, 30.87]

        if freq == 0
        {
            return (nil, nil, nil)
        }
        var (octave, noteDegree) = noteNumber.quotientAndRemainder(dividingBy: 12)
        let perfectFreq = noteFreq[noteDegree] * pow(2, Double(octave))
        var cents = 1200 * log2(freq/perfectFreq)
        if cents <= -50
        {
            if noteDegree == 0
            {
                noteDegree = 11
                octave = octave - 1
            }
            else
            {
                noteDegree = noteDegree - 1
            }
            cents = cents + 100
        }

        noteDegree = noteDegree + 1 // TODO: see if this is necessary
        if noteDegree == 12
        {
            noteDegree = 0
            octave = octave + 1
        }

        return (noteDegree, octave, cents)
    }

    private func convertToFloat(data: Data) -> Float32
    {
        let firstFourBytes = data.prefix(4)
            // Combine the first 4 bytes into a single UInt32
        let combinedUInt32: UInt32 = firstFourBytes.enumerated().reduce(0)
        {
            result, tuple in
            let (index, byte) = tuple
            return result | UInt32(byte) << (8 * index)
        }

        // Interpret the combined UInt32 as a Float32
        let floatValue = Float32(bitPattern: combinedUInt32)
        return floatValue
    }
}

