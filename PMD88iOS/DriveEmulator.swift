import Foundation

// MARK: - Drive State
struct DriveState {
    var currentTrack: Int = 0
    var currentSector: Int = 1
    var headLoaded: Bool = false
    var lastAccessTime: Date = Date()
    var motorOn: Bool = false
}

// MARK: - Drive Timings
struct DriveTimings {
    static let headLoadTime: TimeInterval = 0.035    // 35ms
    static let headSettleTime: TimeInterval = 0.015  // 15ms
    static let trackToTrackTime: TimeInterval = 0.003 // 3ms
    static let rotationTime: TimeInterval = 0.2      // 300rpm = 200ms/回転
    static let sectorReadTime: TimeInterval = 0.002   // 2ms/セクタ
}

// MARK: - Sector Access Control
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

// MARK: - Drive Emulator
class DriveEmulator {
    private var driveState: DriveState
    private var disk: D88Disk
    private var lastError: DriveError?
    private var sectorCache: [Int: [UInt8]] = [:]
    
    init(disk: D88Disk) {
        self.disk = disk
        self.driveState = DriveState()
    }
    
    // モーター制御
    func setMotorState(_ state: Bool) {
        driveState.motorOn = state
        if !state {
            driveState.headLoaded = false
            clearCache()
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
        
        if disk.isWriteProtected() {
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
        
        // 4. 実際の書き込み
        try disk.writeSectorData(track: track, sector: sector, data: data)
        
        // キャッシュを更新
        let cacheKey = track * 100 + sector
        sectorCache[cacheKey] = data
        driveState.lastAccessTime = Date()
        driveState.currentSector = sector
    }
    
    // 連続セクタ読み込み
    func readSectors(track: Int, startSector: Int, count: Int) throws -> [[UInt8]] {
        var sectors: [[UInt8]] = []
        var currentSector = startSector
        
        for _ in 0..<count {
            let data = try readSector(track: track, sector: currentSector)
            sectors.append(data)
            currentSector = SectorAccess.calculateNextSector(current: currentSector)
        }
        
        return sectors
    }
    
    // キャッシュのクリア
    func clearCache() {
        sectorCache.removeAll()
    }
    
    // 現在のドライブ状態を取得
    func getDriveState() -> DriveState {
        return driveState
    }
    
    // 最後のエラーを取得
    func getLastError() -> DriveError? {
        return lastError
    }
}
