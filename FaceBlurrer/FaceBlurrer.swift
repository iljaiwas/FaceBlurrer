//
//  FaceBlurrer.swift
//  FaceBlurrer
//
//  Created by ilja on 03.07.2022.
//

import Foundation
import CoreImage
import Vision

class FaceBlurrer
{
    var humanRects: [CGRect]?
    var faceRects: [CGRect]?
    var blurredImage = CIImage()
    var sourceImage = CIImage()

    func blurrFaces( _ inSourceImage : CIImage, finished: @escaping (CIImage?) -> Void)
    {
        sourceImage = inSourceImage
        blurredImage = inSourceImage.applyingGaussianBlur(sigma: 50)

        humanRectsForImageWithVision (inSourceImage) { [self] (foundHumanRects) in
            humanRects = foundHumanRects
            checkIfDetectionDone (finished)
        }
        faceRectsForImageWithVision (inSourceImage) { [self] (foundFaceRects) in
            faceRects = foundFaceRects
            checkIfDetectionDone (finished)
        }
    }

    func checkIfDetectionDone (_ finished: (CIImage?) -> Void) {
        guard let humanRects = humanRects, let faceRects = faceRects else {
            return;
        }
        var allRects = [CGRect]()

        allRects.append(contentsOf: humanRects)
        allRects.append(contentsOf: faceRects)

        autoreleasepool {
            let maskImage = maskImage(size: CGSize(width: sourceImage.extent.width, height: sourceImage.extent.height), maskRects: allRects)

            guard let filter = CIFilter(name: "CIBlendWithRedMask") else {
                finished (nil)
                return
            }

            filter.setValue( sourceImage, forKey: kCIInputBackgroundImageKey)
            filter.setValue( blurredImage, forKey: kCIInputImageKey)
            filter.setValue( CIImage(cgImage: maskImage!), forKey: kCIInputMaskImageKey)

            let resultImage = filter.outputImage
            finished (resultImage)
        }
    }

    func blurredImageFromImage (_ inImage: CIImage) -> CIImage? {

        var resultImage : CIImage?

        autoreleasepool {
            guard let filter = CIFilter(name: "CIGaussianBlur") else {
                return
            }
            filter.setValue(inImage, forKey: kCIInputImageKey)
            filter.setValue(150.0, forKey: kCIInputRadiusKey)
            resultImage = filter.outputImage
        }
        return resultImage
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
