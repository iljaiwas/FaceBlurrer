//
//  AppDelegate.swift
//  FaceBlurrer
//
//  Created by ilja on 30.06.2022.
//

import Cocoa
import UniformTypeIdentifiers
import AVFoundation


// https://cifilter.io/CIBlendWithRedMask/

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet var window: NSWindow!
    @IBOutlet weak var imageView: NSImageView!

    var pixelBuffer: CVPixelBuffer?
    let context = CIContext()
    var framesGenerated = 0
    var framesRequested = 0

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

            self.convertVideo(url: url)
            //self.openVideoAtURL (url)
        }
    }

    func openVideoAtURL (_ url: URL) {
        let asset = AVAsset(url:url)
        let videoDuration = asset.duration

        let generator = AVAssetImageGenerator(asset: asset)

        generator.requestedTimeToleranceAfter = CMTime.zero
        generator.requestedTimeToleranceBefore = CMTime.zero


        var frameForTimes = [NSValue]()
        let sampleCounts = 1
        let totalTimeLength = Int(videoDuration.seconds * Double(videoDuration.timescale))
        let step = totalTimeLength / sampleCounts

        for i in 0 ..< sampleCounts {
            let cmTime = CMTimeMake(value: Int64(i * step), timescale: Int32(videoDuration.timescale))
            frameForTimes.append(NSValue(time: cmTime))
        }

        generator.generateCGImagesAsynchronously(forTimes: frameForTimes, completionHandler: {requestedTime, image, actualTime, result, error in
            DispatchQueue.main.async {
                if let image = image {
                    print(requestedTime.value, requestedTime.seconds, actualTime.value)
                    let imageWithFace = self.detectFacesInImage (image)
                    //self.imageView.image = imageWithFace
                }
            }
        })
    }

    func blurredImageFromImage (_ inImage: CGImage) -> CIImage? {
        guard let filter = CIFilter(name: "CIGaussianBlur") else {
            return nil
        }
        let ciImage = CIImage(cgImage: inImage)
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(15.0, forKey: kCIInputRadiusKey)
        return filter.outputImage
    }

    func faceRectsForImage (_ inImage: CGImage) -> [CGRect] {
        let personciImage = CIImage(cgImage: inImage)

        let faceDetector = CIDetector(ofType: CIDetectorTypeFace, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let faces = faceDetector?.features(in: personciImage) as! [CIFaceFeature]
        return faces.map{ face in face.bounds }
    }

    func maskImage (size: CGSize, faceRects: [CGRect]) -> CGImage? {

        guard let maskContext = CGContext(
            data: nil,                                                        // auto-assign memory for the bitmap
            width: Int(size.width),    // width of the view in pixels
            height: Int(size.height),   // height of the view in pixels
            bitsPerComponent: 8,                                                          // 8 bits per colour component
            bytesPerRow: 0,                                                          // auto-calculate bytes per row
            space: CGColorSpaceCreateDeviceRGB(),                              // create a suitable colour space
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else {
                return nil
            }

        maskContext.setFillColor (CGColor (red: 1, green: 0, blue: 0, alpha: 1))
        maskContext.setStrokeColor (CGColor (red: 1, green: 0, blue: 0, alpha: 1))
        maskContext.setLineWidth (5.0)

        let insetFactor = -0.2

        for rect in faceRects {
            maskContext.beginPath()
            maskContext.addEllipse(in: rect.insetBy(dx: insetFactor * rect.size.width, dy: insetFactor * rect.size.height))
            maskContext.closePath()
            maskContext.drawPath(using: .fill)
        }

        guard let maskCGImage = maskContext.makeImage() else {
            return nil
        }

        return maskCGImage;
        //return CIImage(cgImage: maskCGImage).applyingFilter("CIMaskToAlpha", parameters: [:]).cgImage

    }

    func detectFacesInImage (_ inImage: CGImage) -> CIImage? {

        guard let blurredImage = blurredImageFromImage(inImage) else {
            return nil
        }
        let faceRects = faceRectsForImage(inImage)
        let maskImage = maskImage(size: CGSize(width: inImage.width, height: inImage.height), faceRects: faceRects)

        guard let filter = CIFilter(name: "CIBlendWithRedMask") else {
            return nil
        }

        filter.setValue( CIImage(cgImage: inImage), forKey: kCIInputBackgroundImageKey)
        filter.setValue( blurredImage, forKey: kCIInputImageKey)
        filter.setValue( CIImage(cgImage: maskImage!), forKey: kCIInputMaskImageKey)

        return filter.outputImage

//        guard let outputImage = filter.outputImage else {
//            return nil ()
//        }
//        let rep: NSCIImageRep = NSCIImageRep(ciImage: outputImage)
//        let nsImage: NSImage = NSImage(size: rep.size)
//        nsImage.addRepresentation(rep)
//
//        return nsImage
    }



    func convertVideo(url: URL) -> Bool {
        let inputAsset = AVAsset(url:url)
        let videoDuration = inputAsset.duration

        let outputURL = url.appendingPathExtension("converted.mov")

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
        let assetWriterAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterInput, sourcePixelBufferAttributes: nil)
        assetwriter.add(assetWriterInput)
        //begin the session
        assetwriter.startWriting()
        assetwriter.startSession(atSourceTime: CMTime.zero)

        let frameRate = videoTrack.nominalFrameRate

        let generator = AVAssetImageGenerator(asset: inputAsset)

        generator.requestedTimeToleranceAfter = CMTime.zero
        generator.requestedTimeToleranceBefore = CMTime.zero

        var frameForTimes = [NSValue]()
        //let totalTimeLength = videoDuration.seconds * Double(videoDuration.timescale)
        let sampleCounts = Int (videoDuration.seconds * Double(frameRate))
        let step = videoDuration.seconds  / Double(sampleCounts)

        for i in 0 ..< sampleCounts {
            let cmTime = CMTimeMake(value: Int64(Double(i) * step), timescale: 1)
            frameForTimes.append(NSValue(time: cmTime))
        }

        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
             kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary


        CVPixelBufferCreate(kCFAllocatorDefault,
                            Int(dimension.width),
                            Int(dimension.height),
                            kCVPixelFormatType_32BGRA,
                            attrs,
                            &pixelBuffer)

        framesGenerated = 0
        framesRequested = frameForTimes.count
        generator.generateCGImagesAsynchronously(forTimes: frameForTimes, completionHandler: {requestedTime, image, actualTime, result, error in

            self.framesGenerated += 1;
            print ("framesGenerated: \(self.framesGenerated) of \(self.framesRequested) for time \(actualTime)")

            guard let image = image, let modifiedImage = self.detectFacesInImage (image) else {
                //close everything
                print ("generation done")
                assetWriterInput.markAsFinished()
                assetwriter.finishWriting {
                    self.pixelBuffer = nil
                }
                return
             }

            self.context.render(modifiedImage, to: self.pixelBuffer!)

            assetWriterAdaptor.append(self.pixelBuffer!, withPresentationTime: actualTime)

            if (self.framesGenerated % 10 == 0) {
                DispatchQueue.main.async {
                    let rep = NSCIImageRep(ciImage: modifiedImage)
                    let nsImage = NSImage(size: rep.size)
                    nsImage.addRepresentation(rep)
                    self.imageView.image = nsImage
                }
            }
            if self.framesGenerated == self.framesRequested {
                //close everything
                print ("generation done")
                assetWriterInput.markAsFinished()
                assetwriter.finishWriting {
                    self.pixelBuffer = nil
                }
            }
        })
        return true;
    }

}
