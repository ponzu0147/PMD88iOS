import Foundation

// MARK: - ドライブタイミング定数
struct DriveTimings {
    static let headLoadTime: TimeInterval = 0.035    // 35ms
    static let headSettleTime: TimeInterval = 0.015  // 15ms
    static let trackToTrackTime: TimeInterval = 0.003 // 3ms
    static let rotationTime:[sudo] password for user: TimeInterval = 0.2      // 300rpm = 200ms/回転
    static let sectorReadTime: TimeInterval = 0.002   // 2ms/セクタ
}

// MARK: - ドライブ状態管理
struct DriveState {
    var currentTrack: Int = 0
    var currentSector: Int = 1
    var headLoaded: Bool = false
    var lastAccessTime: Date = Date()
    var motorOn: Bool = false
    var writeProtected: Bool = false
}

// MARK: - セクタアクセス制御
struct SectorAccess {
    // インターリーブテーブル（1:1の場合）
    static let interleaveTable: [Int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
    
    // 物理的なセクタ配置を考慮したアクセス
    static func calculateNextSector(current: Int) -> Int {
        let index = interleaveTable.firstIndex(of: current) ?? 0
        return interleaveTable[(index + 1) % interleaveTable.count]
    }
    
    // セクタの物理位置を計算（0-359度）
    static func calculateSectorPosition(sector: Int) -> Double {
        return Double(sector - 1) * (360.0 / Double(interleaveTable.count))
    }
}

// MARK: - ドライブエラー定義
enum DriveError: Error {
    case sectorNotFound
    case crcError
    case writeProtected
    case diskChanged
    case seekError
    case noReadySignal
    case dataOverrun
    
    var description: String {
        switch self {
        case .sectorNotFound: return "セクタが見つかりません"
        case .crcError: return "CRCエラー"
        case .writeProtected: return "書き込み保護されています"
        case .diskChanged: return "ディスクが交換されました"
        case .seekError: return "シークエラー"
        case .noReadySignal: return "ドライブの準備ができていません"
        case .dataOverrun: return "データオーバーラン"
        }
    }
}

// MARK: - エラー処理
struct ErrorHandling {
    // CRCチェック実装
    static func verifyCRC(_ data: [UInt8], expected: UInt16) -> Bool {
        var crc: UInt16 = 0xFFFF
        for byte in data {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                if (crc & 0x8000) != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    crc <<= 1
                }
            }
        }
        return crc == expected
    }
    
    // セクタデータの検証
    static func validateSectorData(_ data: [UInt8]) -> Bool {
        guard data.count >= 2 else { return false }
        let storedCRC = UInt16(data[data.count - 2]) << 8 | UInt16(data[data.count - 1])
        let dataToVerify = Array(data.dropLast(2))
        return verifyCRC(dataToVerify, expected: storedCRC)
    }
}

// MARK: - D88ドライブエミュレータ
class D88DriveEmulator {
    private var driveState: DriveState
    private var disk: D88Disk
    private var lastError: DriveError?
    private var sectorCache: [Int: [UInt8]] = [:]
    
    init(disk: D88Disk) {
        self.disk = disk
        self.driveState = DriveState()
        self.driveState.writeProtected = disk.isWriteProtected()
    }
    
    // モーター制御
    func setMotorState(_ state: Bool) {
        driveState.motorOn = state
        if !state {
            driveState.headLoaded = false
        }
    }
    
    // ヘッド移動
    private func seekTrack(_ track: Int) throws {
        guard driveState.motorOn else {
            throw DriveError.noReadySignal
        }
        
        let trackDiff = abs(track - driveState.currentTrack)
        if trackDiff > 0 {
            // ヘッド移動時間をシミュレート
            Thread.sleep(forTimeInterval: Double(trackDiff) * DriveTimings.trackToTrackTime)
            // セトリング時間
            Thread.sleep(forTimeInterval: DriveTimings.headSettleTime)
        }
        
        driveState.currentTrack = track
    }
    
    // セクタ読み込み（タイミング制御付き）
    func readSector(track: Int, sector: Int) throws -> [UInt8] {
        guard driveState.motorOn else {
            throw DriveError.noReadySignal
        }
        
        // キャッシュチェック
        let cacheKey = track * 100 + sector
        if let cachedData = sectorCache[cacheKey] {
            return cachedData
        }
        
        // 1. ヘッド移動
        try seekTrack(track)
        
        // 2. ヘッドロード
        if !driveState.headLoaded {
            Thread.sleep(forTimeInterval: DriveTimings.headLoadTime)
            driveState.headLoaded = true
        }
        
        // 3. セクタ待ち時間の計算（回転待ち）
        let currentRotationPosition = Date().timeIntervalSince(driveState.lastAccessTime)
            .truncatingRemainder(dividingBy: DriveTimings.rotationTime)
        let targetSectorPosition = SectorAccess.calculateSectorPosition(sector: sector) * 
            (DriveTimings.rotationTime / 360.0)
        let waitTime = (targetSectorPosition - currentRotationPosition + DriveTimings.rotationTime)
            .truncatingRemainder(dividingBy: DriveTimings.rotationTime)
        
        Thread.sleep(forTimeInterval: waitTime)
        
        // 4. 実際のセクタ読み込み
        let sectorData = try disk.readSectorData(track: track, sector: sector)
        
        // 5. CRCチェック
        if !ErrorHandling.validateSectorData(sectorData) {
            throw DriveError.crcError
        }
        
        // キャッシュに保存
        sectorCache[cacheKey] = sectorData
        driveState.lastAccessTime = Date()
        driveState.currentSector = sector
        
        return sectorData
    }
    
    // セクタ書き込み
    func writeSector(track: Int, sector: Int, data: [UInt8]) throws {
        guard driveState.motorOn else {
            throw DriveError.noReadySignal
        }
        
        if driveState.writeProtected {
            throw DriveError.writeProtected
        }
        
        // 1. ヘッド移動
        try seekTrack(track)
        
        // 2. ヘッドロード
        if !driveState.headLoaded {
            Thread.sleep(forTimeInterval: DriveTimings.headLoadTime)
            driveState.headLoaded = true
        }
        
        // 3. セクタ待ち時間
        let currentRotationPosition = Date().timeIntervalSince(driveState.lastAccessTime)
            .truncatingRemainder(dividingBy: DriveTimings.rotationTime)
        let targetSectorPosition = SectorAccess.calculateSectorPosition(sector: sector) * 
            (DriveTimings.rotationTime / 360.0)
        let waitTime = (targetSectorPosition - currentRotationPosition + DriveTimings.rotationTime)
            .truncatingRemainder(dividingBy: DriveTimings.rotationTime)
        
        Thread.sleep(forTimeInterval: waitTime)
        
        // 4. データにCRCを付加
        var dataWithCRC = data
        let crc = calculateCRC(data)
        dataWithCRC.append(UInt8(crc >> 8))
        dataWithCRC.append(UInt8(crc & 0xFF))
        
        // 5. 実際の書き込み
        try disk.writeSectorData(track: track, sector: sector, data: dataWithCRC)
        
        // キャッシュを更新
        let cacheKey = track * 100 + sector
        sectorCache[cacheKey] = dataWithCRC
        driveState.lastAccessTime = Date()
        driveState.currentSector = sector
    }
    
    // CRC計算
    private func calculateCRC(_ data: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in data {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                if (crc & 0x8000) != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    crc <<= 1
                }
            }
        }
        return crc
    }
    
    // キャッシュのクリア
    func clearCache() {
        sectorCache.removeAll()
    }
    
    // 最後のエラーを取得
    func getLastError() -> DriveError? {
        return lastError
    }
}
