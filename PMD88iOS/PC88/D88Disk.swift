import Foundation

/// D88ディスクイメージを解析するためのクラス
class D88Disk {
    // D88ヘッダ情報
    struct Header {
        var diskName: String
        var writeProtected: Bool
        var mediaType: UInt8
        var diskSize: UInt32
        
        // メディアタイプの定義
        static let MEDIA_TYPE_2D: UInt8 = 0x00
        static let MEDIA_TYPE_2DD: UInt8 = 0x10
        static let MEDIA_TYPE_2HD: UInt8 = 0x20
        
        // メディアタイプを文字列で取得
        var mediaTypeString: String {
            switch mediaType {
            case Header.MEDIA_TYPE_2D:
                return "2D"
            case Header.MEDIA_TYPE_2DD:
                return "2DD"
            case Header.MEDIA_TYPE_2HD:
                return "2HD"
            default:
                return "不明(\(String(format: "0x%02X", mediaType)))"
            }
        }
    }
    
    // セクタ情報
    struct Sector {
        var cylinder: UInt8    // C - シリンダ/トラック番号
        var head: UInt8        // H - ヘッド/面番号
        var sectorID: UInt8    // R - セクタID
        var sizeCode: UInt8    // N - セクタサイズコード
        var numberOfSectors: UInt16  // セクタ数
        var density: UInt8     // 記録密度
        var deletedMark: UInt8 // 削除フラグ
        var status: UInt8      // ステータス
        var reserved: [UInt8]  // 予約領域
        var sizeInBytes: UInt16 // セクタサイズ（バイト）
        var data: [UInt8]      // セクタデータ
        
        // セクタサイズコードからバイト数を計算
        static func sizeFromCode(_ code: UInt8) -> UInt16 {
            return UInt16(128 << code)
        }
    }
    
    // トラック情報
    struct Track {
        var sectors: [Sector] = []
        var sectorCount: Int { return sectors.count }
    }
    
    // ディスク情報
    var header: Header
    var tracks: [Track?]
    var trackCount: Int = 0
    var maxSectors: Int = 0
    
    // トラックテーブル（オフセット値）
    var trackTable: [UInt32] = []
    
    // 生データ
    private var rawData: [UInt8]
    
    // 初期化
    init?(data: Data) {
        let bytes = [UInt8](data)
        self.rawData = bytes
        
        // データサイズチェック
        if bytes.count < 0x2B0 { // ヘッダ + トラックテーブル
            return nil
        }
        
        // ディスク名の取得
        let diskNameData = bytes[0..<16]
        let diskName = String(bytes: diskNameData, encoding: .ascii)?.trimmingCharacters(in: .controlCharacters) ?? "不明"
        
        // 書き込み保護フラグ
        let writeProtected = bytes[0x1A] != 0
        
        // メディアタイプ
        let mediaType = bytes[0x1B]
        
        // ディスクサイズ
        let diskSize = UInt32(bytes[0x1C]) | (UInt32(bytes[0x1D]) << 8) | (UInt32(bytes[0x1E]) << 16) | (UInt32(bytes[0x1F]) << 24)
        
        // ヘッダ情報の設定
        self.header = Header(
            diskName: diskName,
            writeProtected: writeProtected,
            mediaType: mediaType,
            diskSize: diskSize
        )
        
        // トラックテーブルの読み込み
        trackTable = []
        for i in 0..<164 {
            let offset = 0x20 + (i * 4)
            let trackOffset = UInt32(bytes[offset]) | (UInt32(bytes[offset+1]) << 8) | (UInt32(bytes[offset+2]) << 16) | (UInt32(bytes[offset+3]) << 24)
            trackTable.append(trackOffset)
            
            if trackOffset > 0 {
                trackCount = i + 1
            }
        }
        
        // トラック情報の初期化
        tracks = Array(repeating: nil, count: 164)
        
        // 各トラックのセクタ情報を解析
        for trackIndex in 0..<trackCount {
            if trackTable[trackIndex] == 0 {
                continue
            }
            
            var track = Track()
            var offset = Int(trackTable[trackIndex])
            
            // セクタ数の取得
            if offset + 1 < bytes.count {
                let sectorCount = UInt16(bytes[offset]) | (UInt16(bytes[offset+1]) << 8)
                offset += 2
                
                // 各セクタの情報を解析
                for _ in 0..<sectorCount {
                    if offset + 0x10 >= bytes.count {
                        break
                    }
                    
                    let c = bytes[offset]
                    let h = bytes[offset+1]
                    let r = bytes[offset+2]
                    let n = bytes[offset+3]
                    let sectors = UInt16(bytes[offset+4]) | (UInt16(bytes[offset+5]) << 8)
                    let density = bytes[offset+6]
                    let deletedMark = bytes[offset+7]
                    let status = bytes[offset+8]
                    let reserved = Array(bytes[offset+9..<offset+0xE])
                    let sectorSize = UInt16(bytes[offset+0xE]) | (UInt16(bytes[offset+0xF]) << 8)
                    
                    // セクタデータの取得
                    let dataOffset = offset + 0x10
                    var sectorData: [UInt8] = []
                    
                    if dataOffset + Int(sectorSize) <= bytes.count {
                        sectorData = Array(bytes[dataOffset..<dataOffset+Int(sectorSize)])
                    }
                    
                    // セクタ情報の作成
                    let sector = Sector(
                        cylinder: c,
                        head: h,
                        sectorID: r,
                        sizeCode: n,
                        numberOfSectors: sectors,
                        density: density,
                        deletedMark: deletedMark,
                        status: status,
                        reserved: reserved,
                        sizeInBytes: sectorSize,
                        data: sectorData
                    )
                    
                    track.sectors.append(sector)
                    
                    // 次のセクタへ
                    offset += 0x10 + Int(sectorSize)
                }
                
                // トラック情報を保存
                tracks[trackIndex] = track
                
                // 最大セクタ数の更新
                maxSectors = max(maxSectors, track.sectorCount)
            }
        }
    }
    
    // 指定したトラック・セクタのデータを取得
    func getSectorData(track: Int, sector: Int) -> [UInt8]? {
        guard track < tracks.count, let trackInfo = tracks[track] else {
            return nil
        }
        
        for sectorInfo in trackInfo.sectors {
            if Int(sectorInfo.sectorID) == sector {
                return sectorInfo.data
            }
        }
        
        return nil
    }
    
    // ディスク情報の文字列表現を取得
    func getDiskInfoString() -> String {
        var info = "D88ディスク情報:\n"
        info += "ディスク名: \(header.diskName)\n"
        info += "メディアタイプ: \(header.mediaTypeString)\n"
        info += "書き込み保護: \(header.writeProtected ? "あり" : "なし")\n"
        info += "ディスクサイズ: \(header.diskSize)バイト\n"
        info += "トラック数: \(trackCount)\n"
        info += "最大セクタ数/トラック: \(maxSectors)\n"
        
        return info
    }
    
    // PMD88プログラムと音楽データを抽出
    func extractPMD88MusicData() -> (programData: [UInt8]?, musicData: [UInt8]?, toneData: [UInt8]?) {
        // 初期値
        var programData: [UInt8]? = nil
        var musicData: [UInt8]? = nil
        var toneData: [UInt8]? = nil
        
        // PMD88プログラムは通常トラック0にある
        if trackCount > 0, let track0 = tracks[0] {
            // トラック0の全セクタデータを結合
            var allSectorData: [UInt8] = []
            for sector in track0.sectors {
                allSectorData.append(contentsOf: sector.data)
            }
            
            // PMD88シグネチャを探す
            // "PMD88"のASCIIコード: [0x50, 0x4D, 0x44, 0x38, 0x38]
            let pmdSignature: [UInt8] = [0x50, 0x4D, 0x44, 0x38, 0x38]
            
            // シグネチャを探す
            for i in 0..<(allSectorData.count - pmdSignature.count) {
                var found = true
                for j in 0..<pmdSignature.count {
                    if allSectorData[i + j] != pmdSignature[j] {
                        found = false
                        break
                    }
                }
                
                if found {
                    // PMD88プログラムを抽出
                    let programStartIndex = max(0, i - 512)  // シグネチャの512バイト前から
                    let programEndIndex = min(allSectorData.count, i + 16384)  // 16KBほど
                    programData = Array(allSectorData[programStartIndex..<programEndIndex])
                    
                    // 曲データは通常シグネチャから4KB後にある
                    let musicStartOffset = min(allSectorData.count - 1, i + 4096)
                    let musicEndIndex = min(allSectorData.count, musicStartOffset + 8192)  // 8KBほど
                    if musicEndIndex > musicStartOffset {
                        musicData = Array(allSectorData[musicStartOffset..<musicEndIndex])
                    }
                    
                    // 音色データは通常曲データの後にある
                    let toneStartOffset = min(allSectorData.count - 1, musicEndIndex)
                    let toneEndIndex = min(allSectorData.count, toneStartOffset + 4096)  // 4KBほど
                    if toneEndIndex > toneStartOffset {
                        toneData = Array(allSectorData[toneStartOffset..<toneEndIndex])
                    }
                    
                    break
                }
            }
        }
        
        return (programData, musicData, toneData)
    }
    
    // D88ファイルからPMD88関連ファイルを抽出
    func extractPMD88Files() -> [String: [UInt8]] {
        var files: [String: [UInt8]] = [:]
        
        // トラック0のデータを結合
        if trackCount > 0, let track0 = tracks[0] {
            var allSectorData: [UInt8] = []
            for sector in track0.sectors {
                allSectorData.append(contentsOf: sector.data)
            }
            
            // MCGファイルのパターンを探す
            // "MCG"のASCIIコード: [0x4D, 0x43, 0x47]
            let mcgSignature: [UInt8] = [0x4D, 0x43, 0x47]
            
            for i in 0..<(allSectorData.count - mcgSignature.count) {
                var found = true
                for j in 0..<mcgSignature.count {
                    if allSectorData[i + j] != mcgSignature[j] {
                        found = false
                        break
                    }
                }
                
                if found {
                    // MCGデータを抽出
                    let mcgStartIndex = max(0, i - 16)  // シグネチャの少し前から
                    let mcgEndIndex = min(allSectorData.count, i + 4096)  // 4KBほど
                    files["mcg"] = Array(allSectorData[mcgStartIndex..<mcgEndIndex])
                    break
                }
            }
        }
        
        return files
    }
    
    // PC-8801のディスクファイルシステムからファイルを検索して読み込む
    func findAndLoadFile(fileName: String) -> [UInt8]? {
        // ファイル名を大文字に変換（PC-8801のファイル名は大文字）
        let upperFileName = fileName.uppercased()
        
        // ファイル名の拡張子を分離
        var baseName = upperFileName
        var fileExtension = ""
        
        if let dotIndex = upperFileName.lastIndex(of: ".") {
            baseName = String(upperFileName[..<dotIndex])
            fileExtension = String(upperFileName[upperFileName.index(after: dotIndex)...])
        }
        
        // ファイル名とエクステンションを8.3形式に調整
        let fileNamePadded = baseName.padding(toLength: 8, withPad: " ", startingAt: 0)
        let extensionPadded = fileExtension.padding(toLength: 3, withPad: " ", startingAt: 0)
        
        // ディレクトリエントリを探す
        for trackIndex in 0..<trackCount {
            guard let track = tracks[trackIndex] else { continue }
            
            // トラックのセクタを結合
            var trackData: [UInt8] = []
            for sector in track.sectors {
                trackData.append(contentsOf: sector.data)
            }
            
            // ディレクトリエントリを検索
            for entryOffset in stride(from: 0, to: trackData.count, by: 32) {
                if entryOffset + 32 > trackData.count { break }
                
                // ファイル属性をチェック（削除済みでないか）
                let fileAttribute = trackData[entryOffset]
                if fileAttribute == 0xFF { continue }  // 削除済みエントリ
                
                // ファイル名とエクステンションを取得
                let entryFileName = String(bytes: trackData[entryOffset+1..<entryOffset+9], encoding: .ascii)?.trimmingCharacters(in: .controlCharacters) ?? ""
                let entryExtension = String(bytes: trackData[entryOffset+9..<entryOffset+12], encoding: .ascii)?.trimmingCharacters(in: .controlCharacters) ?? ""
                
                // ファイル名とエクステンションが一致するか確認
                if entryFileName == fileNamePadded && entryExtension == extensionPadded {
                    // ファイルの先頭クラスタ番号
                    let startCluster = Int(trackData[entryOffset+16]) | (Int(trackData[entryOffset+17]) << 8)
                    
                    // ファイルサイズ
                    let fileSize = Int(trackData[entryOffset+18]) | 
                                   (Int(trackData[entryOffset+19]) << 8) |
                                   (Int(trackData[entryOffset+20]) << 16) |
                                   (Int(trackData[entryOffset+21]) << 24)
                    
                    // ファイルデータを読み込む
                    return loadFileData(startCluster: startCluster, fileSize: fileSize)
                }
            }
        }
        
        return nil
    }
    
    // 指定されたクラスタからファイルデータを読み込む
    // ファイルを名前で検索する
    func findFile(fileName: String) -> (found: Bool, cluster: Int, size: Int) {
        // ファイル名を大文字に変換（PC-8801のファイル名は大文字）
        let upperFileName = fileName.uppercased()
        
        // ルートディレクトリを探索
        for track in 1...39 {
            for sector in 1...16 {
                if let sectorData = readSector(track: track, sectorID: sector) {
                    // ディレクトリエントリを検索
                    for i in stride(from: 0, to: sectorData.count, by: 32) {
                        if i + 32 <= sectorData.count {
                            let entryName = String(bytes: Array(sectorData[i..<i+8]), encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? ""
                            let entryExt = String(bytes: Array(sectorData[i+8..<i+11]), encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? ""
                            let fullName = entryName + (entryExt.isEmpty ? "" : ".") + entryExt
                            
                            if fullName.uppercased() == upperFileName {
                                let startCluster = Int(sectorData[i+26]) | (Int(sectorData[i+27]) << 8)
                                let fileSize = Int(sectorData[i+28]) | (Int(sectorData[i+29]) << 8) | (Int(sectorData[i+30]) << 16) | (Int(sectorData[i+31]) << 24)
                                return (true, startCluster, fileSize)
                            }
                        }
                    }
                }
            }
        }
        
        return (false, 0, 0)
    }
    
    // 最初のファイルを検索する
    func findFirstFile() -> (found: Bool, fileName: String, cluster: Int, size: Int) {
        // ルートディレクトリの最初のセクタを読み込む
        if let sectorData = readSector(track: 1, sectorID: 1) {
            // 最初の有効なディレクトリエントリを検索
            for i in stride(from: 0, to: sectorData.count, by: 32) {
                if i + 32 <= sectorData.count && sectorData[i] != 0 && sectorData[i] != 0xE5 {
                    let entryName = String(bytes: Array(sectorData[i..<i+8]), encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? ""
                    let entryExt = String(bytes: Array(sectorData[i+8..<i+11]), encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? ""
                    let fullName = entryName + (entryExt.isEmpty ? "" : ".") + entryExt
                    
                    let startCluster = Int(sectorData[i+26]) | (Int(sectorData[i+27]) << 8)
                    let fileSize = Int(sectorData[i+28]) | (Int(sectorData[i+29]) << 8) | (Int(sectorData[i+30]) << 16) | (Int(sectorData[i+31]) << 24)
                    
                    return (true, fullName, startCluster, fileSize)
                }
            }
        }
        
        return (false, "", 0, 0)
    }
    
    // 次のファイルを検索する
    func findNextFile() -> (found: Bool, fileName: String, cluster: Int, size: Int) {
        // 現在の検索位置から次のファイルを検索
        // 実際の実装ではDTAなどの情報を使用して検索位置を管理する必要があります
        // ここでは簡易的な実装
        
        // ルートディレクトリの次のセクタを読み込む
        if let sectorData = readSector(track: 1, sectorID: 2) {
            // 最初の有効なディレクトリエントリを検索
            for i in stride(from: 0, to: sectorData.count, by: 32) {
                if i + 32 <= sectorData.count && sectorData[i] != 0 && sectorData[i] != 0xE5 {
                    let entryName = String(bytes: Array(sectorData[i..<i+8]), encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? ""
                    let entryExt = String(bytes: Array(sectorData[i+8..<i+11]), encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? ""
                    let fullName = entryName + (entryExt.isEmpty ? "" : ".") + entryExt
                    
                    let startCluster = Int(sectorData[i+26]) | (Int(sectorData[i+27]) << 8)
                    let fileSize = Int(sectorData[i+28]) | (Int(sectorData[i+29]) << 8) | (Int(sectorData[i+30]) << 16) | (Int(sectorData[i+31]) << 24)
                    
                    return (true, fullName, startCluster, fileSize)
                }
            }
        }
        
        return (false, "", 0, 0)
    }
    
    // クラスタからファイルデータをロードする
    func loadFileDataFromCluster(cluster: Int, size: Int) -> [UInt8]? {
        return loadFileData(startCluster: cluster, fileSize: size)
    }
    
    internal func loadFileData(startCluster: Int, fileSize: Int) -> [UInt8]? {
        var fileData: [UInt8] = []
        var currentCluster = startCluster
        
        // FAT領域はトラック1のセクタ1-3に格納されていることが多い
        guard let fatTrack = tracks[1], fatTrack.sectors.count >= 3 else { return nil }
        
        // FAT領域を結合
        var fatData: [UInt8] = []
        for sectorIndex in 0..<3 {
            if sectorIndex < fatTrack.sectors.count {
                fatData.append(contentsOf: fatTrack.sectors[sectorIndex].data)
            }
        }
        
        // データ領域はトラック1のセクタ4から始まることが多い
        let dataTrackIndex = 1
        let dataSectorIndex = 3
        
        // クラスタチェーンをたどる
        while currentCluster >= 2 && currentCluster < 0xFF0 {
            // クラスタのセクタを読み込む（1クラスタ = 1セクタと仮定）
            let trackIndex = dataTrackIndex + (currentCluster / 8)
            let sectorIndex = dataSectorIndex + (currentCluster % 8)
            
            if trackIndex < trackCount, let track = tracks[trackIndex], sectorIndex < track.sectors.count {
                fileData.append(contentsOf: track.sectors[sectorIndex].data)
                
                // 次のクラスタを取得
                let fatOffset = currentCluster * 2
                if fatOffset + 1 < fatData.count {
                    currentCluster = Int(fatData[fatOffset]) | (Int(fatData[fatOffset+1]) << 8)
                } else {
                    break
                }
            } else {
                break
            }
            
            // ファイルサイズに達したら終了
            if fileData.count >= fileSize {
                break
            }
        }
        
        // ファイルサイズに合わせてトリミング
        if fileData.count > fileSize {
            fileData = Array(fileData[0..<fileSize])
        }
        
        return fileData
    }
    
    /// ブートセクタを読み込む
    /// - Returns: ブートセクタのデータ（256バイト）、読み込み失敗時はnil
    func loadBootSector() -> [UInt8]? {
        // トラック0、セクタ1がブートセクタ
        guard let track0 = tracks[0], track0.sectorCount > 0 else {
            return nil
        }
        
        // セクタ1を探す
        for sector in track0.sectors {
            if sector.sectorID == 1 {
                return sector.data
            }
        }
        
        return nil
    }
    
    /// IPLコードを読み込む
    /// - Returns: IPLコードのデータ（256バイト）、読み込み失敗時はnil
    func loadIPLCode() -> [UInt8]? {
        return loadBootSector()
    }
    
    /// トラックとセクタ番号を指定してセクタデータを読み込む
    /// - Parameters:
    ///   - track: トラック番号
    ///   - sectorID: セクタ番号
    /// - Returns: セクタデータ、読み込み失敗時はnil
    func readSector(track: Int, sectorID: Int) -> [UInt8]? {
        guard track < tracks.count, let trackData = tracks[track] else {
            return nil
        }
        
        for sector in trackData.sectors {
            if sector.sectorID == UInt8(sectorID) {
                return sector.data
            }
        }
        
        return nil
    }
    
    /// トラックとセクタ番号を指定してメモリにセクタデータをロード
    /// - Parameters:
    ///   - track: トラック番号
    ///   - sectorID: セクタ番号
    ///   - memory: メモリ配列
    ///   - address: ロード先アドレス
    /// - Returns: 成功時true、失敗時false
    func loadSectorToMemory(track: Int, sectorID: Int, memory: inout [UInt8], address: Int) -> Bool {
        guard let sectorData = readSector(track: track, sectorID: sectorID) else {
            return false
        }
        
        // メモリにセクタデータをコピー
        for (i, byte) in sectorData.enumerated() {
            let memAddr = address + i
            if memAddr < memory.count {
                memory[memAddr] = byte
            }
        }
        
        return true
    }
    
    /// ディスクの詳細情報を解析して返す
    /// - Returns: ディスク情報を格納した辞書
    func analyzeDetailedInfo() -> [String: String] {
        var info: [String: String] = [:]
        
        // ディスク名
        info["diskName"] = header.diskName
        
        // 書き込み保護
        info["writeProtected"] = header.writeProtected ? "あり" : "なし"
        
        // メディアタイプ
        info["mediaType"] = header.mediaTypeString
        
        // ディスクサイズ
        info["diskSize"] = "\(header.diskSize) バイト"
        
        // トラック数
        info["trackCount"] = "\(trackCount)"
        
        // 最大セクタ数
        info["maxSectors"] = "\(maxSectors)"
        
        return info
    }
    
    /// IPL領域とOS領域を特定する
    /// - Returns: システム領域の情報を格納した辞書
    func locateSystemAreas() -> [String: Any] {
        var result: [String: Any] = [:]
        
        // IPLコードのチェック
        if let iplCode = loadIPLCode() {
            result["iplFound"] = true
            result["iplSize"] = iplCode.count
            
            // IPLの特徴的なバイトパターンをチェック
            if iplCode.count >= 10 {
                // 一般的なPC-88のIPLは特定のジャンプ命令で始まる
                let isStandardIPL = (iplCode[0] == 0xC3) // JMP命令
                result["isStandardIPL"] = isStandardIPL
            }
        } else {
            result["iplFound"] = false
        }
        
        // OS領域の探索
        // 通常、OSはトラック0の後半からトラック1にかけて格納されている
        var osData: [UInt8] = []
        
        // トラック0の後半のセクタを収集
        if let track0 = tracks[0], track0.sectors.count > 1 {
            for i in 1..<track0.sectors.count {
                osData.append(contentsOf: track0.sectors[i].data)
            }
        }
        
        // トラック1のセクタを収集
        if tracks.count > 1, let track1 = tracks[1] {
            for sector in track1.sectors {
                osData.append(contentsOf: sector.data)
            }
        }
        
        result["osDataSize"] = osData.count
        
        // OSの特定によく使われる文字列を探索
        let osSignatures: [[UInt8]] = [
            [0x50, 0x43, 0x2D, 0x38, 0x38], // "PC-88"
            [0x4E, 0x38, 0x38, 0x2D, 0x42, 0x41, 0x53, 0x49, 0x43], // "N88-BASIC"
            [0x44, 0x49, 0x53, 0x4B, 0x20, 0x42, 0x41, 0x53, 0x49, 0x43] // "DISK BASIC"
        ]
        
        var foundSignatures: [String] = []
        
        for signature in osSignatures {
            if searchForSignature(in: osData, signature: signature) {
                let sigString = String(bytes: signature, encoding: .ascii) ?? "不明"
                foundSignatures.append(sigString)
            }
        }
        
        result["osSignatures"] = foundSignatures
        
        // PMD88シグネチャの探索
        let pmdSignature: [UInt8] = [0x50, 0x4D, 0x44, 0x38, 0x38] // "PMD88"のASCIIコード
        let pmdFound = searchForSignature(in: rawData, signature: pmdSignature)
        result["pmdFound"] = pmdFound
        
        if pmdFound {
            // PMD88の典型的なメモリアドレスを設定
            result["songDataAddress"] = 0x4C00
            result["voiceDataAddress"] = 0x6000
        }
        
        return result
    }
    
    /// データ内に特定のシグネチャが存在するか探索
    /// - Parameters:
    ///   - data: 探索対象のデータ
    ///   - signature: 探索するシグネチャ
    /// - Returns: シグネチャが見つかった場合はtrue
    private func searchForSignature(in data: [UInt8], signature: [UInt8]) -> Bool {
        guard data.count >= signature.count else { return false }
        
        for i in 0...(data.count - signature.count) {
            let range = i..<(i + signature.count)
            let slice = data[range]
            
            if slice.elementsEqual(signature) {
                return true
            }
        }
        
        return false
    }
}
