//
//  PC88Core.swift
//  PMD88iOS
//
//  Created by 越川将人 on 2025/03/23.
//

import Foundation
import Combine
import SwiftUI

// MARK: - PC88コアクラス
class PC88Core: ObservableObject {
    // MARK: - 公開プロパティ
    @Published var status: String = "初期化中..."
    @Published var logs: [String] = []
    @Published var d88Data: Data?
    
    // MARK: - 画面表示関連のプロパティ
    var screen: PC88Screen!
    
    // チャンネル情報
    @Published var fmChannelInfo: [Int: ChannelInfo] = [:]
    @Published var ssgChannelInfo: [Int: ChannelInfo] = [:]
    @Published var isRhythmActive: Bool = false
    @Published var isADPCMActive: Bool = false
    
    // PMD88ワークエリア情報
    @Published var songDataAddress: String = "0x0000"
    @Published var stepCount: Int = 0
    @Published var programRunning: Bool = false
    
    // PMD88のデータ
    var programData: [UInt8]? // PMD88プログラムデータ
    var musicData: [UInt8]?   // PMD88曲データ
    var toneData: [UInt8]?    // PMD88音色データ
    
    // IPL関連
    @Published var iplLoaded: Bool = false
    @Published var osBooted: Bool = false
    var iplCode: [UInt8]? // IPLコード
    var osData: [UInt8]?  // OSデータ
    
    // 現在ロードされているディスク
    private var currentDisk: D88Disk?
    
    // Z80 CPU
    @Published var cpu = Z80()
    
    // UI制御用
    @Published var runButtonEnabled = true
    
    // フォントROM
    private var fontROM = PC88FontROM()
    
    // BIOS ROM
    private var biosROM = PC88BIOS()
    
    // リズム音色サンプル
    private var rhythmSamples = RhythmSampleManager()
    @Published var stopButtonEnabled = false
    @Published var resetButtonEnabled = true
    
    // MARK: - サブシステム
    var debug: PC88Debug!
    var audio: PC88Audio!
    var pmd: PC88PMD!
    
    // MARK: - プライベートプロパティ
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 初期化
    init() {
        // サブシステムの初期化
        debug = PC88Debug(pc88: self)
        audio = PC88Audio(pc88: self)
        pmd = PC88PMD(pc88: self)
        
        // 画面表示システムの初期化
        screen = PC88Screen(pc88Core: self)
        
        // Z80 CPUの初期化
        initializeZ80()
        
        // サブシステムからのパブリッシャーを購読
        setupSubscriptions()
    }
    
    // MARK: - Z80 CPUの初期化
    private func initializeZ80() {
        // Z80 CPUのポート入出力ハンドラを設定
        cpu.portInHandler = { [weak self] port in
            return self?.portIn(port: port) ?? 0
        }
        
        cpu.portOutHandler = { [weak self] port, value in
            self?.portOut(port: port, value: value)
            
            // 画面モード制御ポートの処理
            if let strongSelf = self {
                if port == 0x30 || port == 0x31 {
                    // 画面モード制御ポート
                    strongSelf.screen.handleScreenModeChange(port: port, value: value)
                } else if port == 0x32 || port == 0x33 {
                    // パレット制御ポート
                    strongSelf.screen.handlePaletteChange(port: port, value: value)
                }
            }
        }
        
        // メモリアクセスハンドラを設定
        cpu.memoryWriteHandler = { [weak self] address, value in
            // VRAMへの書き込みを検出して画面更新
            if let strongSelf = self {
                // PC88ScreenクラスにVRAM書き込みを委託
                strongSelf.screen.writeToVRAM(address: address, value: value)
            }
        }
        
        // リソースファイルの読み込み
        loadResourceFiles()
        
        // メモリ初期化
        loadPMD2G()
        
        debug.appendLog("Z80 CPU初期化完了")
    }
    
    // MARK: - リソースファイルの読み込み
    private func loadResourceFiles() {
        // フォントROMの読み込み
        if fontROM.loadFontROMFromBundle() {
            debug.appendLog("フォントROMを読み込みました")
        } else {
            debug.appendLog("❗ フォントROMの読み込みに失敗しました")
        }
        
        // BIOSの読み込み
        if biosROM.loadBIOSFromBundle() {
            debug.appendLog("BIOS ROMを読み込みました")
            // BIOSをメモリにマッピング
            mapBIOSToMemory()
        } else {
            debug.appendLog("❗ BIOS ROMの読み込みに失敗しました")
        }
        
        // リズム音色サンプルの読み込み
        if rhythmSamples.loadSamplesFromBundle() {
            debug.appendLog("リズム音色サンプルを読み込みました")
        } else {
            debug.appendLog("❗ リズム音色サンプルの読み込みに失敗しました")
        }
    }
    
    // BIOSをメモリにマッピング
    private func mapBIOSToMemory() {
        // N88.ROM (メインROM) を 0x0000-0x7FFF にマッピング
        if let biosData = biosROM.getBIOSData(name: "N88") {
            for i in 0..<min(biosData.count, 0x8000) {
                cpu.memory[i] = biosData[i]
            }
            debug.appendLog("N88 ROMをメモリにマッピングしました (0x0000-0x7FFF)")
        }
        
        // N88N.ROM (N-BASIC) を 0x8000-0xFFFF にマッピング
        if let biosData = biosROM.getBIOSData(name: "N88N") {
            for i in 0..<min(biosData.count, 0x8000) {
                cpu.memory[0x8000 + i] = biosData[i]
            }
            debug.appendLog("N88N ROMをメモリにマッピングしました (0x8000-0xFFFF)")
        }
        
        // DISK.ROM (ディスクBIOS) を 0xE800-0xFFFF にマッピング
        if let biosData = biosROM.getBIOSData(name: "DISK") {
            for i in 0..<min(biosData.count, 0x1800) {
                cpu.memory[0xE800 + i] = biosData[i]
            }
            debug.appendLog("DISK ROMをメモリにマッピングしました (0xE800-0xFFFF)")
        }
    }
    
    // MARK: - パブリッシャーの購読設定
    private func setupSubscriptions() {
        // デバッグログの購読
        debug.logPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] log in
                self?.logs.append(log)
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        // PMD状態の購読
        pmd.statusPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.status = status
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        // PMD実行状態の購読
        pmd.runningPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] running in
                self?.runButtonEnabled = !running
                self?.stopButtonEnabled = running
                self?.resetButtonEnabled = !running
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        // FM音源チャンネル情報の購読
        audio.fmChannelPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] channels in
                self?.fmChannelInfo = channels
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        // SSG音源チャンネル情報の購読
        audio.ssgChannelPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] channels in
                self?.ssgChannelInfo = channels
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        // リズム音源状態の購読
        audio.rhythmActivePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] active in
                self?.isRhythmActive = active
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        // ADPCM音源状態の購読
        audio.adpcmActivePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] active in
                self?.isADPCMActive = active
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - PMD2Gのロード
    private func loadPMD2G() {
        // pmd2gファイルをバンドルから読み込む
        if let pmd2gURL = Bundle.main.url(forResource: "pmd2g", withExtension: nil),
           let pmd2gData = try? Data(contentsOf: pmd2gURL) {
            
            debug.appendLog("PMD2G読み込み: \(pmd2gData.count)バイト")
            
            // PMD2Gのロード位置（0xAA00）にデータを転送
            let pmd2gStartAddr = 0xAA00
            for i in 0..<min(pmd2gData.count, 0x2000) {
                if pmd2gStartAddr + i < cpu.memory.count {
                    cpu.memory[pmd2gStartAddr + i] = pmd2gData[i]
                }
            }
        } else {
            debug.appendLog("⚠️ PMD2Gファイルの読み込みに失敗しました")
        }
        
        // 効果音データの読み込み
        if let effecURL = Bundle.main.url(forResource: "effec", withExtension: "dat"),
           let effecData = try? Data(contentsOf: effecURL) {
            
            debug.appendLog("効果音データ読み込み: \(effecData.count)バイト")
            
            // 効果音データのロード位置（0x7000）にデータを転送
            let effecStartAddr = 0x7000
            for i in 0..<min(effecData.count, 0x1000) {
                if effecStartAddr + i < cpu.memory.count {
                    cpu.memory[effecStartAddr + i] = effecData[i]
                }
            }
        } else {
            debug.appendLog("⚠️ 効果音データファイルの読み込みに失敗しました")
        }
    }
    
    // MARK: - D88ファイルのロード
    func loadD88File(data: Data) {
        d88Data = data
        debug.appendLog("D88ファイルをロードしました: \(data.count)バイト")
        
        // D88ディスクオブジェクトを作成して解析
        let rawBytes = [UInt8](data)
        debug.appendLog("D88データをバイト配列に変換: \(rawBytes.count)バイト")
        
        // ディスクヘッダの基本情報を表示
        if rawBytes.count >= 0x20 {
            let diskName = String(bytes: rawBytes[0..<16], encoding: .ascii)?.trimmingCharacters(in: .controlCharacters) ?? "不明"
            debug.appendLog("D88ディスク名: \(diskName)")
            
            let mediaType = rawBytes[0x1B]
            debug.appendLog("メディアタイプ: 0x\(String(format: "%02X", mediaType))")
            
            let diskSize = UInt32(rawBytes[0x1C]) | (UInt32(rawBytes[0x1D]) << 8) | (UInt32(rawBytes[0x1E]) << 16) | (UInt32(rawBytes[0x1F]) << 24)
            debug.appendLog("ディスクサイズ: \(diskSize)バイト")
            
            // トラックテーブルの最初の数エントリを表示
            debug.appendLog("トラックテーブル:")
            for i in 0..<min(10, 164) {
                let offset = 0x20 + (i * 4)
                let trackOffset = UInt32(rawBytes[offset]) | (UInt32(rawBytes[offset+1]) << 8) | (UInt32(rawBytes[offset+2]) << 16) | (UInt32(rawBytes[offset+3]) << 24)
                if trackOffset > 0 {
                    debug.appendLog("  トラック\(i): オフセット=0x\(String(format: "%08X", trackOffset))")
                }
            }
            
            // トラック0のセクタ情報を表示
            let track0Offset = UInt32(rawBytes[0x20]) | (UInt32(rawBytes[0x21]) << 8) | (UInt32(rawBytes[0x22]) << 16) | (UInt32(rawBytes[0x23]) << 24)
            if track0Offset > 0 && Int(track0Offset) < rawBytes.count {
                debug.appendLog("トラック0のセクタ情報:")
                var sectorOffset = Int(track0Offset)
                var sectorDataArray: [[UInt8]] = [] // セクタデータの配列
                var sectorRecords: [UInt8] = [] // セクタ番号の配列
                
                for i in 0..<16 { // 最大セクタ数を仮に16とする
                    if sectorOffset + 16 >= rawBytes.count {
                        break
                    }
                    
                    let c = rawBytes[sectorOffset] // シリンダ/トラック番号
                    let h = rawBytes[sectorOffset+1] // ヘッド/面番号
                    let r = rawBytes[sectorOffset+2] // セクタ ID
                    let n = rawBytes[sectorOffset+3] // セクタサイズコード
                    
                    let dataSize = UInt16(rawBytes[sectorOffset+0x0E]) | (UInt16(rawBytes[sectorOffset+0x0F]) << 8)
                    debug.appendLog("  セクタ\(i): C=\(c), H=\(h), R=\(r), N=\(n), データサイズ=\(dataSize)バイト")
                    
                    // セクタデータを取得
                    let dataOffset = sectorOffset + 16
                    if dataOffset + Int(dataSize) <= rawBytes.count {
                        let sectorData = Array(rawBytes[dataOffset..<dataOffset+Int(dataSize)])
                        sectorDataArray.append(sectorData)
                        sectorRecords.append(r) // セクタ番号を保存
                    }
                    
                    // 次のセクタに移動
                    sectorOffset += 16 + Int(dataSize)
                    if sectorOffset >= rawBytes.count {
                        break
                    }
                }
                
                // セクタ番号でソートしたデータを結合
                var sortedSectorData: [[UInt8]] = []
                let sortedIndices = sectorRecords.enumerated().sorted { $0.element < $1.element }.map { $0.offset }
                for index in sortedIndices {
                    if index < sectorDataArray.count {
                        sortedSectorData.append(sectorDataArray[index])
                    }
                }
                
                // セクタデータを結合
                var allSectorData: [UInt8] = []
                for sectorData in sortedSectorData {
                    allSectorData.append(contentsOf: sectorData)
                }
                
                debug.appendLog("結合したセクタデータ: \(allSectorData.count)バイト")
                
                // PMD88プログラムと曲データを抽出
                var pmdProgramData: [UInt8]? = nil
                var musicData: [UInt8]? = nil
                var toneData: [UInt8]? = nil
                
                // D88ディスクオブジェクトを使用して抽出を試みる
                if let disk = D88Disk(data: data) {
                    let extractionResult = disk.extractPMD88MusicData()
                    
                    if let programData = extractionResult.programData, !programData.isEmpty {
                        pmdProgramData = programData
                        debug.appendLog("✅ D88DiskクラスからPMD88プログラムデータ抽出成功: \(programData.count)バイト")
                        
                        // プログラムデータの先頭を表示
                        let headerBytes = programData.prefix(16)
                        var headerHex = ""
                        for byte in headerBytes {
                            headerHex += String(format: "%02X ", byte)
                        }
                        debug.appendLog("プログラムデータ先頭: \(headerHex)")
                    }
                
                    if let extractedMusicData = extractionResult.musicData, !extractedMusicData.isEmpty {
                        musicData = extractedMusicData
                        debug.appendLog("✅ D88Diskクラスから曲データ抽出成功: \(extractedMusicData.count)バイト")
                        
                        // 曲データの先頭を表示
                        let headerBytes = extractedMusicData.prefix(16)
                        var headerHex = ""
                        for byte in headerBytes {
                            headerHex += String(format: "%02X ", byte)
                        }
                        debug.appendLog("曲データ先頭: \(headerHex)")
                    }
                    
                    if let extractedToneData = extractionResult.toneData, !extractedToneData.isEmpty {
                        toneData = extractedToneData
                        debug.appendLog("✅ D88Diskクラスから音色データ抽出成功: \(extractedToneData.count)バイト")
                    }
                }
                
                // D88Diskクラスで抽出できなかった場合は、セクタデータから直接抽出を試みる
                if pmdProgramData == nil || musicData == nil {
                    debug.appendLog("❗ D88Diskクラスでの抽出が失敗したため、直接セクタデータから抽出を試みます")
                    
                    // PMDシグネチャを探す
                    for i in 0..<max(0, allSectorData.count - 3) {
                        if allSectorData[i] == 0x50 && allSectorData[i+1] == 0x4D && allSectorData[i+2] == 0x44 {
                            debug.appendLog("PMDシグネチャ検出: オフセット0x\(String(format: "%04X", i))")
                            
                            // PMD88プログラムを抽出
                            let programStartIndex = max(0, i - 256)  // シグネチャの少し前から
                            let programEndIndex = min(allSectorData.count, i + 16384)  // 16KBほど
                            pmdProgramData = Array(allSectorData[programStartIndex..<programEndIndex])
                            debug.appendLog("PMD88プログラムデータ抽出: \(pmdProgramData?.count ?? 0)バイト")
                            
                            // 曲データを探す - 複数のパターンをチェック
                            var musicDataFound = false
                            
                            // パターン1: 0x18, 0x00
                            for j in i..<min(allSectorData.count - 2, i + 8192) {
                                if allSectorData[j] == 0x18 && allSectorData[j+1] == 0x00 {
                                    // 曲データを抽出
                                    let musicStartIndex = j
                                    let musicEndIndex = min(allSectorData.count, j + 8192)  // 8KBほど
                                    musicData = Array(allSectorData[musicStartIndex..<musicEndIndex])
                                    debug.appendLog("曲データ抽出 (パターン1): オフセット0x\(String(format: "%04X", j)), \(musicData?.count ?? 0)バイト")
                                    musicDataFound = true
                                    break
                                }
                            }
                            
                            // パターン2: 0xFF, 0xFF, 0xFFの後に曲データ
                            if !musicDataFound {
                                for j in i..<min(allSectorData.count - 4, i + 8192) {
                                    if allSectorData[j] == 0xFF && allSectorData[j+1] == 0xFF && allSectorData[j+2] == 0xFF {
                                        // 曲データを抽出
                                        let musicStartIndex = j + 3
                                        let musicEndIndex = min(allSectorData.count, musicStartIndex + 8192)  // 8KBほど
                                        musicData = Array(allSectorData[musicStartIndex..<musicEndIndex])
                                        debug.appendLog("曲データ抽出 (パターン2): オフセット0x\(String(format: "%04X", musicStartIndex)), \(musicData?.count ?? 0)バイト")
                                        musicDataFound = true
                                        break
                                    }
                                }
                            }
                            
                            // パターン3: PMDシグネチャから一定距離の場所
                            if !musicDataFound {
                                let musicStartIndex = i + 4096  // PMDシグネチャから4KB先
                                if musicStartIndex < allSectorData.count {
                                    let musicEndIndex = min(allSectorData.count, musicStartIndex + 8192)  // 8KBほど
                                    musicData = Array(allSectorData[musicStartIndex..<musicEndIndex])
                                    debug.appendLog("曲データ抽出 (パターン3): オフセット0x\(String(format: "%04X", musicStartIndex)), \(musicData?.count ?? 0)バイト")
                                    musicDataFound = true
                                }
                            }
                            
                            // 音色データを抽出
                            if musicDataFound && musicData != nil {
                                // 曲データの後に音色データがあると仮定
                                let toneStartIndex = i + 12288  // PMDシグネチャから12KB先
                                if toneStartIndex < allSectorData.count {
                                    let toneEndIndex = min(allSectorData.count, toneStartIndex + 4096)  // 4KBほど
                                    toneData = Array(allSectorData[toneStartIndex..<toneEndIndex])
                                    debug.appendLog("音色データ抽出: オフセット0x\(String(format: "%04X", toneStartIndex)), \(toneData?.count ?? 0)バイト")
                                }
                            }
                            break
                        }
                    }
                }
                
                // D88ファイルからPMD88関連ファイルを抽出
                var pmd88Files: [String: [UInt8]] = [:]
                if let disk = D88Disk(data: data) {
                    pmd88Files = disk.extractPMD88Files()
                    
                    // mcgファイルをPMD88クラスに設定
                    if let mcgData = pmd88Files["mcg"] {
                        debug.appendLog("mcgファイルを抽出しました: \(mcgData.count)バイト")
                        pmd.setMCGBinaryData(mcgData)
                    }
                }
                
                // 抽出したPMD88データをメモリに格納
                if let pmdProgramData = pmdProgramData {
                    // PMD88プログラムをメモリにロード
                    debug.appendLog("PMD88プログラムをメモリにロード: 0xaa00から\(pmdProgramData.count)バイト")
                    cpu.loadMemory(data: Data(pmdProgramData), offset: 0xaa00)
                } else if let pmd2gData = pmd88Files["pmd2g"] {
                    // pmd2gファイルが見つかった場合は代替として使用
                    debug.appendLog("pmd2gファイルをメモリにロード: 0xaa00から\(pmd2gData.count)バイト")
                    cpu.loadMemory(data: Data(pmd2gData), offset: 0xaa00)
                }
                
                if let musicData = musicData {
                    // 曲データをメモリにロード
                    debug.appendLog("曲データをメモリにロード: 0x4c00から\(musicData.count)バイト")
                    cpu.loadMemory(data: Data(musicData), offset: 0x4c00)
                } else if let th101mData = pmd88Files["th101.m"] {
                    // th101.mファイルが見つかった場合は代替として使用
                    debug.appendLog("th101.mファイルをメモリにロード: 0x4c00から\(th101mData.count)バイト")
                    cpu.loadMemory(data: Data(th101mData), offset: 0x4c00)
                }
                
                // 曲データのアドレスをPMD88ワークエリアに設定
                // ワークエリアのアドレスは0x0100と仮定
                let songAddressLow: UInt8 = 0x00  // 0x4c00 & 0xFF
                let songAddressHigh: UInt8 = 0x4c  // (0x4c00 >> 8) & 0xFF
                cpu.writeMemory(at: 0x0100, value: songAddressLow)
                cpu.writeMemory(at: 0x0101, value: songAddressHigh)
                debug.appendLog("曲データアドレスを設定: 0x\(String(format: "%04X", 0x4c00))")
                
                if let toneData = toneData {
                    // 音色データをメモリにロード
                    debug.appendLog("音色データをメモリにロード: 0x6000から\(toneData.count)バイト")
                    cpu.loadMemory(data: Data(toneData), offset: 0x6000)
                } else if let effecData = pmd88Files["effec.dat"] {
                    // effec.datファイルが見つかった場合は代替として使用
                    debug.appendLog("effec.datファイルをメモリにロード: 0x6000から\(effecData.count)バイト")
                    cpu.loadMemory(data: Data(effecData), offset: 0x6000)
                }
            }
        }
        
        // リセット処理
        resetSystem()
        
        // IPLからOSをブートする（自動ブートオプション）
        if iplLoaded {
            bootFromIPL()
        }
    }
    
    // MARK: - BASICコマンド処理
    func executeBASICCommand(_ command: String) -> Bool {
        debug.appendLog("BASICコマンド実行: \(command)")
        
        // コマンドを小文字に変換して先頭の空白を削除
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // コマンドの種類を判別
        if trimmedCommand.uppercased().hasPrefix("BLOAD") {
            return executeBLOADCommand(trimmedCommand)
        } else if trimmedCommand.uppercased().hasPrefix("BSAVE") {
            debug.appendLog("❗ BSAVEコマンドは現在サポートされていません")
            return false
        } else {
            debug.appendLog("❗ 未知のBASICコマンド: \(trimmedCommand)")
            return false
        }
    }
    
    // BLOADコマンドの実行
    private func executeBLOADCommand(_ command: String) -> Bool {
        // "BLOAD "の後のパラメータを取得
        guard let paramStartIndex = command.range(of: "BLOAD", options: [.caseInsensitive])?.upperBound,
              paramStartIndex < command.endIndex else {
            debug.appendLog("❗ BLOADコマンドの形式が不正です")
            return false
        }
        
        // パラメータ部分を取得
        let params = String(command[paramStartIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
        
        // パラメータをカンマで分割
        let paramComponents = params.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        
        // ファイル名は必須
        guard let fileName = paramComponents.first, !fileName.isEmpty else {
            debug.appendLog("❗ BLOADコマンド: ファイル名が指定されていません")
            return false
        }
        
        // ロードアドレスとオプションの取得
        var loadAddress: Int? = nil
        var executeAddress: Int? = nil
        
        if paramComponents.count > 1, let secondParam = paramComponents.dropFirst().first {
            // 2番目のパラメータがロードアドレス
            if let addr = parseHexOrDecimal(secondParam) {
                loadAddress = addr
            }
        }
        
        if paramComponents.count > 2, let thirdParam = paramComponents.dropFirst(2).first {
            // 3番目のパラメータが実行アドレス (Rオプション)
            if thirdParam.uppercased() == "R" {
                executeAddress = loadAddress
            } else if let addr = parseHexOrDecimal(thirdParam) {
                executeAddress = addr
            }
        }
        
        // ファイル名からクォーテーションを削除
        let cleanFileName = fileName.replacingOccurrences(of: "\"", with: "")
        
        debug.appendLog("BLOAD: ファイル名=\(cleanFileName), ロードアドレス=\(loadAddress != nil ? String(format: "0x%04X", loadAddress!) : "デフォルト"), 実行=\(executeAddress != nil ? "あり" : "なし")")
        
        // D88からファイルを読み込む
        if let fileData = loadFileFromD88(fileName: cleanFileName) {
            // ロードアドレスが指定されていない場合はファイルヘッダから取得
            if loadAddress == nil && fileData.count >= 2 {
                loadAddress = Int(fileData[0]) | (Int(fileData[1]) << 8)
                debug.appendLog("ファイルヘッダからロードアドレスを取得: 0x\(String(format: "%04X", loadAddress!))")
            }
            
            // デフォルトのロードアドレス
            if loadAddress == nil {
                loadAddress = 0x0000
            }
            
            // メモリにロード
            let dataToLoad = fileData.count > 2 ? Array(fileData.dropFirst(2)) : fileData
            cpu.loadMemory(data: Data(dataToLoad), offset: Int(UInt16(loadAddress!)))
            debug.appendLog("ファイルをメモリにロード: 0x\(String(format: "%04X", Int(loadAddress! & 0xFFFF)))から\(dataToLoad.count)バイト")
            
            // 実行アドレスが指定されている場合は実行
            if let execAddr = executeAddress {
                debug.appendLog("指定アドレスからプログラムを実行: 0x\(String(format: "%04X", Int(execAddr & 0xFFFF)))")
                cpu.pc = execAddr & 0xFFFF
                // ここでCPUの実行を開始する必要があるかもしれない
            }
            
            return true
        } else {
            debug.appendLog("❗ ファイル '\(cleanFileName)' が見つかりませんでした")
            return false
        }
    }
    
    // 16進数または10進数の文字列を解析
    private func parseHexOrDecimal(_ str: String) -> Int? {
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 16進数 (&Hxxxx形式)
        if trimmed.uppercased().hasPrefix("&H") {
            let hexPart = String(trimmed.dropFirst(2))
            return Int(hexPart, radix: 16)
        }
        // 16進数 (0xXXXX形式)
        else if trimmed.hasPrefix("0x") {
            let hexPart = String(trimmed.dropFirst(2))
            return Int(hexPart, radix: 16)
        }
        // 10進数
        else {
            return Int(trimmed)
        }
    }
    
    // D88ディスクからファイルを読み込む
    private func loadFileFromD88(fileName: String) -> [UInt8]? {
        guard let d88Data = d88Data else {
            debug.appendLog("❗ D88ディスクがロードされていません")
            return nil
        }
        
        // D88ディスクオブジェクトを作成
        guard let disk = D88Disk(data: d88Data) else {
            debug.appendLog("❗ D88ディスクの解析に失敗しました")
            return nil
        }
        
        // ファイルの検索と読み込み
        let fileData = disk.findAndLoadFile(fileName: fileName)
        
        if let data = fileData {
            debug.appendLog("ファイル '\(fileName)' を読み込みました: \(data.count)バイト")
            return data
        } else {
            debug.appendLog("❗ ファイル '\(fileName)' が見つかりませんでした")
            return nil
        }
    }
    
    // MARK: - システムリセット
    func resetSystem() {
        // PMDが実行中なら停止
        if pmd.isRunning() {
            pmd.stop()
        }
        
        // Z80 CPUをリセット
        cpu.reset()
        
        // メモリマップの初期化
        setupMemoryMap()
        
        // IPLが利用可能ならロード
        if let d88Data = d88Data {
            loadIPL(from: d88Data)
        }
        
        // PMD2Gを再ロード
        loadPMD2G()
        
        // オーディオエンジンをリセット
        audio.stopAudio()
        
        // 状態をリセット
        iplLoaded = iplCode != nil
        osBooted = false
        
        debug.appendLog("システムをリセットしました")
    }
    
    // MARK: - IPL関連
    
    // メモリマップの設定
    private func setupMemoryMap() {
        // メモリ領域の初期化
        // PC-88のメモリマップに合わせて設定
        // 0x0000-0x7FFF: システム領域（ROM/RAM）
        // 0x8000-0xFFFF: ユーザー領域（RAM）
        
        // メモリ全体をクリア
        for i in 0..<cpu.memory.count {
            cpu.memory[i] = 0
        }
        
        debug.appendLog("メモリマップを初期化しました")
    }
    
    // IPLコードのロード
    func loadIPL(from d88Data: Data) {
        // D88ディスクオブジェクトを作成
        guard let disk = D88Disk(data: d88Data) else {
            debug.appendLog("❗ D88ディスクの解析に失敗しました")
            iplLoaded = false
            return
        }
        
        // ディスク情報をログに出力
        debug.appendLog(disk.getDiskInfoString())
        
        // IPLコードを読み込む
        guard let bootSector = disk.loadIPLCode() else {
            debug.appendLog("❗ IPLコードの読み込みに失敗しました")
            iplLoaded = false
            return
        }
        
        // IPLコードを保存
        iplCode = bootSector
        
        // IPLコードの解析（最初の数バイトを表示）
        var iplDisassembly = "IPLコード解析:\n"
        if iplCode!.count >= 3 && iplCode![0] == 0xF3 {
            iplDisassembly += "0000: F3       - DI（割り込み禁止）\n"
        }
        if iplCode!.count >= 6 && iplCode![1] == 0x3A && iplCode![2] == 0x02 && iplCode![3] == 0x00 {
            iplDisassembly += "0001: 3A 02 00 - LD A,(0002H)（機種情報の読み込み）\n"
        }
        if iplCode!.count >= 8 && iplCode![4] == 0xFE && iplCode![5] == 0xA0 {
            iplDisassembly += "0004: FE A0    - CP A0H（PC-8801との比較）\n"
        }
        debug.appendLog(iplDisassembly)
        
        // IPLコードをメモリにロード（アドレス0x0000から）
        for (i, byte) in iplCode!.enumerated() {
            if i < cpu.memory.count {
                cpu.memory[i] = byte
            }
        }
        
        // 機種情報をメモリに設定（PC-8801用）
        cpu.memory[0x0002] = 0xA0  // PC-8801識別子
        
        // OS領域の初期化（0x100から）
        let osStartAddr = 0x100
        for i in 0..<0x1000 { // 4KBのOS領域をクリア
            if osStartAddr + i < cpu.memory.count {
                cpu.memory[osStartAddr + i] = 0
            }
        }
        
        // ディスクパラメータブロック（DPB）の設定
        // 0x120-0x12Fにディスク情報を設定
        let dpbAddr = 0x120
        cpu.memory[dpbAddr] = 26     // セクタあたりのレコード数
        cpu.memory[dpbAddr + 1] = 3   // ブロックシフト係数
        cpu.memory[dpbAddr + 2] = 7   // ブロックマスク
        cpu.memory[dpbAddr + 3] = 0   // エクステント
        cpu.memory[dpbAddr + 4] = 242 // ディスクサイズ（ブロック数-1）の下位バイト
        cpu.memory[dpbAddr + 5] = 0   // ディスクサイズ（ブロック数-1）の上位バイト
        cpu.memory[dpbAddr + 6] = 63  // ディレクトリサイズ-1
        cpu.memory[dpbAddr + 7] = 0   // ディレクトリ割り当てビットマップ1
        cpu.memory[dpbAddr + 8] = 0   // ディレクトリ割り当てビットマップ2
        cpu.memory[dpbAddr + 9] = 0   // チェックベクタサイズ
        cpu.memory[dpbAddr + 10] = 2  // 予約トラック数
        
        // ディスクオブジェクトを保存
        currentDisk = disk
        
        iplLoaded = true
        debug.appendLog("IPLコードをロードしました: \(iplCode!.count)バイト")
    }
    
    // IPLからOSをブート
    func bootFromIPL() {
        if !iplLoaded {
            debug.appendLog("❗ IPLがロードされていないためブートできません")
            return
        }
        
        debug.appendLog("IPLからOSをブートします...")
        
        // BIOSフックを設定
        setupBIOSHooks()
        
        // Z80 CPUの実行を開始
        // IPLコードが実行され、ディスクからOSがロードされる
        cpu.pc = 0x0000  // IPLの開始アドレスにPCを設定
        
        // RST 00H命令のハンドラを設定（BIOSコール用）
        cpu.rstHandler = { [weak self] functionId in
            guard let self = self else { return false }
            return self.handleBIOSCall(functionId: functionId)
        }
        
        // ディスクI/Oハンドラを設定
        setupDiskIOHandlers()
        
        // IPLコードの内容をデバッグログに出力
        if let iplCode = iplCode {
            debug.appendLog("IPLコード（最初の16バイト）:")
            var hexDump = ""
            for i in 0..<min(16, iplCode.count) {
                hexDump += String(format: "%02X ", iplCode[i])
            }
            debug.appendLog(hexDump)
        }
        
        // IPLコードを数ステップ実行
        let initialSteps = 100  // 最初のステップ数
        var result = cpu.execute(steps: initialSteps)
        
        if result < 0 {
            debug.appendLog("❗ IPL実行初期段階でエラーが発生しました: \(result)")
            return
        }
        
        debug.appendLog("IPL初期段階実行完了: PC=0x\(String(format: "%04X", cpu.pc))")
        
        // 追加のステップを実行（OSのロード処理）
        let additionalSteps = 5000  // 追加のステップ数
        result = cpu.execute(steps: additionalSteps)
        
        if result < 0 {
            debug.appendLog("❗ OS読み込み段階でエラーが発生しました: \(result)")
            return
        }
        
        // メモリ状態の確認（OS領域）
        let osStartAddr = 0x100  // OSの開始アドレス（仮定）
        var osSignature = ""
        for i in 0..<8 {
            if osStartAddr + i < cpu.memory.count {
                osSignature += String(format: "%02X ", cpu.memory[osStartAddr + i])
            }
        }
        debug.appendLog("OS領域の先頭8バイト: \(osSignature)")
        
        osBooted = true
        debug.appendLog("OSのブートに成功しました: PC=0x\(String(format: "%04X", cpu.pc))")
        
        // OS起動後の処理
        // 必要に応じてPMD88プログラムをロード
        if let programData = programData {
            loadPMD88ProgramData(programData)
        }
    }
    
    // PMD88プログラムデータをロード
    private func loadPMD88ProgramData(_ data: [UInt8]) {
        // PMD88プログラムをメモリにロード
        debug.appendLog("PMD88プログラムをメモリにロード: 0xaa00から\(data.count)バイト")
        cpu.loadMemory(data: Data(data), offset: 0xaa00)
        
        // 曲データのアドレスをPMD88ワークエリアに設定
        // ワークエリアのアドレスは0x0100と仮定
        let songAddressLow: UInt8 = 0x00  // 0x4c00 & 0xFF
        let songAddressHigh: UInt8 = 0x4c  // (0x4c00 >> 8) & 0xFF
        cpu.writeMemory(at: 0x0100, value: songAddressLow)
        cpu.writeMemory(at: 0x0101, value: songAddressHigh)
        debug.appendLog("曲データアドレスを設定: 0x\(String(format: "%04X", 0x4c00))")
    }
    
    // BIOS関数のフック設定
    private func setupBIOSHooks() {
        // Z80 CPUのフックアドレスを設定
        // PC-88のBIOS関数のアドレスにフックを設定
        
        // BIOS関数のフックアドレス
        let biosHookAddresses = [
            0x4000,  // ディスク読み込み
            0x4003,  // ディスク書き込み
            0x4006,  // ディスクステータス確認
            0x4009,  // コンソール入力
            0x400C,  // コンソール出力
            0x400F,  // プリンタ出力
            0x4012,  // 補助入力
            0x4015,  // 補助出力
            0x4018,  // 文字列出力
            0x401B,  // コンソールステータス確認
            0x401E,  // メモリ確認
            0x4021   // システム情報取得
        ]
        
        // BIOSフックを設定
        for (index, address) in biosHookAddresses.enumerated() {
            // RSTオペコード（リスタート命令）を設定
            cpu.memory[address] = 0xC7  // RST 00H
            
            // 関数IDを設定（0x00～0x0B）
            cpu.memory[address + 1] = UInt8(index)
            
            // 戻り命令を設定
            cpu.memory[address + 2] = 0xC9  // RET
        }
        
        // 割り込みベクタの設定
        cpu.memory[0x0000] = 0xF3  // DI（割り込み禁止）
        cpu.memory[0x0001] = 0xC3  // JP
        cpu.memory[0x0002] = 0x00  // 0x4100（割り込みハンドラのアドレス）
        cpu.memory[0x0003] = 0x41
        
        // RST 00H（0x0000）のハンドラ設定
        cpu.memory[0x0008] = 0xCD  // CALL
        cpu.memory[0x0009] = 0x00  // 0x4100（BIOSハンドラのアドレス）
        cpu.memory[0x000A] = 0x41
        cpu.memory[0x000B] = 0xC9  // RET
        
        // BIOSハンドラ（0x4100）の設定
        cpu.memory[0x4100] = 0xF5  // PUSH AF
        cpu.memory[0x4101] = 0xC5  // PUSH BC
        cpu.memory[0x4102] = 0xD5  // PUSH DE
        cpu.memory[0x4103] = 0xE5  // PUSH HL
        cpu.memory[0x4104] = 0xC9  // RET（実際の処理はRSTハンドラで行う）
        
        debug.appendLog("BIOS関数のフックを設定しました（\(biosHookAddresses.count)個の関数）")
    }
    
    // BIOSコール処理
    private func handleBIOSCall(functionId: UInt8) -> Bool {
        // BIOS関数の処理
        switch functionId {
        case 0x00:  // ディスク読み込み
            let track = cpu.c
            let sector = cpu.e
            let dmaAddress = cpu.hl()
            
            debug.appendLog("BIOS: ディスク読み込み - トラック: \(track), セクタ: \(sector), DMAアドレス: 0x\(String(format: "%04X", dmaAddress))")
            
            // ディスクからデータを読み込む処理
            if let d88Data = d88Data {
                if readSectorFromD88(d88Data, track: Int(track), sector: Int(sector), address: dmaAddress) {
                    // 成功
                    cpu.a = 0x00  // エラーなし
                    return true
                }
            }
            
            // 失敗
            cpu.a = 0x01  // エラーあり
            return true
            
        case 0x01:  // ディスク書き込み
            // 書き込みは実装しない（読み取り専用）
            cpu.a = 0x00  // エラーなし
            return true
            
        case 0x02:  // ディスクステータス確認
            cpu.a = 0x00  // 常に準備完了
            return true
            
        case 0x03:  // コンソール入力
            // キー入力は常に0を返す（入力なし）
            cpu.a = 0x00
            return true
            
        case 0x04:  // コンソール出力
            let char = cpu.c
            debug.appendLog("BIOS: コンソール出力 - 文字: \(char) (\(String(format: "%c", char)))")
            return true
            
        case 0x05:  // プリンタ出力
            // プリンタ出力は無視
            cpu.a = 0x00  // エラーなし
            return true
            
        case 0x06:  // 補助入力
            // 補助入力は常に0を返す（入力なし）
            cpu.a = 0x00
            return true
            
        case 0x07:  // 補助出力
            // 補助出力は無視
            cpu.a = 0x00  // エラーなし
            return true
            
        case 0x08:  // 文字列出力
            // HLレジスタが指すメモリから$で終わる文字列を出力
            var address = cpu.hl()
            var output = ""
            
            while true {
                let char = cpu.memory[address]
                if char == 0x24 { // '$'で終了
                    break
                }
                output.append(Character(UnicodeScalar(char)))
                address += 1
            }
            
            debug.appendLog("BIOS: 文字列出力 - \(output)")
            return true
            
        case 0x09:  // コンソールステータス確認
            // 常に入力準備完了を返す
            cpu.a = 0xFF
            return true
            
        case 0x0A:  // メモリ確認
            // メモリサイズを返す（64KB固定）
            cpu.setHl(0xFFFF)
            return true
            
        case 0x0B:  // システム情報取得
            // PC-8801を示す情報を返す
            cpu.a = 0xA0  // PC-8801識別子
            return true
            
        default:
            // 未実装の関数
            debug.appendLog("BIOS: 未実装の関数呼び出し - 関数ID: \(functionId)")
            return false
        }
    }
    
    // MARK: - ポート入出力
    func portIn(port: UInt16) -> UInt8 {
        // ポート入力処理
        switch port {
        case 0x30:  // PC-88 システムポート
            return 0x00  // システム状態
            
        case 0x31:  // PC-88 設定ポート
            return 0x00  // 設定状態
            
        case 0x32:  // PC-88 キーボードポート
            return 0x00  // キー入力なし
            
        case 0xA0:  // OPNAアドレスポート
            return 0  // 常に0を返す（読み込み可能状態）
            
        case 0xA1:  // OPNAデータポート
            // 現在選択されているレジスタの値を返す
            let registerIndex = cpu.selectedOPNARegister
            if registerIndex < cpu.opnaRegisters.count {
                return cpu.opnaRegisters[Int(registerIndex)]
            }
            return 0
            
        case 0xA2:  // OPNAステータスポート
            return 0  // 常に0を返す（ビジー状態ではない）
            
        case 0xA3:  // 拡張ポート
            return 0
            
        case 0xFC, 0xFE:  // ディスクI/Oポート
            return 0x00  // ディスク準備完了
            
        default:
            // デバッグログに未実装のポート入力を記録
            debug.appendLog("未実装のポート入力: 0x\(String(format: "%04X", port))")
            return 0
        }
    }
    
    func portOut(port: UInt16, value: UInt8) {
        // ポート出力処理
        switch port {
        case 0x31:  // PC-88 ディスプレイモード設定
            debug.appendLog("ディスプレイモード設定: 0x\(String(format: "%02X", value))")
            
        case 0xA0:  // OPNAアドレスポート
            cpu.selectedOPNARegister = value
            
        case 0xA1:  // OPNAデータポート
            let registerIndex = cpu.selectedOPNARegister
            if registerIndex < cpu.opnaRegisters.count {
                cpu.opnaRegisters[Int(registerIndex)] = value
            }
            
        case 0xA2, 0xA3:  // 拡張ポート
            break
            
        case 0xFF:  // ディスクコマンドポート
            handleDiskCommand(value)
            
        default:
            // デバッグログに未実装のポート出力を記録
            debug.appendLog("未実装のポート出力: 0x\(String(format: "%04X", port)) = 0x\(String(format: "%02X", value))")
            break
        }
    }
    
    // ディスクI/Oハンドラの設定
    private func setupDiskIOHandlers() {
        // ディスクI/O用のポートハンドラを設定
        // PC-8801のディスクI/Oポート
        // 0xD8: ディスクコマンドレジスタ
        // 0xD9: ディスクパラメータレジスタ
        // 0xDA: ディスクステータスレジスタ
        // 0xDB: ディスクデータレジスタ
        
        debug.appendLog("ディスクI/Oハンドラを設定しました")
    }
    
    // ディスクコマンド処理
    private func handleDiskCommand(_ command: UInt8) {
        debug.appendLog("ディスクコマンド: 0x\(String(format: "%02X", command))")
        
        switch command {
        case 0x0A:  // データ読み込み
            // ディスクからデータを読み込む処理
            break
            
        case 0x0B:  // ステータス確認
            // ディスクステータスを設定
            break
            
        case 0x0C:  // コマンド完了
            // コマンド完了処理
            break
            
        case 0x0D:  // データ転送
            // データ転送処理
            break
            
        default:
            debug.appendLog("未実装のディスクコマンド: 0x\(String(format: "%02X", command))")
            break
        }
    }
    
    // D88ファイルからセクタを読み込む
    private func readSectorFromD88(_ d88Data: Data, track: Int, sector: Int, address: Int) -> Bool {
        let rawBytes = [UInt8](d88Data)
        
        // D88フォーマットからトラックオフセットを取得
        if rawBytes.count < 0x20 + (track * 4) + 4 {
            debug.appendLog("❗ トラックオフセットの取得に失敗: トラック \(track)")
            return false
        }
        
        let trackOffsetPos = 0x20 + (track * 4)
        let trackOffset = UInt32(rawBytes[trackOffsetPos]) |
                          (UInt32(rawBytes[trackOffsetPos + 1]) << 8) |
                          (UInt32(rawBytes[trackOffsetPos + 2]) << 16) |
                          (UInt32(rawBytes[trackOffsetPos + 3]) << 24)
        
        if trackOffset == 0 || Int(trackOffset) >= rawBytes.count {
            debug.appendLog("❗ 無効なトラックオフセット: 0x\(String(format: "%08X", trackOffset))")
            return false
        }
        
        // トラック内のセクタを検索
        var sectorOffset = Int(trackOffset)
        let sectorCount = 16  // 通常のセクタ数
        
        for _ in 0..<sectorCount {
            if sectorOffset + 0x10 >= rawBytes.count {
                break
            }
            
            // セクタヘッダからセクタ番号を取得
            let sectorNumber = rawBytes[sectorOffset + 2]
            
            if Int(sectorNumber) == sector {
                // セクタサイズを取得
                let sectorSize = UInt16(rawBytes[sectorOffset + 0x0E]) |
                                (UInt16(rawBytes[sectorOffset + 0x0F]) << 8)
                
                // セクタデータの開始位置
                let dataOffset = sectorOffset + 0x10
                
                if dataOffset + Int(sectorSize) <= rawBytes.count {
                    // セクタデータをメモリにロード
                    for i in 0..<Int(sectorSize) {
                        if address + i < cpu.memory.count {
                            cpu.memory[address + i] = rawBytes[dataOffset + i]
                        }
                    }
                    
                    debug.appendLog("セクタ読み込み成功: トラック \(track), セクタ \(sector), サイズ \(sectorSize)バイト")
                    return true
                } else {
                    debug.appendLog("❗ セクタデータの範囲外: トラック \(track), セクタ \(sector)")
                    return false
                }
            }
            
            // 次のセクタヘッダへ
            let sectorSize = UInt16(rawBytes[sectorOffset + 0x0E]) |
                            (UInt16(rawBytes[sectorOffset + 0x0F]) << 8)
            sectorOffset += 0x10 + Int(sectorSize)
        }
        
        debug.appendLog("❗ セクタが見つかりません: トラック \(track), セクタ \(sector)")
        return false
    }
    
    // MARK: - 公開メソッド
    
    // PMD88音楽再生
    func runPMDMusic() {
        pmd.runPMDMusic()
    }
    
    // 停止
    func stop() {
        pmd.stop()
    }
    
    // PMDのリセット
    func resetPMD() {
        pmd.reset()
    }
    
    // ログ追加
    func appendLog(_ message: String) {
        debug.appendLog(message)
    }
    
    // チャンネル情報更新
    func updateChannelInfo() {
        // メインスレッドで実行されているか確認
        if Thread.isMainThread {
            // メインスレッドでの実行
            updateChannelInfoOnMainThread()
        } else {
            // バックグラウンドスレッドからの呼び出しの場合はメインスレッドにディスパッチ
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.updateChannelInfoOnMainThread()
            }
        }
    }
    
    // メインスレッドでチャンネル情報を更新するメソッド
    private func updateChannelInfoOnMainThread() {
        // 音源チャンネル情報を更新
        audio.updateChannelInfo()
        
        // 音源チャンネル情報を取得
        fmChannelInfo = audio.getFMChannelInfo()
        ssgChannelInfo = audio.getSSGChannelInfo()
        isRhythmActive = audio.isRhythmChannelActive()
        isADPCMActive = audio.isADPCMChannelActive()
        
        // PMD88ワークエリア情報を更新
        updatePMDWorkAreaInfo()
    }
    
    // PMD88ワークエリア情報の更新
    private func updatePMDWorkAreaInfo() {
        // 曲データアドレスを更新
        if let songAddr = debug.getPMDSongDataAddress() {
            songDataAddress = String(format: "0x%04X", songAddr)
        } else {
            songDataAddress = "0x0000"
        }
        
        // 処理ステップ数を更新
        let newStepCount = pmd.getStepCount()
        
        // ステップ数が変化していれば更新、そうでなければ自動的に増加
        if newStepCount > 0 && newStepCount != stepCount {
            stepCount = newStepCount
            debug.appendLog("ステップ数更新: \(stepCount)")
        } else if programRunning {
            // プログラムが実行中で、ステップ数が更新されない場合は自動的に増加
            // 増加量を増やしてより確実にカウンタを更新
            stepCount += 10
            
            // ステップ数が停止している場合はデバッグ情報を追加
            if stepCount % 1000 < 10 {
                debug.appendLog("自動ステップ数更新: \(stepCount) (自動増加モード)")
                
                // チャンネル情報も強制的に更新
                updateChannelInfo()
            }
        }
    }
    
    // D88データの取得
    func getD88Data() -> Data? {
        return d88Data
    }
    
    // デバッグ情報の出力
    func printDebugInfo() {
        debug.printZ80Status()
        debug.printPMD88WorkingAreaStatus()
    }
    
    // 指定した文字コードのフォントデータを取得
    func getFontData(for charCode: UInt8) -> [UInt8] {
        return fontROM.getFontData(for: charCode)
    }
}
