/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Custom anchor for saving camera screenshots in an ARWorldMap.
*/

import ARKit

class KeyPositionAnchor: ARAnchor {
    private(set) var image: UIImage
    private(set) var mappingStatus: ARFrame.WorldMappingStatus
    
    init(image: UIImage, transform: float4x4, mappingStatus: ARFrame.WorldMappingStatus) {
        self.image = image
        self.mappingStatus = mappingStatus
        super.init(name: "KeyPosition", transform: transform)
    }
    
    override class var supportsSecureCoding: Bool {
        return true
    }
    
    required init?(coder aDecoder: NSCoder) {
        if let image = aDecoder.decodeObject(of: UIImage.self, forKey: "image") {
            self.image = image
            let mappingValue = aDecoder.decodeInteger(forKey: "mappingStatus")
            self.mappingStatus = ARFrame.WorldMappingStatus(rawValue: mappingValue)!
        } else {
            return nil
        }
        super.init(coder: aDecoder)
    }
    
    override func encode(with aCoder: NSCoder) {
        super.encode(with: aCoder)
        aCoder.encode(image, forKey: "image")
        aCoder.encode(mappingStatus.rawValue, forKey: "mappingStatus")
    }
    
    override func copy(with zone: NSZone? = nil) -> Any {
        // required by objc method override
        let copy = super.copy(with: zone) as! KeyPositionAnchor
        copy.image = image
        copy.mappingStatus = mappingStatus
        return copy
    }
}
