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
}
