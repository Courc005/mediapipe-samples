// Copyright 2023 The MediaPipe Authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import UIKit
import AVFoundation

// MARK: CameraFeedServiceDelegate Declaration
protocol CameraFeedServiceDelegate: AnyObject {

  /**
   This method delivers the pixel buffer of the current frame seen by the device's camera.
   */
  func didOutput(sampleBuffer: CMSampleBuffer, orientation: UIImage.Orientation)

  /**
   This method initimates that a session runtime error occured.
   */
  func didEncounterSessionRuntimeError()

  /**
   This method initimates that the session was interrupted.
   */
  func sessionWasInterrupted(canResumeManually resumeManually: Bool)

  /**
   This method initimates that the session interruption has ended.
   */
  func sessionInterruptionEnded()

}

/**
 This class manages all camera related functionality
 */
class CameraFeedService: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
  /**
   This enum holds the state of the camera initialization.
   */
  enum AVConfigurationStatus {
    case success
    case failed
    case permissionDenied
  }

  // MARK: Public Instance Variables
  var videoResolution: CGSize {
    get {
      guard let size = imageBufferSize else {
        return CGSize.zero
      }
      let minDimension = min(size.width, size.height)
      let maxDimension = max(size.width, size.height)
      switch UIDevice.current.orientation {
        case .portrait:
          return CGSize(width: minDimension, height: maxDimension)
        case .landscapeLeft:
          fallthrough
        case .landscapeRight:
          return CGSize(width: maxDimension, height: minDimension)
        default:
          return CGSize(width: minDimension, height: maxDimension)
      }
    }
  }

  let videoGravity = AVLayerVideoGravity.resizeAspectFill

  // MARK: Instance Variables
  private let session: AVCaptureSession = AVCaptureSession()
  private var audioEngine = AVAudioEngine()
  private var audioPlayer = AVAudioPlayerNode()
  private var audioUnitTimePitch = AVAudioUnitTimePitch()
    
    
  private lazy var videoPreviewLayer = AVCaptureVideoPreviewLayer(session: session)
  private let sessionQueue = DispatchQueue(label: "com.google.mediapipe.CameraFeedService.sessionQueue")
  private let cameraPosition: AVCaptureDevice.Position = .front

  private var avConfigurationStatus: AVConfigurationStatus = .failed
  private var microphoneConfigurationStatus: AVConfigurationStatus = .failed
  private lazy var videoDataOutput = AVCaptureVideoDataOutput()
  private lazy var audioDataOutput = AVCaptureAudioDataOutput()
  private var isSessionRunning = false
  private var imageBufferSize: CGSize?


  // MARK: CameraFeedServiceDelegate
  weak var delegate: CameraFeedServiceDelegate?

  // MARK: Initializer
  init(previewView: UIView) {
    super.init()

    // Initializes the session
    session.sessionPreset = .high
    setUpPreviewView(previewView)

    attemptToConfigureSession()
    NotificationCenter.default.addObserver(
      self, selector: #selector(orientationChanged),
      name: UIDevice.orientationDidChangeNotification,
      object: nil)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  private func setUpPreviewView(_ view: UIView) {
    videoPreviewLayer.videoGravity = videoGravity
    videoPreviewLayer.connection?.videoOrientation = .portrait
    view.layer.addSublayer(videoPreviewLayer)
  }

  // MARK: notification methods
  @objc func orientationChanged(notification: Notification) {
    switch UIImage.Orientation.from(deviceOrientation: UIDevice.current.orientation) {
    case .up:
      videoPreviewLayer.connection?.videoOrientation = .portrait
    case .left:
      videoPreviewLayer.connection?.videoOrientation = .landscapeRight
    case .right:
      videoPreviewLayer.connection?.videoOrientation = .landscapeLeft
    default:
      break
    }
  }

  // MARK: Session Start and End methods

  /**
   This method starts an AVCaptureSession based on whether the camera configuration was successful.
   */

  func startLiveCameraSession(_ completion: @escaping(_ cameraConfiguration: AVConfigurationStatus) -> Void) {
    sessionQueue.async {
      switch self.avConfigurationStatus {
      case .success:
        self.addObservers()
        self.startSession()
        default:
          break
      }
      completion(self.avConfigurationStatus)
    }
  }

  /**
   This method stops a running an AVCaptureSession.
   */
  func stopSession() {
    self.removeObservers()
    sessionQueue.async {
      if self.session.isRunning {
        self.session.stopRunning()
        self.isSessionRunning = self.session.isRunning
      }
    }

  }

  /**
   This method resumes an interrupted AVCaptureSession.
   */
  func resumeInterruptedSession(withCompletion completion: @escaping (Bool) -> ()) {
    sessionQueue.async {
      self.startSession()

      DispatchQueue.main.async {
        completion(self.isSessionRunning)
      }
    }
  }

  func updateVideoPreviewLayer(toFrame frame: CGRect) {
    videoPreviewLayer.frame = frame
  }

  /**
   This method starts the AVCaptureSession
   **/
  private func startSession() {
    self.session.startRunning()
    self.isSessionRunning = self.session.isRunning
  }

  // MARK: Session Configuration Methods.
  /**
   This method requests for camera permissions and handles the configuration of the session and stores the result of configuration.
   */
  private func attemptToConfigureSession() {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      self.avConfigurationStatus = .success
    case .notDetermined:
      self.sessionQueue.suspend()
      self.requestCameraAccess(completion: { (granted) in
        self.sessionQueue.resume()
      })
    case .denied:
      self.avConfigurationStatus = .permissionDenied
    default:
      break
    }
      
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
      case .authorized:
        self.avConfigurationStatus = .success
      case .notDetermined:
        self.sessionQueue.suspend()
        self.requestMicrophoneAccess(completion: { (granted) in
          self.sessionQueue.resume()
        })
      case .denied:
        self.avConfigurationStatus = .permissionDenied
      default:
        break
      }

    self.sessionQueue.async {
      self.configureSession()
    }
  }

  /**
   This method requests for camera permissions.
   */
  private func requestCameraAccess(completion: @escaping (Bool) -> ()) {
    AVCaptureDevice.requestAccess(for: .video) { (granted) in
      if !granted {
        self.avConfigurationStatus = .permissionDenied
      }
      else {
        self.avConfigurationStatus = .success
      }
      completion(granted)
    }
  }

    /**
     This method requests for camera permissions.
     */
    private func requestMicrophoneAccess(completion: @escaping (Bool) -> ()) {
      AVCaptureDevice.requestAccess(for: .audio) { (granted) in
        if !granted {
          self.avConfigurationStatus = .permissionDenied
        }
        else {
          self.avConfigurationStatus = .success
        }
        completion(granted)
      }
    }
    
  /**
   This method handles all the steps to configure an AVCaptureSession.
   */
  private func configureSession() {

    guard avConfigurationStatus == .success else {
      return
    }
    session.beginConfiguration()

    // Tries to add an AVCaptureDeviceInput for video.
    guard addVideoDeviceInput() == true else {
      self.session.commitConfiguration()
      self.avConfigurationStatus = .failed
      return
    }
      
    // Tries to add an AVCaptureDeviceInput for audio.
    guard addAudioDeviceInput() == true else {
        self.session.commitConfiguration()
        self.avConfigurationStatus = .failed
        return
      }

    // Tries to add an AVCaptureVideoDataOutput.
    guard addVideoDataOutput() else {
      self.session.commitConfiguration()
      self.avConfigurationStatus = .failed
      return
    }
      
    // Tries to add an AVCaptureAudioDataOutput.
    guard setupAudioPlayback() else {
      self.session.commitConfiguration()
      self.avConfigurationStatus = .failed
      return
    }

    session.commitConfiguration()
    self.avConfigurationStatus = .success
  }

  /**
   This method tries to an AVCaptureDeviceInput to the current AVCaptureSession.
   */
  private func addVideoDeviceInput() -> Bool {

    /**Tries to get the default back camera.
     */
    guard let camera  = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition) else {
      return false
    }

    do {
      let videoDeviceInput = try AVCaptureDeviceInput(device: camera)
      if session.canAddInput(videoDeviceInput) {
        session.addInput(videoDeviceInput)
        return true
      }
      else {
        return false
      }
    }
    catch {
      fatalError("Cannot create video device input")
    }
  }

    /**
     This method tries to an AVCaptureDeviceInput to the current AVCaptureSession.
     */
    private func addAudioDeviceInput() -> Bool {

      /**Tries to get the default microphone.
       */
      guard let microphone  = AVCaptureDevice.default(for: .audio) else {
        return false
      }

      do {
        let audioDeviceInput = try AVCaptureDeviceInput(device: microphone)
        if session.canAddInput(audioDeviceInput) {
          session.addInput(audioDeviceInput)
          return true
        }
        else {
          return false
        }
      }
      catch {
        fatalError("Cannot create audio device input")
      }
    }
  /**
   This method tries to an AVCaptureVideoDataOutput to the current AVCaptureSession.
   */
  private func addVideoDataOutput() -> Bool {

    let sampleBufferQueue = DispatchQueue(label: "sampleBufferQueue")
    videoDataOutput.setSampleBufferDelegate(self, queue: sampleBufferQueue)
    videoDataOutput.alwaysDiscardsLateVideoFrames = true
    videoDataOutput.videoSettings = [ String(kCVPixelBufferPixelFormatTypeKey) : kCMPixelFormat_32BGRA]

    if session.canAddOutput(videoDataOutput) {
      session.addOutput(videoDataOutput)
      videoDataOutput.connection(with: .video)?.videoOrientation = .portrait
      if videoDataOutput.connection(with: .video)?.isVideoOrientationSupported == true
          && cameraPosition == .front {
        videoDataOutput.connection(with: .video)?.isVideoMirrored = true
      }
      return true
    }
    return false
  }
    
    /**
     This method tries to an AVCaptureAudioDataOutput to the current AVCaptureSession.
     */
//    private func addAudioDataOutput() -> Bool {
//
//      let sampleBufferQueue = DispatchQueue(label: "sampleBufferQueue")
//      audioDataOutput.setSampleBufferDelegate(self, queue: sampleBufferQueue)
////      audioDataOutput.rec = [
////        AVFormatIDKey: NSNumber(value: kAudioFormatAppleLossless),
////        AVSampleRateKey: 16000.0,
////        AVNumberOfChannelsKey: 1,
////        AVEncoderAudioQualityKey: AVAudioQuality.min.rawValue
////    ]
//      if session.canAddOutput(audioDataOutput) {
//        session.addOutput(audioDataOutput)
//        return true
//      }
//      return false
//    }
    func setupAudioPlayback() -> Bool {
        audioEngine.attach(audioPlayer)
        audioEngine.attach(audioUnitTimePitch)
        
        audioEngine.connect(audioPlayer, to: audioUnitTimePitch, format: nil)
        audioEngine.connect(audioUnitTimePitch, to: audioEngine.mainMixerNode, format: nil)
        
        do {
            try audioEngine.start()
            return true
        } catch {
            print("Error starting audio engine: \(error.localizedDescription)")
            return false
        }
    }

  // MARK: Notification Observer Handling
  private func addObservers() {
    NotificationCenter.default.addObserver(self, selector: #selector(CameraFeedService.sessionRuntimeErrorOccured(notification:)), name: NSNotification.Name.AVCaptureSessionRuntimeError, object: session)
    NotificationCenter.default.addObserver(self, selector: #selector(CameraFeedService.sessionWasInterrupted(notification:)), name: NSNotification.Name.AVCaptureSessionWasInterrupted, object: session)
    NotificationCenter.default.addObserver(self, selector: #selector(CameraFeedService.sessionInterruptionEnded), name: NSNotification.Name.AVCaptureSessionInterruptionEnded, object: session)
  }

  private func removeObservers() {
    NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVCaptureSessionRuntimeError, object: session)
    NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVCaptureSessionWasInterrupted, object: session)
    NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVCaptureSessionInterruptionEnded, object: session)
  }

  // MARK: Notification Observers
  @objc func sessionWasInterrupted(notification: Notification) {

    if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?,
       let reasonIntegerValue = userInfoValue.integerValue,
       let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) {
      print("Capture session was interrupted with reason \(reason)")

      var canResumeManually = false
      if reason == .videoDeviceInUseByAnotherClient {
        canResumeManually = true
      } else if reason == .videoDeviceNotAvailableWithMultipleForegroundApps {
        canResumeManually = false
      }

      self.delegate?.sessionWasInterrupted(canResumeManually: canResumeManually)

    }
  }

  @objc func sessionInterruptionEnded(notification: Notification) {
    self.delegate?.sessionInterruptionEnded()
  }

  @objc func sessionRuntimeErrorOccured(notification: Notification) {
    guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else {
      return
    }

    print("Capture session runtime error: \(error)")

    guard error.code == .mediaServicesWereReset else {
      self.delegate?.didEncounterSessionRuntimeError()
      return
    }

    sessionQueue.async {
      if self.isSessionRunning {
        self.startSession()
      } else {
        DispatchQueue.main.async {
          self.delegate?.didEncounterSessionRuntimeError()
        }
      }
    }
  }
}

/**
 AVCaptureVideoDataOutputSampleBufferDelegate
 */
extension CameraFeedService: AVCaptureVideoDataOutputSampleBufferDelegate {

  /** This method delegates the CVPixelBuffer of the frame seen by the camera currently.
   */
  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
      let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
      if (imageBufferSize == nil) {
        imageBufferSize = CGSize(width: CVPixelBufferGetHeight(imageBuffer), height: CVPixelBufferGetWidth(imageBuffer))
      }
    delegate?.didOutput(sampleBuffer: sampleBuffer, orientation: UIImage.Orientation.from(deviceOrientation: UIDevice.current.orientation))
  }
}

// MARK: UIImage.Orientation Extension
extension UIImage.Orientation {
  static func from(deviceOrientation: UIDeviceOrientation) -> UIImage.Orientation {
    switch deviceOrientation {
      case .portrait:
        return .up
      case .landscapeLeft:
        return .left
      case .landscapeRight:
        return .right
      default:
        return .up
    }
  }
}
