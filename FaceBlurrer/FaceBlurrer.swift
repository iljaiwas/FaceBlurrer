//
//  FaceBlurrer.swift
//  FaceBlurrer
//
//  Created by ilja on 03.07.2022.
//

import Cocoa
import CoreImage
import Vision


class BlurredImage
{
    internal init(blurredImage: NSImage, timestamp: CMTime, frameIndex: Int) {
        self.image = blurredImage
        self.timestamp = timestamp
        self.frameIndex = frameIndex
    }

    let image: NSImage
    let timestamp: CMTime
    let frameIndex: Int
}

class FaceBlurrer
{
    let frameExtractor: FrameExtractor

    init(frameExtractor: FrameExtractor) {
        self.frameExtractor = frameExtractor
    }

    deinit
    {
        print ("FaceBlurrer deinit")
    }

    func blurredImages() -> AsyncMapSequence<AsyncStream<SourceImage>, BlurredImage> {
        return frameExtractor.images ().map { image in
            return await withCheckedContinuation { cc in
                self.blurrImage(image) { blurredImage in
                    cc.resume (returning: blurredImage)
                }
            }
        }
    }

    func blurrImage( _ inSourceImage : SourceImage, finished: @escaping (BlurredImage) -> Void)
    {
        print ("blurrImage at \(inSourceImage.frameIndex) timestamp \(inSourceImage.timestamp.value)")
        humanRectsForImageWithVision (inSourceImage.image) { [self] (foundHumanRects) in
            inSourceImage.humanRects = foundHumanRects
            checkIfDetectionDone (inSourceImage, finished)
        }
        faceRectsForImageWithVision (inSourceImage.image) { [self] (foundFaceRects) in
            inSourceImage.faceRects = foundFaceRects
            checkIfDetectionDone (inSourceImage, finished)
        }
    }

    func checkIfDetectionDone (_ inSourceImage : SourceImage, _ finished: (BlurredImage) -> Void) {
        guard let humanRects = inSourceImage.humanRects, let faceRects = inSourceImage.faceRects else {
            return;
        }
        var allRects = [CGRect]()

        allRects.append(contentsOf: humanRects)
        allRects.append(contentsOf: faceRects)

        let blurredImage = inSourceImage.image.applyingGaussianBlur(sigma: 50)

        autoreleasepool {
            let maskImage = maskImage(size: CGSize(width: inSourceImage.image.extent.width, height: inSourceImage.image.extent.height), maskRects: allRects)

            guard let filter = CIFilter(name: "CIBlendWithRedMask") else {
                finished (BlurredImage(blurredImage: NSImage(), timestamp: CMTime(), frameIndex: inSourceImage.frameIndex))
                return
            }

            filter.setValue( inSourceImage.image, forKey: kCIInputBackgroundImageKey)
            filter.setValue( blurredImage, forKey: kCIInputImageKey)
            filter.setValue( CIImage(cgImage: maskImage!), forKey: kCIInputMaskImageKey)

            if let result = filter.outputImage {
                finished (BlurredImage(blurredImage: NSImage.fromCIImage(result), timestamp: inSourceImage.timestamp, frameIndex: inSourceImage.frameIndex))
            } else {
                finished (BlurredImage(blurredImage: NSImage(), timestamp:inSourceImage.timestamp, frameIndex: inSourceImage.frameIndex))
            }
        }
    }

    func humanRectsForImageWithVision(_ inImage: CIImage,  finished: @escaping ([CGRect]) -> Void)
    {
        let handler=VNImageRequestHandler(ciImage: inImage)
        do{
            let request = VNDetectHumanRectanglesRequest {aRequest, error in
                autoreleasepool{
                    var foundFaceRects = [CGRect]()

                    if let results=aRequest.results as? [VNHumanObservation]{
                        for face_obs in results{
                            let ts=CGAffineTransform.identity.scaledBy(x: CGFloat(inImage.extent.width), y: CGFloat(inImage.extent.height))
                            let converted_rect=face_obs.boundingBox.applying(ts)
                            foundFaceRects.append(converted_rect)
                        }
                    }
                    finished(foundFaceRects)
                }
            }
            try handler.perform([request])
        }catch{
            print(error)
        }
    }

    func faceRectsForImageWithVision(_ inImage: CIImage, finished: @escaping ([CGRect]) -> Void)
    {
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
                    finished(foundFaceRects)
                }
            }
            request.revision = VNDetectFaceLandmarksRequestRevision3
            try handler.perform([request])
        }catch{
            print(error)
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
}
