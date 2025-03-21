import Foundation

struct D88Disk {
    let data: [UInt8]
    
    init(from fileData: Data) {
        self.data = [UInt8](fileData)
    }
    
    func extractFile(at offset: Int, size: Int) -> [UInt8] {
        return Array(data[offset..<min(offset + size, data.count)])
    }
} 
