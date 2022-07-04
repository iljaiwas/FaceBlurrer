//
//  AppDelegate.swift
//  FaceBlurrer
//
//  Created by ilja on 30.06.2022.
//

import Cocoa
import UniformTypeIdentifiers
import AVFoundation
import Vision


// https://cifilter.io/CIBlendWithRedMask/

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet var window: NSWindow!
    @IBOutlet weak var imageView: NSImageView!

    @IBOutlet weak var progressBar: NSProgressIndicator!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }


    @IBAction func openVideoButtonAction(_ sender: Any) {
        let openPanel = NSOpenPanel()

        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowedContentTypes = [UTType.audiovisualContent]

        openPanel.beginSheetModal(for: window) { modalResponse in
            guard modalResponse == .OK,
            let url = openPanel.url else { return }

            _ = self.convertVideo(url: url)
        }
    }

    func blurredImageFromImage (_ inImage: CIImage) -> CIImage? {

        var resultImage : CIImage?

        autoreleasepool {
            guard let filter = CIFilter(name: "CIGaussianBlur") else {
                return
            }
            filter.setValue(inImage, forKey: kCIInputImageKey)
            filter.setValue(30.0, forKey: kCIInputRadiusKey)
            resultImage = filter.outputImage
        }
        return resultImage
    }

    func faceRectsForImage (_ inImage: CGImage) -> [CGRect] {
        let personciImage = CIImage(cgImage: inImage)

        let faceDetector = CIDetector(ofType: CIDetectorTypeFace, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let faces = faceDetector?.features(in: personciImage) as! [CIFaceFeature]
        return faces.map{ face in face.bounds }
    }

    func faceRectsForImageWithVision(_ inImage: CIImage) async throws -> [CGRect] {

        return try await withCheckedThrowingContinuation { continuation in

            let handler=VNImageRequestHandler(ciImage: inImage)
            do{
                let request = VNDetectFaceRectanglesRequest {aRequest, error in
                    autoreleasepool{
                        var foundFaceRects = [CGRect]()

                        if let results=aRequest.results as? [VNFaceObservation]{
                            //print(results.count, "faces found")
                            for face_obs in results{
                                let ts=CGAffineTransform.identity.scaledBy(x: CGFloat(inImage.extent.width), y: CGFloat(inImage.extent.height))
                                let converted_rect=face_obs.boundingBox.applying(ts)
                                foundFaceRects.append(converted_rect)
                            }
                        }
                        continuation.resume(returning: foundFaceRects)
                    }
                }
                request.revision = VNDetectFaceLandmarksRequestRevision3
                try handler.perform([request])
            }catch{
                print(error)
            }
        }
    }

    func humanRectsForImageWithVision(_ inImage: CIImage) async throws -> [CGRect] {

        return try await withCheckedThrowingContinuation { continuation in

            let handler=VNImageRequestHandler(ciImage: inImage)
            do{
                let request = VNDetectHumanRectanglesRequest {aRequest, error in
                    autoreleasepool{
                        var foundFaceRects = [CGRect]()

                        if let results=aRequest.results as? [VNHumanObservation]{
                            //print(results.count, "humans found")
                            for face_obs in results{
                                let ts=CGAffineTransform.identity.scaledBy(x: CGFloat(inImage.extent.width), y: CGFloat(inImage.extent.height))
                                let converted_rect=face_obs.boundingBox.applying(ts)
                                foundFaceRects.append(converted_rect)
                            }
                        }
                        continuation.resume(returning: foundFaceRects)
                    }
                }
                try handler.perform([request])
            }catch{
                print(error)
            }
        }
    }


    func maskImage (size: CGSize, maskRects: [CGRect]) -> CGImage? {

        var maskCGImage: CGImage?

        autoreleasepool {
            guard let maskContext = CGContext(
                data: nil,                                                        // auto-assign memory for the bitmap
                width: Int(size.width),    // width of the view in pixels
                height: Int(size.height),   // height of the view in pixels
                bitsPerComponent: 8,                                                          // 8 bits per colour component
                bytesPerRow: 0,                                                          // auto-calculate bytes per row
                space: CGColorSpaceCreateDeviceRGB(),                              // create a suitable colour space
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else {
                    return
                }

            maskContext.setFillColor (CGColor (red: 1, green: 0, blue: 0, alpha: 1))
            maskContext.setStrokeColor (CGColor (red: 1, green: 0, blue: 0, alpha: 1))
            maskContext.setLineWidth (5.0)

            let insetFactor = -0.2

            for rect in maskRects {
                maskContext.beginPath()
                maskContext.addEllipse(in: rect.insetBy(dx: insetFactor * rect.size.width, dy: insetFactor * rect.size.height))
                maskContext.closePath()
                maskContext.drawPath(using: .fill)
            }

            maskCGImage = maskContext.makeImage()
        }

        return maskCGImage;
    }

    func detectFacesInImage (_ inImage: CIImage) async -> CIImage? {

        guard let blurredImage = blurredImageFromImage(inImage) else {
            return nil
        }
        var allRects = [CGRect] ()
        let humanRects = try? await humanRectsForImageWithVision (inImage)
        let faceRects = try? await faceRectsForImageWithVision (inImage)

        if let humanRects = humanRects {
            allRects.append(contentsOf: humanRects)
        }
        if let faceRects = faceRects {
            allRects.append(contentsOf: faceRects)
        }

        var result : CIImage?

        autoreleasepool {
            let maskImage = maskImage(size: CGSize(width: inImage.extent.width, height: inImage.extent.height), maskRects: allRects)

            guard let filter = CIFilter(name: "CIBlendWithRedMask") else {
                return
            }

            filter.setValue( inImage, forKey: kCIInputBackgroundImageKey)
            filter.setValue( blurredImage, forKey: kCIInputImageKey)
            filter.setValue( CIImage(cgImage: maskImage!), forKey: kCIInputMaskImageKey)

            result = filter.outputImage
        }

        return result
    }

    func convertVideo(url: URL) -> Bool {
        let inputAsset = AVAsset(url:url)
        let videoDuration = inputAsset.duration

        let outputURL = url.appendingPathExtension("converted.mov")

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

        let assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: assetWriterSettings)

        let assetWriterAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterInput,
                                                                      sourcePixelBufferAttributes: nil )//adaptorSettings)
        assetwriter.add(assetWriterInput)
        //begin the session
        assetwriter.startWriting()
        assetwriter.startSession(atSourceTime: CMTime.zero)

        let generator = AVAssetImageGenerator(asset: inputAsset)

        generator.requestedTimeToleranceAfter = CMTime.zero
        generator.requestedTimeToleranceBefore = CMTime.zero

        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
             kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary


        var temp : CVPixelBuffer?

        CVPixelBufferCreate(kCFAllocatorDefault,
                            Int(dimension.width),
                            Int(dimension.height),
                            kCVPixelFormatType_32BGRA,
                            attrs,
                            &temp)
        guard let pixelBuffer = temp else { return false }

        let context = CIContext()

        //let timePerFrame = 1.0 / videoTrack.nominalFrameRate
        let totalFrames = Int (videoDuration.seconds * Double (videoTrack.nominalFrameRate))

        DispatchQueue.main.sync {
            self.progressBar.maxValue = Double(totalFrames)
            self.progressBar.doubleValue = 0
        }

        let secondsPerFrame = videoDuration.seconds / Double (totalFrames)

        //Step through the frames

        computeImageForFrame (frameIndex: 0,
                              totalFrames: totalFrames,
                              generator:generator,
                              secondsPerFrame: secondsPerFrame,
                              pixelBuffer: pixelBuffer,
                              context: context,
                              assetWriterAdaptor: assetWriterAdaptor,
                              assetWriterInput: assetWriterInput,
                              assetWriter: assetwriter)

        return true
    }


    func  computeImageForFrame (frameIndex : Int , totalFrames : Int, generator: AVAssetImageGenerator, secondsPerFrame: Double, pixelBuffer: CVPixelBuffer, context: CIContext, assetWriterAdaptor: AVAssetWriterInputPixelBufferAdaptor, assetWriterInput: AVAssetWriterInput, assetWriter: AVAssetWriter) {

        if frameIndex == totalFrames {
            print ("generation done")
            assetWriterInput.markAsFinished()
            assetWriter.finishWriting { }
            return
        }
        let imageTimeEstimate = CMTime(value: CMTimeValue(Double(frameIndex) * secondsPerFrame * 1000), timescale: 1000)

        print ("at \(frameIndex) of \(totalFrames)")

        do {
            var actualTime = CMTime(value: CMTimeValue(0), timescale: 1000)

            var frameCIImage : CIImage?
            try autoreleasepool {
                let frameCGImage = try generator.copyCGImage(at: imageTimeEstimate, actualTime: &actualTime)
                frameCIImage = CIImage(cgImage: frameCGImage)
            }
            let faceBlurrer = FaceBlurrer()
            faceBlurrer.blurrFaces(frameCIImage!) { modifiedImage in
                autoreleasepool {
                    guard let modifiedImage = modifiedImage else {
                        return
                    }

                    context.render(modifiedImage, to: pixelBuffer)

                    if false == assetWriterAdaptor.append(pixelBuffer, withPresentationTime: imageTimeEstimate) {
                        print ("append failed with error \(assetWriter.error!)")
                        print ("Video file writer status: \(assetWriter.status.rawValue)")
                        abort()
                    }
                    var nsImage = NSImage()
                    if frameIndex % 25 == 0 {
                        nsImage = NSImage.fromCIImage(modifiedImage)
                    }
                    DispatchQueue.main.async {
                        if frameIndex % 25 == 0 {
                            self.progressBar.doubleValue = Double(frameIndex)
                            self.imageView.image = nsImage
                        }
                        self.computeImageForFrame(frameIndex: frameIndex + 1, totalFrames: totalFrames, generator: generator, secondsPerFrame: secondsPerFrame, pixelBuffer: pixelBuffer, context: context, assetWriterAdaptor: assetWriterAdaptor, assetWriterInput: assetWriterInput, assetWriter: assetWriter)
                    }
                }
            }
        } catch (_) {
            print ("excpetion received")
        }
    }
}


extension NSImage {
    /// Generates a CIImage for this NSImage.
    /// - Returns: A CIImage optional.
    func ciImage() -> CIImage? {
        guard let data = self.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data) else {
                  return nil
              }
        let ci = CIImage(bitmapImageRep: bitmap)
        return ci
    }

    /// Generates an NSImage from a CIImage.
    /// - Parameter ciImage: The CIImage
    /// - Returns: An NSImage optional.
    static func fromCIImage(_ ciImage: CIImage) -> NSImage {
        let rep = NSCIImageRep(ciImage: ciImage)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }
}
