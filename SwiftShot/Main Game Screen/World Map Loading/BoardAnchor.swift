/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Custom anchor for saving the board location in an ARWorldMap.
*/

import ARKit

class BoardAnchor: ARAnchor {
    private(set) var size: CGSize
    
    init(transform: float4x4, size: CGSize) {
        self.size = size
        super.init(name: "Board", transform: transform)
    }
    
    override class var supportsSecureCoding: Bool {
        return true
    }
    
    required init?(coder aDecoder: NSCoder) {
        self.size = aDecoder.decodeCGSize(forKey: "size")
        super.init(coder: aDecoder)
    }
    
    override func encode(with aCoder: NSCoder) {
        super.encode(with: aCoder)
        aCoder.encode(size, forKey: "size")
    }
    
    override func copy(with zone: NSZone? = nil) -> Any {
        // required by objc method override
        let copy = super.copy(with: zone) as! BoardAnchor
        copy.size = size
        return copy
    }
}
