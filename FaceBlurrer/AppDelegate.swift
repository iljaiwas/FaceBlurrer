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

        self.progressBar.maxValue = Double(totalFrames)
        self.progressBar.doubleValue = 0

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
                    guard let modifiedCIImage = modifiedImage?.ciImage() else {
                        return
                    }

                    context.render(modifiedCIImage, to: pixelBuffer)

                    if false == assetWriterAdaptor.append(pixelBuffer, withPresentationTime: imageTimeEstimate) {
                        print ("append failed with error \(assetWriter.error!)")
                        print ("Video file writer status: \(assetWriter.status.rawValue)")
                        abort()
                    }
                    var nsImage = NSImage()
                    if frameIndex % 25 == 0 {
                        nsImage = modifiedImage ?? NSImage()
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
