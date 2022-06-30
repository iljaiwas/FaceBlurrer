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

    func detectFacesInImage (_ inImage: CGImage) -> NSImage {
       let personciImage = CIImage(cgImage: inImage)

        let accuracy = [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        let faceDetector = CIDetector(ofType: CIDetectorTypeFace, context: nil, options: accuracy)
        let faces = faceDetector?.features(in: personciImage)

//        // For converting the Core Image Coordinates to UIView Coordinates
//        let ciImageSize = personciImage.extent.size
//        var transform = CGAffineTransform(scaleX: 1, y: -1)
//        transform = transform.translatedBy(x: 0, y: -ciImageSize.height)

        guard let bitmapContext = CGContext(
            data: nil,                                                        // auto-assign memory for the bitmap
            width: inImage.width,    // width of the view in pixels
            height: inImage.height,   // height of the view in pixels
            bitsPerComponent: 8,                                                          // 8 bits per colour component
            bytesPerRow: 0,                                                          // auto-calculate bytes per row
            space: CGColorSpaceCreateDeviceRGB(),                              // create a suitable colour space
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else {
                return NSImage ()
            }

        bitmapContext.draw(inImage,
                           in: NSMakeRect(0, 0,  CGFloat(inImage.width),  CGFloat(inImage.height)))

        bitmapContext.setStrokeColor (CGColor (red: 1, green: 0, blue: 0, alpha: 1))
        bitmapContext.setLineWidth (5.0)

//        let resultImage = NSImage(size: NSMakeSize (CGFloat(inImage.width), CGFloat(inImage.height)))
//
//        resultImage.lockFocus()
//
//        let sourceImage = NSImage(cgImage: inImage, size: .zero)


//        //sourceImage.draw(in: NSMakeRect(0, 0, CGFloat(inImage.width), CGFloat(inImage.height)),
//                         from: NSMakeRect(0, 0, CGFloat(inImage.width), CGFloat(inImage.height)),
//                         operation: .sourceOver,
//                         fraction: 1)



        for face in faces as! [CIFaceFeature] {

            print("Found bounds are \(face.bounds)")

            // Apply the transform to convert the coordinates
            //let faceViewBounds = face.bounds.applying(transform)

            //let path = NSBezierPath(rect: face.bounds)

            bitmapContext.beginPath()
            bitmapContext.addRect(face.bounds)
            bitmapContext.closePath()
            bitmapContext.drawPath(using: .stroke)
            /*
            // Calculate the actual position and size of the rectangle in the image view
            let viewSize = NSMakeSize(CGFloat(inImage.width), CGFloat(inImage.height))
            let scale = min(viewSize.width / ciImageSize.width,
                            viewSize.height / ciImageSize.height)
            let offsetX = (viewSize.width - ciImageSize.width * scale) / 2
            let offsetY = (viewSize.height - ciImageSize.height * scale) / 2

            let scaleTransformation = CGAffineTransform(scaleX: scale, y: scale)
            faceViewBounds = faceViewBounds.applying(scaleTransformation)
            faceViewBounds.origin.x += offsetX
            faceViewBounds.origin.y += offsetY

            let faceBox = UIView(frame: faceViewBounds)

            faceBox.layer.borderWidth = 3
            faceBox.layer.borderColor = UIColor.redColor().CGColor
            faceBox.backgroundColor = UIColor.clearColor()
            personPic.addSubview(faceBox)
             */

            if face.hasLeftEyePosition {
                print("Left eye bounds are \(face.leftEyePosition)")
            }

            if face.hasRightEyePosition {
                print("Right eye bounds are \(face.rightEyePosition)")
            }
        }
        guard let cgImage = bitmapContext.makeImage () else {
            return NSImage()
        }

        return NSImage (cgImage: cgImage, size: NSMakeSize(CGFloat(cgImage.width), CGFloat(cgImage.height)))
    }
}

