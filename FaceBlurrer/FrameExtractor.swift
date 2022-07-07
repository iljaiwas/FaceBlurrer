//
//  FrameExtractor.swift
//  FaceBlurrer
//
//  Created by ilja on 06.07.2022.
//

import Foundation
import AVFoundation
import Cocoa

class SourceImage
{
    internal init(image: CIImage, timestamp: CMTime, frameIndex: Int) {
        self.image = image
        self.timestamp = timestamp
        self.frameIndex = frameIndex
    }

    let image: CIImage
    let timestamp: CMTime
    let frameIndex: Int

    var humanRects: [CGRect]?
    var faceRects: [CGRect]?
}


class FrameExtractor
{
    let totalFrames: Int
    let imageGenerator: AVAssetImageGenerator
    let secondsPerFrame: Double

    init(totalFrames: Int, imageGenerator: AVAssetImageGenerator, secondsPerFrame: Double) {
        self.totalFrames = totalFrames
        self.imageGenerator = imageGenerator
        self.secondsPerFrame = secondsPerFrame
    }

    func images() -> AsyncStream<SourceImage> {

        return AsyncStream { continuation in

            Task {
            for frameIndex in 0 ..< totalFrames {
                let imageTimeEstimate = CMTime(value: CMTimeValue(Double(frameIndex) * secondsPerFrame * 1000), timescale: 1000)
                var actualTime = CMTime(value: CMTimeValue(0), timescale: 1000)

                do {
                    let frameCGImage = try imageGenerator.copyCGImage(at: imageTimeEstimate, actualTime: &actualTime)
                    print ("FrameExtractor.images at \(frameIndex) timestamp: \(actualTime.value)")
                    continuation.yield(SourceImage (image:CIImage(cgImage: frameCGImage), timestamp:actualTime, frameIndex: frameIndex ))
                } catch {
                }
            }
            continuation.finish()
            }
        }
    }
}
