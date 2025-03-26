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
// MARK: - Cache Statistics
/// キャッシュの統計情報を保持する構造体
struct CacheStatistics {
    let currentSize: Int          // 現在のキャッシュサイズ
    let maxSize: Int             // 最大キャッシュサイズ
    let hitCount: Int            // キャッシュヒット数
    let missCount: Int           // キャッシュミス数
    let hitRate: Double          // ヒット率
    let evictionCount: Int       // キャッシュからの削除数
    let timeoutCount: Int        // タイムアウトによる無効化数
    let averageAccessTime: TimeInterval  // 平均アクセス時間
    let lastAccessTime: Date?     // 最後のアクセス時刻
    
    var utilizationRate: Double { Double(currentSize) / Double(maxSize) }
    var missRate: Double { 1.0 - hitRate }
}

/// 内部用の統計情報記録構造体
struct CacheStats {
    var hitCount: Int = 0
    var missCount: Int = 0
    var evictionCount: Int = 0
    var timeoutCount: Int = 0
    var totalAccessTime: TimeInterval = 0
    var lastAccessTime: Date?
    
    var totalCount: Int { hitCount + missCount }
    var hitRate: Double { totalCount > 0 ? Double(hitCount) / Double(totalCount) : 0 }
    var averageAccessTime: TimeInterval { totalCount > 0 ? totalAccessTime / Double(totalCount) : 0 }
    
    mutating func recordHit(accessTime: TimeInterval) {
        hitCount += 1
        totalAccessTime += accessTime
        lastAccessTime = Date()
    }
    
    mutating func recordMiss(accessTime: TimeInterval) {
        missCount += 1
        totalAccessTime += accessTime
        lastAccessTime = Date()
    }
    
    mutating func recordEviction() {
        evictionCount += 1
    }
    
    mutating func recordTimeout() {
        timeoutCount += 1
    }
}

// MARK: - Cache Configuration
struct CacheConfig {
    static let maxCacheSize = 256 // 最大キャッシュサイズ（セクタ数）
    static let cacheTimeout: TimeInterval = 5.0 // キャッシュタイムアウト（秒）
}

// MARK: - Cache Entry
struct CacheEntry {
    let data: [UInt8]
    let timestamp: Date
    
    var isValid: Bool {
        return Date().timeIntervalSince(timestamp) < CacheConfig.cacheTimeout
    }
}

class DriveEmulator {
    private var driveState: DriveState
    private var disk: D88Disk
    private var lastError: DriveError?
    private var sectorCache: [Int: CacheEntry] = [:]
    private var cacheStats = CacheStats()
    
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
        let startTime = Date()
        let cacheKey = track * 100 + sector
        
        if let cachedEntry = sectorCache[cacheKey] {
            if cachedEntry.isValid {
                let accessTime = Date().timeIntervalSince(startTime)
                cacheStats.recordHit(accessTime: accessTime)
                return cachedEntry.data
            } else {
                cacheStats.recordTimeout()
            }
        }
        
        // 古いキャッシュエントリを削除
        cleanCache()
        let accessTime = Date().timeIntervalSince(startTime)
        cacheStats.recordMiss(accessTime: accessTime)
        
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
    
    // MARK: - Cache Management
    
    /// キャッシュをクリア
    func clearCache() {
        sectorCache.removeAll()
    }
    
    /// 古いキャッシュエントリを削除
    private func cleanCache() {
        let now = Date()
        sectorCache = sectorCache.filter { $0.value.isValid }
        
        // キャッシュサイズが最大値を超えている場合、古いエントリから削除
        if sectorCache.count > CacheConfig.maxCacheSize {
            let sortedEntries = sectorCache.sorted { $0.value.timestamp > $1.value.timestamp }
            let entriesToRemove = sortedEntries[CacheConfig.maxCacheSize...]
            for entry in entriesToRemove {
                sectorCache.removeValue(forKey: entry.key)
                cacheStats.recordEviction()
            }
        }
    }
    
    /// キャッシュを更新
    private func updateCache(key: Int, data: [UInt8]) {
        cleanCache() // 更新前に古いエントリを削除
        
        // キャッシュサイズに余裕がある場合のみ追加
        if sectorCache.count < CacheConfig.maxCacheSize {
            sectorCache[key] = CacheEntry(data: data, timestamp: Date())
        }
    }
    
    /// キャッシュの詳細な統計情報を取得
    func getCacheStats() -> CacheStatistics {
        return CacheStatistics(
            currentSize: sectorCache.count,
            maxSize: CacheConfig.maxCacheSize,
            hitCount: cacheStats.hitCount,
            missCount: cacheStats.missCount,
            hitRate: cacheStats.hitRate,
            evictionCount: cacheStats.evictionCount,
            timeoutCount: cacheStats.timeoutCount,
            averageAccessTime: cacheStats.averageAccessTime,
            lastAccessTime: cacheStats.lastAccessTime
        )
    }
    
    /// キャッシュの統計情報をリセット
    func resetCacheStats() {
        cacheStats = CacheStats()
    }
}
