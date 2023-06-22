//
//  FaceDetectorTests.swift
//  FaceDetectorTests
//
//  Created by MBA0077 on 6/20/23.
//

import XCTest
@testable import FaceDetector
import MediaPipeTasksVision

final class FaceDetectorTests: XCTestCase {

  static let modelPath = Bundle.main.path(forResource: "blaze_face_short_range", ofType: "tflite")!
  static let minDetectionConfidence: Float = 0.5
  static let minSuppressionThreshold: Float = 0.5

  static let testImage = UIImage(named: "testImg.jpeg")!

  static let results: [Detection] = [
    Detection(
      categories: [ResultCategory(index: 0, score: 0.973259031, categoryName: nil, displayName: nil)],
      boundingBox: CGRect(x: 126.0, y: 100.0, width: 464.0, height: 464.0),
      keypoints: nil),
    Detection(
      categories: [ResultCategory(index: 0, score: 0.926310122, categoryName: nil, displayName: nil)],
      boundingBox: CGRect(x: 616.0, y: 193, width: 430.0, height: 430.0),
      keypoints: nil)
  ]

  func faceDetectorWithModelPath(
    _ modelPath: String,
    minDetectionConfidence: Float,
    minSuppressionThreshold: Float) throws -> FaceDetectorHelper {
    let faceDetectorHelper = FaceDetectorHelper(modelPath: modelPath,
                                                minDetectionConfidence: minDetectionConfidence,
                                                minSuppressionThreshold: minSuppressionThreshold,
                                                runningModel: .image)
    return faceDetectorHelper
  }

  func assertFaceDetectionResultHasOneHead(
    _ faceDetectorResult: FaceDetectorResult
  ) {
    XCTAssertEqual(faceDetectorResult.detections.count, 2)
  }

  func assertDetectionAreEqual(
    detection: Detection,
    expectedDetection: Detection,
    indexInDetectionList: Int
  ) {
    XCTAssertEqual(
      detection.boundingBox,
      expectedDetection.boundingBox,
      String(
        format: """
                    detection[%d].boundingBox and expectedDetection[%d].boundingBox are not equal.
              """, indexInDetectionList))
    for (category, expectedCategory) in zip(detection.categories, expectedDetection.categories) {
      XCTAssertEqual(
        category.index,
        expectedCategory.index,
        String(
          format: """
                category[%d].index and expectedCategory[%d].index are not equal.
                """, indexInDetectionList))
      XCTAssertEqual(
        category.score,
        expectedCategory.score,
        accuracy: 1e-3,
        String(
          format: """
                category[%d].score and expectedCategory[%d].score are not equal.
                """, indexInDetectionList))
      XCTAssertEqual(
        category.categoryName,
        expectedCategory.categoryName,
        String(
          format: """
                category[%d].categoryName and expectedCategory[%d].categoryName are \
                not equal.
                """, indexInDetectionList))
      XCTAssertEqual(
        category.displayName,
        expectedCategory.displayName,
        String(
          format: """
                category[%d].displayName and expectedCategory[%d].displayName are \
                not equal.
                """, indexInDetectionList))
    }
  }

  func assertEqualDetectionArrays(
    detectionArray: [Detection],
    expecteddetectionArray: [Detection]
  ) {
    XCTAssertEqual(
      detectionArray.count,
      expecteddetectionArray.count)

    for (index, (detection, expectedDetection)) in zip(detectionArray, expecteddetectionArray)
      .enumerated()
    {
      assertDetectionAreEqual(
        detection: detection,
        expectedDetection: expectedDetection,
        indexInDetectionList: index)
    }
  }

  func assertResultsForDetection(
    image: UIImage,
    using faceDetector: FaceDetectorHelper,
    equals expectedDetections: [Detection]
  ) throws {
    let faceDetectorResult =
    try XCTUnwrap(faceDetector.detect(image: image)!.faceDetectorResult)
    print(faceDetectorResult)
    assertFaceDetectionResultHasOneHead(faceDetectorResult)
    assertEqualDetectionArrays(
      detectionArray: faceDetectorResult.detections,
      expecteddetectionArray: expectedDetections)
  }
  func testDetectionSucceeds() throws {

    let faceDetector = try faceDetectorWithModelPath(
      FaceDetectorTests.modelPath,
      minDetectionConfidence: FaceDetectorTests.minDetectionConfidence,
      minSuppressionThreshold: FaceDetectorTests.minSuppressionThreshold)
    try assertResultsForDetection(
      image: FaceDetectorTests.testImage,
      using: faceDetector,
      equals: FaceDetectorTests.results)
  }
}
