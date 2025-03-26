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
    
    // Z80 CPU
    @Published var cpu = Z80()
    
    // UI制御用
    @Published var runButtonEnabled = true
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
        }
        
        // メモリ初期化
        loadPMD2G()
        
        debug.appendLog("Z80 CPU初期化完了")
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
                let disk = D88Disk(from: data)
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
                let pmd88Files = disk.extractPMD88Files()
                
                // mcgファイルをPMD88クラスに設定
                if let mcgData = pmd88Files["mcg"] {
                    debug.appendLog("mcgファイルを抽出しました: \(mcgData.count)バイト")
                    pmd.setMCGBinaryData(mcgData)
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
    }
    
    // MARK: - システムリセット
    func resetSystem() {
        // PMDが実行中なら停止
        if pmd.isRunning() {
            pmd.stop()
        }
        
        // Z80 CPUをリセット
        cpu.reset()
        
        // PMD2Gを再ロード
        loadPMD2G()
        
        // オーディオエンジンをリセット
        audio.stopAudio()
        
        debug.appendLog("システムをリセットしました")
    }
    
    // MARK: - ポート入出力
    func portIn(port: UInt16) -> UInt8 {
        // ポート入力処理
        switch port {
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
            
        default:
            return 0
        }
    }
    
    func portOut(port: UInt16, value: UInt8) {
        // ポート出力処理
        switch port {
        case 0xA0:  // OPNAアドレスポート
            cpu.selectedOPNARegister = value
            
        case 0xA1:  // OPNAデータポート
            let registerIndex = cpu.selectedOPNARegister
            if registerIndex < cpu.opnaRegisters.count {
                cpu.opnaRegisters[Int(registerIndex)] = value
            }
            
        case 0xA2, 0xA3:  // 拡張ポート
            break
            
        default:
            break
        }
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
}
