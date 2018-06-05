/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Convenience extension for generating screeshots from ARSCNView.
*/

import ARKit

private let log = Log()

extension ARSCNView {
    func createScreenshot(interfaceOrientation: UIDeviceOrientation) -> UIImage? {
        guard let frame = session.currentFrame else {
            log.error("Error: Failed to create a screenshot - no current ARFrame exists.")
            return nil
        }
        let ciImage = CIImage(cvPixelBuffer: frame.capturedImage)
        let context = CIContext()
        var orientation: UIImage.Orientation = .right
        switch interfaceOrientation {
        case .portrait:
            orientation = .right
        case .portraitUpsideDown:
            orientation = .left
        case .landscapeLeft:
            orientation = .up
        case .landscapeRight:
            orientation = .down
        default:
            break
        }
        if let cgimage = context.createCGImage(ciImage, from: ciImage.extent) {
            return UIImage(cgImage: cgimage, scale: 1.0, orientation: orientation)
        }
        return nil
    }
}
