//
//  AppDelegate.swift
//  FaceBlurrer
//
//  Created by ilja on 30.06.2022.
//

import Cocoa
import UniformTypeIdentifiers
import AVFoundation

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet var window: NSWindow!
    @IBOutlet weak var imageView: NSImageView!

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

            self.openVideoAtURL (url)
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
                    self.imageView.image = imageWithFace
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

        for rect in faceRects {
            maskContext.beginPath()
            maskContext.addRect(rect)
            maskContext.closePath()
            maskContext.drawPath(using: .fill)
        }

        guard let maskCGImage = maskContext.makeImage() else {
            return nil
        }

        return maskCGImage;
        //return CIImage(cgImage: maskCGImage).applyingFilter("CIMaskToAlpha", parameters: [:]).cgImage

    }

    func detectFacesInImage (_ inImage: CGImage) -> NSImage {

        guard let blurredImage = blurredImageFromImage(inImage) else {
            return NSImage ()
        }
        let faceRects = faceRectsForImage(inImage)
        let maskImage = maskImage(size: CGSize(width: inImage.width, height: inImage.height), faceRects: faceRects)

        guard let filter = CIFilter(name: "CIBlendWithRedMask") else {
            return NSImage ()
        }

        filter.setValue( CIImage(cgImage: inImage), forKey: kCIInputBackgroundImageKey)
        filter.setValue( blurredImage, forKey: kCIInputImageKey)
        filter.setValue( CIImage(cgImage: maskImage!), forKey: kCIInputMaskImageKey) 

        guard let outputImage = filter.outputImage else {
            return NSImage ()
        }
        let rep: NSCIImageRep = NSCIImageRep(ciImage: outputImage)
        let nsImage: NSImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)

        return nsImage
    }

}

