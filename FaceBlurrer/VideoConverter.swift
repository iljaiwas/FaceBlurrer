//
//  VideoConverter.swift
//  FaceBlurrer
//
//  Created by ilja on 04.07.2022.
//

import Cocoa
import AVFoundation


class VideoConverter
{
    let videoURL: URL
    let inputAsset: AVAsset
    let ciContext = CIContext()

    var pixelBuffer : CVPixelBuffer?
    var totalFrames: Int = 0
    var secondsPerFrame: Double = 0.0
    var assetWriterAdaptor : AVAssetWriterInputPixelBufferAdaptor?
    var assetWriterInput : AVAssetWriterInput?
    var assetWriter : AVAssetWriter?

    init(withURL inVideoURL: URL) {
        videoURL = inVideoURL

        inputAsset = AVAsset(url:videoURL)

    }

    func convertVideo() async -> Void
    {
        let outputURL = videoURL.appendingPathExtension("converted.mov")
        let videoDuration = inputAsset.duration

        try? FileManager.default.removeItem(at: outputURL)

        guard let videoTrack = inputAsset.tracks(withMediaType: .video).first else {
            return
        }
        guard let formatDescription = videoTrack.formatDescriptions.first else {
            return
        }

        let dimension = CMVideoFormatDescriptionGetPresentationDimensions(formatDescription as! CMVideoFormatDescription, usePixelAspectRatio: true, useCleanAperture: true)
        
        guard let assetwriter = try? AVAssetWriter(outputURL: outputURL, fileType: .mov) else {
            abort()
        }
        let assetWriterSettings = [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey : dimension.width, AVVideoHeightKey: dimension.height] as [String : Any]

        self.assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: assetWriterSettings)
        guard let assetWriterInput = self.assetWriterInput else { return }

        assetWriterAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterInput,
                                                                      sourcePixelBufferAttributes: nil )//adaptorSettings)
        assetwriter.add(assetWriterInput)
        assetwriter.startWriting()
        assetwriter.startSession(atSourceTime: CMTime.zero)

        let imageGenerator = AVAssetImageGenerator(asset: inputAsset)
        imageGenerator.requestedTimeToleranceAfter = CMTime.zero
        imageGenerator.requestedTimeToleranceBefore = CMTime.zero

        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
             kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary


        var temp : CVPixelBuffer?

        CVPixelBufferCreate(kCFAllocatorDefault,
                            Int(dimension.width),
                            Int(dimension.height),
                            kCVPixelFormatType_32BGRA,
                            attrs,
                            &temp)
        guard let temp = temp else { return  }
        pixelBuffer = temp

        totalFrames = Int (videoDuration.seconds * Double (videoTrack.nominalFrameRate))
        secondsPerFrame = videoDuration.seconds / Double (totalFrames)

        let frameExtractor = FrameExtractor(totalFrames: totalFrames, imageGenerator: imageGenerator , secondsPerFrame: secondsPerFrame)
        let imageBlurrer = FaceBlurrer(frameExtractor: frameExtractor)

        let blurredImages = imageBlurrer.blurredImages()
        var iterator = blurredImages.makeAsyncIterator()

        while let blurredImage = await iterator.next() {
            if let pixelBuffer = self.pixelBuffer, let assetWriterAdaptor = self.assetWriterAdaptor {
                self.ciContext.render(blurredImage.blurredImage.ciImage()!, to: pixelBuffer)

                if false == assetWriterAdaptor.append(pixelBuffer, withPresentationTime: blurredImage.timestamp) {
                    print ("append failed with error \(String(describing: self.assetWriter?.error!))")
                    print ("Video file writer status: \(String(describing: self.assetWriter?.status.rawValue))")
                    abort()
                }
            }
        }
    }
}
