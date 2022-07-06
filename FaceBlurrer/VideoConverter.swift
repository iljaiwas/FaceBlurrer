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

    var imageGenerator: AVAssetImageGenerator?
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

    func convertVideo() -> Bool
    {
        let outputURL = videoURL.appendingPathExtension("converted.mov")
        let videoDuration = inputAsset.duration

        try? FileManager.default.removeItem(at: outputURL)

        guard let videoTrack = inputAsset.tracks(withMediaType: .video).first else {
            return false
        }
        guard let formatDescription = videoTrack.formatDescriptions.first else {
            return false
        }

        let dimension = CMVideoFormatDescriptionGetPresentationDimensions(formatDescription as! CMVideoFormatDescription, usePixelAspectRatio: true, useCleanAperture: true)


        guard let assetwriter = try? AVAssetWriter(outputURL: outputURL, fileType: .mov) else {
            abort()
        }
        let assetWriterSettings = [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey : dimension.width, AVVideoHeightKey: dimension.height] as [String : Any]

        self.assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: assetWriterSettings)
        guard let assetWriterInput = self.assetWriterInput else { return false}

        assetWriterAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterInput,
                                                                      sourcePixelBufferAttributes: nil )//adaptorSettings)
        assetwriter.add(assetWriterInput)
        //begin the session
        assetwriter.startWriting()
        assetwriter.startSession(atSourceTime: CMTime.zero)

        imageGenerator = AVAssetImageGenerator(asset: inputAsset)
        imageGenerator?.requestedTimeToleranceAfter = CMTime.zero
        imageGenerator?.requestedTimeToleranceBefore = CMTime.zero

        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
             kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary


        var temp : CVPixelBuffer?

        CVPixelBufferCreate(kCFAllocatorDefault,
                            Int(dimension.width),
                            Int(dimension.height),
                            kCVPixelFormatType_32BGRA,
                            attrs,
                            &temp)
        guard let temp = temp else { return false }
        pixelBuffer = temp

        totalFrames = Int (videoDuration.seconds * Double (videoTrack.nominalFrameRate))

        //self.progressBar.maxValue = Double(totalFrames)
        //self.progressBar.doubleValue = 0

        secondsPerFrame = videoDuration.seconds / Double (totalFrames)

        //Step through the frames
        computeImageForFrame (frameIndex: 0)
        return true
    }

    func computeImageForFrame (frameIndex : Int) {

        if frameIndex == totalFrames {
            print ("generation done")
            assetWriterInput?.markAsFinished()
            assetWriter?.finishWriting { }
            return
        }
        let imageTimeEstimate = CMTime(value: CMTimeValue(Double(frameIndex) * secondsPerFrame * 1000), timescale: 1000)

        print ("at \(frameIndex) of \(totalFrames)")

        do {
            var actualTime = CMTime(value: CMTimeValue(0), timescale: 1000)

            var frameCIImage : CIImage?
            try autoreleasepool {
                if let frameCGImage = try imageGenerator?.copyCGImage(at: imageTimeEstimate, actualTime: &actualTime) {
                    frameCIImage = CIImage(cgImage: frameCGImage)
                }
            }
            let faceBlurrer = FaceBlurrer()
            faceBlurrer.blurrFaces(frameCIImage!) { modifiedImage in
                autoreleasepool {
                    guard let modifiedCIImage = modifiedImage?.ciImage() else {
                        return
                    }

                    if let pixelBuffer = self.pixelBuffer, let assetWriterAdaptor = self.assetWriterAdaptor {
                        self.ciContext.render(modifiedCIImage, to: pixelBuffer)

                        if false == assetWriterAdaptor.append(pixelBuffer, withPresentationTime: imageTimeEstimate) {
                            print ("append failed with error \(String(describing: self.assetWriter?.error!))")
                            print ("Video file writer status: \(String(describing: self.assetWriter?.status.rawValue))")
                            abort()
                        }
                    }
                    //var nsImage = NSImage()
                    if frameIndex % 25 == 0 {
                    //    nsImage = modifiedImage ?? NSImage()
                    }
                    DispatchQueue.main.async {
                        if frameIndex % 25 == 0 {
                            //self.progressBar.doubleValue = Double(frameIndex)
                            //self.imageView.image = nsImage
                        }
                        self.computeImageForFrame(frameIndex: frameIndex + 1)
                    }
                }
            }
        } catch (_) {
            print ("excpetion received")
        }
    }
}
