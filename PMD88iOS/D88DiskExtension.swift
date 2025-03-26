import Foundation

// MARK: - D88Disk Extension for Sector Access
extension D88Disk {
    // セクタデータの読み込み
    func readSectorData(track: Int, sector: Int) throws -> [UInt8] {
        guard track < tracks.count else {
            throw DriveError.seekError
        }
        
        let trackData = tracks[track]
        guard let sectorData = trackData.sectors.first(where: { $0.record == sector }) else {
            throw DriveError.sectorNotFound
        }
        
        return Array(data[sectorData.dataOffset..<(sectorData.dataOffset + Int(sectorData.dataSize))])
    }
    
    // セクタデータの書き込み
    mutating func writeSectorData(track: Int, sector: Int, data: [UInt8]) throws {
        guard !writeProtected else {
            throw DriveError.writeProtected
        }
        
        guard track < tracks.count else {
            throw DriveError.seekError
        }
        
        guard let sectorIndex = tracks[track].sectors.firstIndex(where: { $0.record == sector }) else {
            throw DriveError.sectorNotFound
        }
        
        let sectorData = tracks[track].sectors[sectorIndex]
        guard data.count <= sectorData.dataSize else {
            throw DriveError.dataOverrun
        }
        
        // データの書き込み
        let startIndex = sectorData.dataOffset
        let endIndex = startIndex + Int(sectorData.dataSize)
        guard endIndex <= self.data.count else {
            throw DriveError.dataOverrun
        }
        
        // データの更新
        var newData = self.data
        for i in 0..<data.count {
            newData[startIndex + i] = data[i]
        }
        self.data = newData
    }
    
    // 書き込み保護状態の確認
    func isWriteProtected() -> Bool {
        return writeProtected
    }
    
    // トラック情報の取得
    func getTrackInfo(track: Int) -> D88Track? {
        guard track < tracks.count else {
            return nil
        }
        return tracks[track]
    }
    
    // セクタ情報の取得
    func getSectorInfo(track: Int, sector: Int) -> D88Sector? {
        guard let trackData = getTrackInfo(track: track) else {
            return nil
        }
        return trackData.sectors.first { $0.record == sector }
    }
}
