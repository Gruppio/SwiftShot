/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Convenience extension for rotating images.
*/

import UIKit

extension UIImage {
    func rotatedImage(orientation: UIInterfaceOrientation) -> UIImage? {
        var size = CGSize(width: self.size.width, height: self.size.height)
        if orientation == .portrait {
            size = CGSize(width: self.size.height, height: self.size.width)
        }
        UIGraphicsBeginImageContext(size)
        guard let cgContext = UIGraphicsGetCurrentContext() else {
            return nil
        }
        
        if orientation == .portrait {
            cgContext.rotate(by: CGFloat(Float.pi / 2))
            cgContext.translateBy(x: 0, y: -self.size.height)
        } else {
            cgContext.translateBy(x: self.size.width / 2, y: self.size.height / 2)
            cgContext.rotate(by: CGFloat(Float.pi))
            cgContext.translateBy(x: -self.size.width / 2, y: -self.size.height / 2)
        }
        
        draw(at: CGPoint(x: 0, y: 0))
        let rotatedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return rotatedImage
    }
}
