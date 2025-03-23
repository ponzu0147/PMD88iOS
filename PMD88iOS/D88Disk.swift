import Foundation

// D88ディスクイメージフォーマット
// 参考: https://www.pc98.org/project/doc/d88.html

import Foundation

// MARK: - D88ディスクイメージ関連の定数
enum D88Constants {
    // ディスクヘッダ関連
    static let headerSize = 688                // ディスクヘッダサイズ (0x2B0)
    static let diskNameOffset = 0              // ディスク名オフセット
    static let diskNameSize = 16               // ディスク名サイズ
    static let writeProtectFlagOffset = 0x1A   // 書き込み保護フラグオフセット
    static let mediaFlagOffset = 0x1B          // メディアフラグオフセット
    static let diskSizeOffset = 0x1C           // ディスクサイズオフセット
    static let trackTableOffset = 0x20         // トラックテーブルオフセット
    static let maxTracks = 164                 // 最大トラック数
    
    // メディアフラグ
    static let media2D = 0x00                  // 2D (PC-88標準)
    static let media2DD = 0x10                 // 2DD
    static let media2HD = 0x20                 // 2HD
    static let media1D = 0x30                  // 1D
    static let media1DD = 0x40                 // 1DD
    
    // セクタヘッダ関連
    static let sectorHeaderSize = 16           // セクタヘッダサイズ
    static let cylinderOffset = 0              // C (シリンダ/トラック番号)
    static let headOffset = 1                  // H (ヘッド/面番号)
    static let recordOffset = 2                // R (セクタID)
    static let sectorSizeCodeOffset = 3        // N (セクタサイズコード)
    static let sectorsInTrackOffset = 4        // トラック内のセクタ数
    static let densityFlagOffset = 6           // 密度フラグ
    static let deletedDataFlagOffset = 7       // 削除データフラグ
    static let statusCodeOffset = 8            // FDCステータスコード
    static let dataSizeOffset = 0x0E           // 実際のデータサイズ
    
    // 密度フラグ
    static let doubleDensity = 0x00            // 倍密度
    static let singleDensity = 0x40            // 単密度
    
    // PC-88標準フォーマット (2D)
    static let standardSectorsPerTrack = 16    // 1トラックあたりのセクタ数
    static let standardSectorSize = 256        // 標準セクタサイズ
    static let standardSectorSizeCode = 1      // N=1 (256バイト)
}

// MARK: - D88セクタ構造体
struct D88Sector {
    let cylinder: UInt8                // C (シリンダ/トラック番号)
    let head: UInt8                    // H (ヘッド/面番号)
    let record: UInt8                  // R (セクタID)
    let sizeCode: UInt8                // N (セクタサイズコード)
    let sectorsInTrack: UInt16         // トラック内のセクタ数
    let densityFlag: UInt8             // 密度フラグ
    let deletedDataFlag: UInt8         // 削除データフラグ
    let statusCode: UInt8              // FDCステータスコード
    let dataSize: UInt16               // 実際のデータサイズ
    let data: [UInt8]                  // セクタデータ
    
    // セクタサイズを計算 (128 << N)
    var sectorSize: Int {
        return 128 << Int(sizeCode)
    }
    
    // セクタの総サイズ (ヘッダ + データ)
    var totalSize: Int {
        return D88Constants.sectorHeaderSize + data.count
    }
    
    // セクタの文字列表現
    var description: String {
        return "C=\(cylinder) H=\(head) R=\(record) N=\(sizeCode) Size=\(dataSize)bytes"
    }
}

// MARK: - D88トラック構造体
struct D88Track {
    let trackNumber: Int               // トラック番号
    let offset: UInt32                 // ディスク先頭からのオフセット
    var sectors: [D88Sector] = []      // セクタのリスト
    
    // トラックの総サイズ
    var size: Int {
        return sectors.reduce(0) { $0 + $1.totalSize }
    }
    
    // トラックの文字列表現
    var description: String {
        return "Track \(trackNumber): \(sectors.count) sectors, offset=0x\(String(format: "%08X", offset))"
    }
}

// MARK: - D88ディスク構造体
struct D88Disk {
    let data: [UInt8]                  // ディスクイメージの生データ
    var diskName: String = ""          // ディスク名
    var mediaFlag: UInt8 = 0           // メディアフラグ
    var diskSize: UInt32 = 0           // ディスクサイズ
    var writeProtected: Bool = false   // 書き込み保護フラグ
    var tracks: [D88Track] = []        // トラックのリスト
    
    // 初期化
    init(from fileData: Data) {
        self.data = [UInt8](fileData)
        parseHeader()
        parseTracks()
    }
    
    // ディスクヘッダの解析
    private mutating func parseHeader() {
        guard data.count >= D88Constants.headerSize else {
            print("⚠️ D88ファイルが小さすぎます")
            return
        }
        
        // ディスク名の取得
        let nameData = data[D88Constants.diskNameOffset..<D88Constants.diskNameOffset + D88Constants.diskNameSize]
        if let name = String(bytes: nameData, encoding: .ascii) {
            // NULL文字で終わる文字列を取得
            if let nullTerminator = name.firstIndex(of: "\0") {
                diskName = String(name[..<nullTerminator])
            } else {
                diskName = name
            }
        }
        
        // 書き込み保護フラグの取得
        writeProtected = data[D88Constants.writeProtectFlagOffset] != 0
        
        // メディアフラグの取得
        mediaFlag = data[D88Constants.mediaFlagOffset]
        
        // ディスクサイズの取得 (リトルエンディアン)
        diskSize = UInt32(data[D88Constants.diskSizeOffset]) |
                  (UInt32(data[D88Constants.diskSizeOffset + 1]) << 8) |
                  (UInt32(data[D88Constants.diskSizeOffset + 2]) << 16) |
                  (UInt32(data[D88Constants.diskSizeOffset + 3]) << 24)
    }
    
    // トラックの解析
    private mutating func parseTracks() {
        // トラックテーブルの解析
        for i in 0..<D88Constants.maxTracks {
            let trackTableIndex = D88Constants.trackTableOffset + (i * 4)
            let trackOffset = UInt32(data[trackTableIndex]) |
                             (UInt32(data[trackTableIndex + 1]) << 8) |
                             (UInt32(data[trackTableIndex + 2]) << 16) |
                             (UInt32(data[trackTableIndex + 3]) << 24)
            
            // オフセットが0の場合はトラックが存在しない
            if trackOffset == 0 || trackOffset >= UInt32(data.count) {
                continue
            }
            
            // トラックオブジェクトを作成
            var track = D88Track(trackNumber: i, offset: trackOffset)
            
            // トラック内のセクタを解析
            var currentOffset = Int(trackOffset)
            while currentOffset + D88Constants.sectorHeaderSize <= data.count {
                // セクタヘッダの解析
                let cylinder = data[currentOffset + D88Constants.cylinderOffset]
                let head = data[currentOffset + D88Constants.headOffset]
                let record = data[currentOffset + D88Constants.recordOffset]
                let sizeCode = data[currentOffset + D88Constants.sectorSizeCodeOffset]
                
                let sectorsInTrack = UInt16(data[currentOffset + D88Constants.sectorsInTrackOffset]) |
                                    (UInt16(data[currentOffset + D88Constants.sectorsInTrackOffset + 1]) << 8)
                
                let densityFlag = data[currentOffset + D88Constants.densityFlagOffset]
                let deletedDataFlag = data[currentOffset + D88Constants.deletedDataFlagOffset]
                let statusCode = data[currentOffset + D88Constants.statusCodeOffset]
                
                let dataSize = UInt16(data[currentOffset + D88Constants.dataSizeOffset]) |
                              (UInt16(data[currentOffset + D88Constants.dataSizeOffset + 1]) << 8)
                
                // セクタデータの取得
                let sectorDataOffset = currentOffset + D88Constants.sectorHeaderSize
                let sectorData: [UInt8]
                
                if sectorDataOffset + Int(dataSize) <= data.count {
                    sectorData = Array(data[sectorDataOffset..<sectorDataOffset + Int(dataSize)])
                } else {
                    // データサイズが不正な場合は残りのデータを全て取得
                    sectorData = Array(data[sectorDataOffset..<data.count])
                }
                
                // セクタオブジェクトを作成
                let sector = D88Sector(
                    cylinder: cylinder,
                    head: head,
                    record: record,
                    sizeCode: sizeCode,
                    sectorsInTrack: sectorsInTrack,
                    densityFlag: densityFlag,
                    deletedDataFlag: deletedDataFlag,
                    statusCode: statusCode,
                    dataSize: dataSize,
                    data: sectorData
                )
                
                // トラックにセクタを追加
                track.sectors.append(sector)
                
                // 次のセクタへ
                currentOffset = sectorDataOffset + sectorData.count
                
                // トラックの終端に達した場合は終了
                if currentOffset >= data.count || dataSize == 0 {
                    break
                }
            }
            
            // トラックを追加
            tracks.append(track)
        }
    }
    
    // 指定されたトラック番号とセクタIDからセクタを取得
    func getSector(track: Int, sector: Int) -> D88Sector? {
        guard track < tracks.count else { return nil }
        
        let trackObj = tracks[track]
        return trackObj.sectors.first { $0.record == UInt8(sector) }
    }
    
    // 指定されたオフセットから指定サイズのデータを抽出
    func extractFile(at offset: Int, size: Int) -> [UInt8] {
        return Array(data[offset..<min(offset + size, data.count)])
    }
    
    // PMD88の曲データを探して抽出
    func extractPMD88MusicData() -> (programData: [UInt8]?, musicData: [UInt8]?, toneData: [UInt8]?) {
        // PMD88プログラムと曲データを探す
        // 通常、PMD88プログラムはトラック0のセクタ1～4に配置されている
        var programData: [UInt8]? = nil
        var musicData: [UInt8]? = nil
        var toneData: [UInt8]? = nil
        
        // 全トラックを調査するように拡張
        for trackIndex in 0..<min(2, tracks.count) { // 最初の2トラックを調査
            let track = tracks[trackIndex]
            
            // セクタをセクタ番号でソートして連結
            let sortedSectors = track.sectors.sorted(by: { $0.record < $1.record })
            var allSectorData: [UInt8] = []
            
            // セクタデータをデバッグ出力
            print("トラック\(trackIndex) のセクタ数: \(sortedSectors.count)")
            for (index, sector) in sortedSectors.enumerated() {
                print("  セクタ\(index): C=\(sector.cylinder), H=\(sector.head), R=\(sector.record), データサイズ=\(sector.data.count)バイト")
                allSectorData.append(contentsOf: sector.data)
            }
            
            print("トラック\(trackIndex) の全セクタデータサイズ: \(allSectorData.count)バイト")
            
            // PMD88プログラムの特徴を探す
            var foundPMD = false
            var pmdSignatureOffset = 0
            
            // PMDシグネチャを探す
            for i in 0..<max(0, allSectorData.count - 3) {
                // "PMD"という文字列を探す
                if allSectorData[i] == 0x50 && allSectorData[i+1] == 0x4D && allSectorData[i+2] == 0x44 {
                    foundPMD = true
                    pmdSignatureOffset = i
                    print("PMDシグネチャ検出: トラック\(trackIndex), オフセット0x\(String(format: "%04X", i))")
                    break
                }
            }
            
            if foundPMD {
                // PMD88プログラムを抽出 - シグネチャの前からより多くのデータを含める
                let programStartIndex = max(0, pmdSignatureOffset - 512)  // シグネチャの512バイト前から
                let programEndIndex = min(allSectorData.count, pmdSignatureOffset + 16384)  // 16KBほど
                programData = Array(allSectorData[programStartIndex..<programEndIndex])
                print("PMD88プログラムデータ抽出: \(programData?.count ?? 0)バイト")
                
                // プログラムデータの先頭をデバッグ出力
                if let programData = programData, programData.count >= 16 {
                    var headerHex = ""
                    for i in 0..<16 {
                        headerHex += String(format: "%02X ", programData[i])
                    }
                    print("プログラムデータ先頭: \(headerHex)")
                }
                
                // 曲データを探す - 複数のパターンを試す
                var foundMusicData = false
                var musicStartOffset = 0
                
                // パターン1: 0x18, 0x00 シーケンス
                for j in pmdSignatureOffset..<min(allSectorData.count - 2, pmdSignatureOffset + 8192) {
                    if allSectorData[j] == 0x18 && allSectorData[j+1] == 0x00 {
                        // 曲データを抽出
                        musicStartOffset = j
                        let musicEndIndex = min(allSectorData.count, j + 8192)  // 8KBほど
                        musicData = Array(allSectorData[musicStartOffset..<musicEndIndex])
                        print("曲データ抽出 (パターン1): オフセット0x\(String(format: "%04X", j)), \(musicData?.count ?? 0)バイト")
                        foundMusicData = true
                        break
                    }
                }
                
                // パターン2: 0xFF, 0xFF, 0xFF シーケンス
                if !foundMusicData {
                    for j in pmdSignatureOffset..<min(allSectorData.count - 4, pmdSignatureOffset + 8192) {
                        if allSectorData[j] == 0xFF && allSectorData[j+1] == 0xFF && allSectorData[j+2] == 0xFF {
                            // 曲データを抽出 (シーケンスの直後から)
                            musicStartOffset = j + 3
                            let musicEndIndex = min(allSectorData.count, musicStartOffset + 8192)  // 8KBほど
                            musicData = Array(allSectorData[musicStartOffset..<musicEndIndex])
                            print("曲データ抽出 (パターン2): オフセット0x\(String(format: "%04X", musicStartOffset)), \(musicData?.count ?? 0)バイト")
                            foundMusicData = true
                            break
                        }
                    }
                }
                
                // パターン3: 0x00, 0x01, 0x00, 0x01 シーケンス (音色データの特徴)
                if !foundMusicData {
                    for j in pmdSignatureOffset..<min(allSectorData.count - 4, pmdSignatureOffset + 12288) {
                        if allSectorData[j] == 0x00 && allSectorData[j+1] == 0x01 && 
                           allSectorData[j+2] == 0x00 && allSectorData[j+3] == 0x01 {
                            // 音色データを発見した場合、その前を曲データと仮定
                            let toneStartOffset = j
                            // 音色データの前に曲データがあると仮定
                            musicStartOffset = max(pmdSignatureOffset, toneStartOffset - 4096)  // 音色データの4KB前
                            let musicEndIndex = toneStartOffset
                            if musicEndIndex > musicStartOffset {
                                musicData = Array(allSectorData[musicStartOffset..<musicEndIndex])
                                print("曲データ抽出 (パターン3): オフセット0x\(String(format: "%04X", musicStartOffset)), \(musicData?.count ?? 0)バイト")
                                
                                // 音色データも抽出
                                let toneEndIndex = min(allSectorData.count, toneStartOffset + 4096)  // 4KBほど
                                toneData = Array(allSectorData[toneStartOffset..<toneEndIndex])
                                print("音色データ抽出: オフセット0x\(String(format: "%04X", toneStartOffset)), \(toneData?.count ?? 0)バイト")
                                foundMusicData = true
                                break
                            }
                        }
                    }
                }
                
                // パターン4: PMDシグネチャの後、一定オフセットにある可能性
                if !foundMusicData {
                    // PMDシグネチャから4KB後を曲データと仮定
                    musicStartOffset = min(allSectorData.count - 1, pmdSignatureOffset + 4096)
                    let musicEndIndex = min(allSectorData.count, musicStartOffset + 8192)  // 8KBほど
                    if musicEndIndex > musicStartOffset {
                        musicData = Array(allSectorData[musicStartOffset..<musicEndIndex])
                        print("曲データ抽出 (パターン4): オフセット0x\(String(format: "%04X", musicStartOffset)), \(musicData?.count ?? 0)バイト")
                        foundMusicData = true
                    }
                }
                
                // 曲データが見つかった場合、音色データも抽出する
                if foundMusicData && musicData != nil && toneData == nil {
                    // 音色データの抽出方法を1: 曲データの後に音色データがある場合
                    let toneStartOffset = min(allSectorData.count - 1, musicStartOffset + 4096)  // 曲データの4KB後
                    let toneEndIndex = min(allSectorData.count, toneStartOffset + 4096)  // 4KBほど
                    if toneEndIndex > toneStartOffset {
                        toneData = Array(allSectorData[toneStartOffset..<toneEndIndex])
                        print("音色データ抽出 (曲データ後): オフセット0x\(String(format: "%04X", toneStartOffset)), \(toneData?.count ?? 0)バイト")
                    }
                    
                    // 抽出したデータの先頭をデバッグ出力
                    if let musicData = musicData, musicData.count >= 16 {
                        var headerHex = ""
                        for i in 0..<16 {
                            headerHex += String(format: "%02X ", musicData[i])
                        }
                        print("曲データ先頭: \(headerHex)")
                    }
                    
                    if let toneData = toneData, toneData.count >= 16 {
                        var headerHex = ""
                        for i in 0..<16 {
                            headerHex += String(format: "%02X ", toneData[i])
                        }
                        print("音色データ先頭: \(headerHex)")
                    }
                }
                
                // データが見つかった場合は処理終了
                if programData != nil && musicData != nil {
                    break
                }
            }
        }
        
        // PMDシグネチャが見つからない場合、別の方法で探す
        if programData == nil && !tracks.isEmpty {
            let track = tracks[0] // トラック0を使用
            let sortedSectors = track.sectors.sorted(by: { $0.record < $1.record })
            
            // トラック0の最初のセクタをプログラムデータと仮定
            if !sortedSectors.isEmpty {
                programData = sortedSectors[0].data
                
                // 2番目以降のセクタを曲データと仮定
                if sortedSectors.count > 1 {
                    var combinedMusicData: [UInt8] = []
                    for i in 1..<min(4, sortedSectors.count) {
                        combinedMusicData.append(contentsOf: sortedSectors[i].data)
                    }
                    musicData = combinedMusicData
                    
                    // 残りのセクタを音色データと仮定
                    if sortedSectors.count > 4 {
                        var combinedToneData: [UInt8] = []
                        for i in 4..<sortedSectors.count {
                            combinedToneData.append(contentsOf: sortedSectors[i].data)
                        }
                        toneData = combinedToneData
                    }
                }
            }
        }
        
        return (programData, musicData, toneData)
    }
    
    // D88ファイルから特定のファイルを抽出する
    // 戻り値: [ファイル名: データ] の辞書
    func extractPMD88Files() -> [String: [UInt8]] {
        print("\n===== D88ファイルからPMD88ファイルの抽出開始 =====\n")
        var files: [String: [UInt8]] = [:]
        _ = ["pmd2g", "mcg", "effec.dat", "th101.m"]
        
        // トラック数を確認
        print("D88ディスクのトラック数: \(tracks.count)")
        if tracks.isEmpty {
            print("トラックが見つかりません")
            return files
        }
        
        // 全トラックのセクタデータを連結
        var allSectorData: [UInt8] = []
        for (i, track) in tracks.enumerated() {
            let sortedSectors = track.sectors.sorted(by: { $0.record < $1.record })
            print("\(i): \(sortedSectors.count)セクタ")
            for sector in sortedSectors {
                allSectorData.append(contentsOf: sector.data)
            }
        }
        
        print("全トラックのデータサイズ: \(allSectorData.count)バイト")
        
        // ファイル名のバイトパターンを作成
        let patterns: [(name: String, pattern: [UInt8], expectedSize: Int)] = [
            ("pmd2g", [0x70, 0x6D, 0x64, 0x32, 0x67], 4096), // "pmd2g" - プログラムデータ、約4KB
            ("mcg", [0x6D, 0x63, 0x67], 2048), // "mcg" - MCGバイナリ、約2KB
            ("effec.dat", [0x65, 0x66, 0x66, 0x65, 0x63, 0x2E, 0x64, 0x61, 0x74], 1024), // "effec.dat" - 効果音データ、約1KB
            ("th101.m", [0x74, 0x68, 0x31, 0x30, 0x31, 0x2E, 0x6D], 4096) // "th101.m" - 音楽データ、約4KB
        ]
        
        print("ファイル名パターン検索開始 - 全データサイズ: \(allSectorData.count)バイト")
        
        // バイナリデータの特徴をチェック
        let signatures: [(offset: Int, pattern: [UInt8], description: String)] = [
            (0, [0x43, 0x50, 0x4D], "CP/Mファイルヘッダ"),
            (0, [0x1F, 0x8B], "gzip圧縮ファイル"),
            (0, [0xC3], "Z80ジャンプ命令"),
            (0, [0xF3], "Z80 DI命令"),
            (0, [0x00, 0x01, 0x00, 0x01], "音色データパターン")
        ]
        
        // 全データの先頭をチェック
        if allSectorData.count >= 16 {
            var headerHex = ""
            for i in 0..<16 {
                headerHex += String(format: "%02X ", allSectorData[i])
            }
            print("全データの先頭16バイト: \(headerHex)")
            
            // 特徴パターンをチェック
            for (offset, pattern, description) in signatures {
                if allSectorData.count > offset + pattern.count {
                    var match = true
                    for i in 0..<pattern.count {
                        if allSectorData[offset + i] != pattern[i] {
                            match = false
                            break
                        }
                    }
                    if match {
                        print("データ特徴検出: \(description)")
                    }
                }
            }
        }
        
        // 各パターンを検索
        for (name, pattern, expectedSize) in patterns {
            for i in 0..<(allSectorData.count - pattern.count) {
                var found = true
                for j in 0..<pattern.count {
                    if allSectorData[i + j] != pattern[j] {
                        found = false
                        break
                    }
                }
                
                if found {
                    // ファイル名の後にデータが続くと仮定
                    let dataStartOffset = i + pattern.count + 1 // ファイル名 + 区切り文字の次
                    let dataEndOffset = min(dataStartOffset + expectedSize, allSectorData.count) // 予想サイズを抽出
                    
                    if dataEndOffset > dataStartOffset {
                        let fileData = Array(allSectorData[dataStartOffset..<dataEndOffset])
                        files[name] = fileData
                        print("\(name)ファイルを抽出: \(fileData.count)バイト (位置: \(dataStartOffset)-\(dataEndOffset))")
                        
                        // データの先頭を表示
                        if fileData.count >= 16 {
                            var headerHex = ""
                            for j in 0..<16 {
                                headerHex += String(format: "%02X ", fileData[j])
                            }
                            print("\(name)データ先頭: \(headerHex)")
                            
                            // MCGファイルの場合、特徴を確認
                            if name == "mcg" {
                                // MCGファイルの特徴的なバイトパターンを確認
                                let mcgSignatures = [
                                    ([0xC3], "Z80ジャンプ命令"),
                                    ([0xF3], "Z80 DI命令"),
                                    ([0x21], "Z80 LD HL命令")
                                ]
                                
                                for (sig, desc) in mcgSignatures {
                                    if fileData.count > sig.count && fileData[0] == sig[0] {
                                        print("MCGファイルの特徴検出: \(desc)")
                                    }
                                }
                            }
                        }
                    }
                    
                    break
                }
            }
        }
        
        print("パターン検索結果: \(files.count)個のファイルが見つかりました")
        
        // ファイルが見つからない場合、別の方法で探す
        if files.isEmpty && !tracks.isEmpty {
            print("パターン検索でファイルが見つからなかったため、セクタ単位で抽出します")
            // トラックとセクタの構造を詳細に分析
            print("トラック構造の詳細分析:")
            
            // 各トラックのセクタ数とデータサイズを確認
            var totalSectors = 0
            var largestTrackIndex = 0
            var largestSectorCount = 0
            
            for (i, track) in tracks.enumerated() {
                let sortedSectors = track.sectors.sorted(by: { $0.record < $1.record })
                let trackDataSize = sortedSectors.reduce(0) { $0 + $1.data.count }
                print("  トラック\(i): \(sortedSectors.count)セクタ, 合計\(trackDataSize)バイト")
                
                totalSectors += sortedSectors.count
                
                if sortedSectors.count > largestSectorCount {
                    largestSectorCount = sortedSectors.count
                    largestTrackIndex = i
                }
            }
            
            print("全トラック合計: \(totalSectors)セクタ")
            print("最もセクタ数が多いトラック: \(largestTrackIndex) (\(largestSectorCount)セクタ)")
            
            // トラック0の最初のセクタをpmd2gと仮定
            let track = tracks[0]
            let sortedSectors = track.sectors.sorted(by: { $0.record < $1.record })
            print("トラック0のセクタ数: \(sortedSectors.count)")
            
            if sortedSectors.count >= 1 {
                files["pmd2g"] = sortedSectors[0].data
                print("pmd2gファイルを抽出（推定）: \(sortedSectors[0].data.count)バイト")
                
                // データの先頭を表示
                if sortedSectors[0].data.count >= 16 {
                    var headerHex = ""
                    for i in 0..<16 {
                        headerHex += String(format: "%02X ", sortedSectors[0].data[i])
                    }
                    print("pmd2gデータ先頭: \(headerHex)")
                }
            }
            
            // 2番目のセクタをmcgと仮定
            if sortedSectors.count >= 2 {
                files["mcg"] = sortedSectors[1].data
                print("mcgファイルを抽出（推定）: \(sortedSectors[1].data.count)バイト")
                
                // データの先頭を表示
                if sortedSectors[1].data.count >= 16 {
                    var headerHex = ""
                    for i in 0..<16 {
                        headerHex += String(format: "%02X ", sortedSectors[1].data[i])
                    }
                    print("mcgデータ先頭: \(headerHex)")
                }
            }
            
            // 3番目のセクタをeffec.datと仮定
            if sortedSectors.count >= 3 {
                files["effec.dat"] = sortedSectors[2].data
                print("effec.datファイルを抽出（推定）: \(sortedSectors[2].data.count)バイト")
            }
            
            // 4番目のセクタをth101.mと仮定
            if sortedSectors.count >= 4 {
                files["th101.m"] = sortedSectors[3].data
                print("th101.mファイルを抽出（推定）: \(sortedSectors[3].data.count)バイト")
            }
        }
        
        print("\n===== PMD88ファイル抽出結果 =====\n")
        for (name, data) in files {
            print("\(name): \(data.count)バイト")
            
            // ファイルの特性を分析
            if data.count >= 16 {
                var headerHex = ""
                for i in 0..<16 {
                    headerHex += String(format: "%02X ", data[i])
                }
                print("  先頭16バイト: \(headerHex)")
                
                // ファイル種別に応じた特徴分析
                switch name {
                case "pmd2g":
                    // プログラムファイルの特徴を確認
                    if data[0] == 0xC3 { // Z80のジャンプ命令
                        let jumpAddress = UInt16(data[2]) << 8 | UInt16(data[1])
                        print("  PMD2G: ジャンプ命令検出 - アドレス 0x\(String(format: "%04X", jumpAddress))")
                    }
                case "mcg":
                    // MCGバイナリの特徴を確認
                    if data[0] == 0xC3 || data[0] == 0xF3 {
                        print("  MCG: Z80命令検出 - \(data[0] == 0xC3 ? "ジャンプ命令" : "DI命令")")
                    }
                case "effec.dat":
                    // 効果音データの特徴を確認
                    print("  EFFEC.DAT: 効果音データ")
                case "th101.m":
                    // 音楽データの特徴を確認
                    print("  TH101.M: 音楽データ")
                default:
                    break
                }
            }
        }
        
        if files.isEmpty {
            print("ファイルが一つも抽出されませんでした")
        }
        
        return files
    }
    
    // デバッグ情報を文字列として出力
    func getDebugInfo() -> String {
        var debugInfo = "===== D88ディスク情報 =====\n"
        debugInfo += diskInfo
        
        debugInfo += "\n===== トラック情報 =====\n"
        for (index, track) in tracks.enumerated() {
            debugInfo += "トラック\(index): \(track.sectors.count)セクタ, オフセット=0x\(String(format: "%08X", track.offset))\n"
            
            // 最初の数トラックのセクタ情報を詳細表示
            if index < 2 {
                for (sectorIndex, sector) in track.sectors.enumerated() {
                    debugInfo += "  セクタ\(sectorIndex): \(sector.description), データサイズ=\(sector.data.count)バイト\n"
                }
            }
        }
        
        debugInfo += "\n===== PMD88データ抽出 =====\n"
        let (programData, musicData, toneData) = extractPMD88MusicData()
        
        // PMD88関連ファイルの抽出
        debugInfo += "\n===== PMD88ファイル抽出 =====\n"
        let files = extractPMD88Files()
        for (name, data) in files {
            debugInfo += "\(name): \(data.count)バイト\n"
        }
        
        if let programData = programData {
            debugInfo += "PMD88プログラムデータ: \(programData.count)バイト\n"
            // PMDシグネチャの検索
            for i in 0..<max(0, programData.count - 3) {
                if programData[i] == 0x50 && programData[i+1] == 0x4D && programData[i+2] == 0x44 {
                    debugInfo += "PMDシグネチャ検出: オフセット0x\(String(format: "%04X", i))\n"
                    break
                }
            }
        } else {
            debugInfo += "PMD88プログラムデータが見つかりませんでした\n"
        }
        
        if let musicData = musicData {
            debugInfo += "曲データ: \(musicData.count)バイト\n"
            // 曲データの先頭バイトを表示
            let headerBytes = musicData.prefix(16)
            debugInfo += "曲データヘッダ: \(headerBytes.map { String(format: "%02X", $0) }.joined(separator: " "))\n"
        } else {
            debugInfo += "曲データが見つかりませんでした\n"
        }
        
        if let toneData = toneData {
            debugInfo += "音色データ: \(toneData.count)バイト\n"
        } else {
            debugInfo += "音色データが見つかりませんでした\n"
        }
        
        return debugInfo
    }
    
    // ディスク情報の文字列表現
    var diskInfo: String {
        var info = "ディスク名: \(diskName)\n"
        info += "メディアタイプ: \(mediaTypeString)\n"
        info += "ディスクサイズ: \(diskSize)バイト\n"
        info += "書き込み保護: \(writeProtected ? "あり" : "なし")\n"
        info += "トラック数: \(tracks.count)\n"
        
        return info
    }
    
    // メディアタイプの文字列表現
    var mediaTypeString: String {
        switch mediaFlag {
        case UInt8(D88Constants.media2D):
            return "2D"
        case UInt8(D88Constants.media2DD):
            return "2DD"
        case UInt8(D88Constants.media2HD):
            return "2HD"
        case UInt8(D88Constants.media1D):
            return "1D"
        case UInt8(D88Constants.media1DD):
            return "1DD"
        default:
            return "不明 (0x\(String(format: "%02X", mediaFlag)))"
        }
    }
}
