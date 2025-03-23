//
//  PC88.swift
//  PMD88iOS
//
//  Created by 越川将人 on 2025/03/21.
//

@_exported import struct Foundation.Data

import SwiftUI
import Foundation
import AVFoundation
import Combine

class PC88: ObservableObject {
    // MARK: - 公開プロパティ
    @Published var status: String = "初期化中..."
    @Published var logs: [String] = []
    @Published var d88Data: Data?
    
    // チャンネル情報
    @Published var fmChannelInfo: [Int: ChannelInfo] = [:]
    @Published var ssgChannelInfo: [Int: ChannelInfo] = [:]
    @Published var isRhythmActive: Bool = false
    @Published var isADPCMActive: Bool = false
    
    // 実行制御フラグ（UIからアクセス可能に）
    public var shouldStop = false
    
    // Z80クラスを明示的にインポート
    
    @Published var cpu = Z80()
    @Published var programRunning = false
    @Published var lastLog = ""
    @Published var audioEngine: AudioEngine?
    
    // MARK: - チャンネル情報の構造体
    struct ChannelInfo {
        var isActive: Bool = false
        var playingAddress: Int = 0
        var toneNumber: Int = 0
        var volume: Int = 0
        
        // 表示用の追加情報
        var type: String = ""
        var number: Int = 0
        var address: Int = 0
        var note: String = "---"
        var instrument: Int = 0
        var isPlaying: Bool = false
    }
    
    // 各チャンネルの情報
    @Published var fmChannels: [ChannelInfo] = []
    @Published var ssgChannels: [ChannelInfo] = []
    @Published var rhythmChannels: [ChannelInfo] = []
    @Published var adpcmChannel: ChannelInfo?
    @Published var lastDebugLog = ""
    @Published var stepCount = 0
    @Published var lastError = ""
    @Published var runButtonEnabled = true
    @Published var stopButtonEnabled = false
    @Published var resetButtonEnabled = true
    
    // PMD88ワークエリアモニター用のプロパティ
    @Published var fm1AddressHexValue = "0x0000"      // 演奏中のアドレス
    @Published var fm1AddressDecimalValue = 0
    @Published var fm1AddressChanged = false
    private var previousFm1Value: UInt16 = 0
    private var previousFm1Fnum: UInt16 = 0
    private var previousFm1Volume: Int = 0
    private var previousSongDataAddr: UInt16 = 0
    private var previousKeyOnRegValue: UInt8 = 0
    
    // FM1チャンネルの追加情報
    @Published var fm1FnumValue = "0x0000"          // BLOCK/FNUM値
    @Published var fm1Volume = 0                     // 音量
    @Published var fm1Length = 0                     // 残りの長さ
    @Published var fm1PartLoop = "0x0000"           // 演奏終了時の戻り先
    @Published var fm1NoteName = "---"               // 音名
    @Published var fm1Instrument = 0                 // 音色番号
    
    // キーオン状態の詳細情報
    @Published var isFM1KeyOn = false               // FM1チャンネルがキーオンされているか
    @Published var activeSlots = ""                  // アクティブなスロット
    
    // 追加モニタリング情報
    @Published var fm1BlockValue = 0                 // FM1のブロック値（オクターブ）
    @Published var fm1FnumRawValue = 0               // FM1の周波数値（生値）
    @Published var songDataAddress = "0x0000"        // 曲データの先頭アドレス
    @Published var keyOnRegisterValue = "0x00"       // キーオンレジスタの値
    @Published var isChannelActive = false           // チャンネルがアクティブかどうか
    
    // 実行開始・停止フラグ
    private var lastPortOutTime = 0
    private var lastPortCheckTime = 0
    
    init() {
        // 音声エンジンの初期化
        setupAudio()
    }
    
    // 音声エンジンのセットアップ
    private func setupAudio() {
        do {
            // オーディオセッションを設定
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            try session.setActive(true)
            
            // Z80がリセットされていることを確認
            if cpu.opnaRegisters.count < 16 {
                appendLog("⚠️ Z80のopnaRegisters配列サイズが不足: \(cpu.opnaRegisters.count)")
                // Z80をリセットして配列を再初期化
                cpu.reset()
            }
            
            // AudioEngineを初期化
            audioEngine = AudioEngine(z80: cpu)
            
            if audioEngine != nil {
                appendLog("✅ オーディオエンジン初期化成功")
            } else {
                appendLog("❌ オーディオエンジン初期化失敗")
            }
        } catch {
            appendLog("❌ オーディオセッション設定エラー: \(error.localizedDescription)")
        }
    }
    
    // ログ追加関数
    func appendLog(_ message: String) {
        let timestamp = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timeString = formatter.string(from: timestamp)
        
        let logMessage = "[\(timeString)] \(message)"
        print(logMessage)
        
        DispatchQueue.main.async {
            self.lastLog += logMessage + "\n"
            // ログの行数を制限
            let lines = self.lastLog.components(separatedBy: "\n")
            if lines.count > 1000 {
                self.lastLog = lines.suffix(500).joined(separator: "\n") + "\n"
            }
            
            // 最後のログメッセージを更新
            self.lastDebugLog = message
        }
    }
    
    // ポート出力関数
    func portOut(port: UInt16, value: UInt8) {
        // ポート出力処理
        let portValue = UInt8(port & 0xFF)
        cpu.ports[portValue] = value
        cpu.portWriteOrder.append((port: portValue, value: value))
        cpu.outPortCounter += 1
        
        // 現在時刻を記録
        lastPortOutTime = Int(Date().timeIntervalSince1970 * 1000)
    }
    
    // チャンネル情報を更新するメソッド
    func updateChannelInfo() {
        // FM音源チャンネル情報の更新（FM1〜FM6）
        for i in 0..<6 {
            let baseAddr = 0xBD61 + (i * 0x30) // チャンネルごとのオフセット
            
            // アドレスが有効範囲内かチェック
            if baseAddr < cpu.memory.count - 2 {
                let addrL = UInt16(cpu.memory[baseAddr])
                let addrH = UInt16(cpu.memory[baseAddr + 1])
                let address = (addrH << 8) | addrL
                
                // 音量情報
                let volumeOffset = 0xC // 実際のオフセットに合わせて調整
                let volume = baseAddr + volumeOffset < cpu.memory.count ? Int(cpu.memory[baseAddr + volumeOffset]) : 0
                
                // 音色情報
                let toneOffset = 0xE // 実際のオフセットに合わせて調整
                let tone = baseAddr + toneOffset < cpu.memory.count ? Int(cpu.memory[baseAddr + toneOffset]) : 0
                
                // 実行中フラグ（非ゼロアドレスなら演奏中と判断）
                let isActive = address != 0
                
                // 情報を更新
                DispatchQueue.main.async {
                    self.fmChannelInfo[i] = ChannelInfo(
                        isActive: isActive,
                        playingAddress: Int(address),
                        toneNumber: tone,
                        volume: volume,
                        type: "FM",
                        number: i + 1,
                        address: Int(address),
                        note: "---",
                        instrument: tone,
                        isPlaying: isActive
                    )
                }
            }
        }
        
        // SSG音源チャンネル情報の更新（SSG1〜SSG3）
        for i in 0..<3 {
            let baseAddr = 0xBF61 + (i * 0x30) // チャンネルごとのオフセット
            
            // アドレスが有効範囲内かチェック
            if baseAddr < cpu.memory.count - 2 {
                let addrL = UInt16(cpu.memory[baseAddr])
                let addrH = UInt16(cpu.memory[baseAddr + 1])
                let address = (addrH << 8) | addrL
                
                // 音量情報
                let volumeOffset = 0xC // SSGの音量オフセット
                let volume = baseAddr + volumeOffset < cpu.memory.count ? Int(cpu.memory[baseAddr + volumeOffset]) : 0
                
                // 音色情報
                let toneOffset = 0xE // SSGの音色オフセット
                let tone = baseAddr + toneOffset < cpu.memory.count ? Int(cpu.memory[baseAddr + toneOffset]) : 0
                
                // 実行中フラグ
                let isActive = address != 0
                
                // 情報を更新
                DispatchQueue.main.async {
                    self.ssgChannelInfo[i] = ChannelInfo(
                        isActive: isActive,
                        playingAddress: Int(address),
                        toneNumber: tone,
                        volume: volume,
                        type: "SSG",
                        number: i + 1,
                        address: Int(address),
                        note: "---",
                        instrument: tone,
                        isPlaying: isActive
                    )
                }
            }
        }
        
        // リズム音源の状態取得（0xB500付近）
        let rhythmAddr = 0xB500
        if rhythmAddr < cpu.memory.count {
            let rhythmStatus = cpu.memory[rhythmAddr]
            DispatchQueue.main.async {
                self.isRhythmActive = rhythmStatus != 0
            }
        }
        
        // ADPCM音源の状態取得（0xB600付近）
        let adpcmAddr = 0xB600
        if adpcmAddr < cpu.memory.count {
            let adpcmStatus = cpu.memory[adpcmAddr]
            DispatchQueue.main.async {
                self.isADPCMActive = adpcmStatus != 0
            }
        }
        
        // 従来のChannelInfo配列も更新（互換性のため）
        updateLegacyChannelArrays()
    }
    
    // 従来形式のチャンネル配列を更新（既存コードとの互換性のため）
    private func updateLegacyChannelArrays() {
        // FM音源チャンネル情報
        var updatedFmChannels: [ChannelInfo] = []
        for i in 0..<6 {
            if let info = fmChannelInfo[i] {
                updatedFmChannels.append(info)
            } else {
                // データがない場合はダミーを追加
                updatedFmChannels.append(ChannelInfo(
                    type: "FM",
                    number: i + 1,
                    address: 0,
                    note: "---",
                    instrument: 0,
                    isPlaying: false
                ))
            }
        }
        
        // SSG音源チャンネル情報
        var updatedSsgChannels: [ChannelInfo] = []
        for i in 0..<3 {
            if let info = ssgChannelInfo[i] {
                updatedSsgChannels.append(info)
            } else {
                // データがない場合はダミーを追加
                updatedSsgChannels.append(ChannelInfo(
                    type: "SSG",
                    number: i + 1,
                    address: 0,
                    note: "---",
                    instrument: 0,
                    isPlaying: false
                ))
            }
        }
        
        // リズム音源チャンネル情報
        var updatedRhythmChannels: [ChannelInfo] = []
        // リズムの各パートをダミーで設定
        for i in 0..<6 {
            let partName = ["BD", "SD", "TOP", "HH", "TOM", "RIM"][i]
            updatedRhythmChannels.append(ChannelInfo(
                type: "RHYTHM",
                number: i + 1,
                address: 0,
                note: partName,
                instrument: 0,
                isPlaying: isRhythmActive
            ))
        }
        
        // ADPCM音源チャンネル情報
        let updatedAdpcmChannel = ChannelInfo(
            type: "ADPCM",
            number: 1,
            address: 0,
            note: "---",
            instrument: 0,
            isPlaying: isADPCMActive
        )
        
        // メインスレッドで更新
        DispatchQueue.main.async {
            self.fmChannels = updatedFmChannels
            self.ssgChannels = updatedSsgChannels
            self.rhythmChannels = updatedRhythmChannels
            self.adpcmChannel = updatedAdpcmChannel
        }
    }

    // PMD音楽を再生する関数
    func runPMDMusic() {
        guard !programRunning else {
            appendLog("既にプログラムが実行中です")
            return
        }
        
        // 音声エンジンの初期化確認
        if audioEngine == nil {
            appendLog("オーディオエンジンを初期化します")
            setupAudio()
        }
        
        // PMD88の実行
        appendLog("PMD88音楽再生を開始します")
        
        // 状態を更新
        DispatchQueue.main.async {
            self.programRunning = true
            self.shouldStop = false
            self.status = "PMD88音楽再生中..."
            self.runButtonEnabled = false
            self.stopButtonEnabled = true
            self.resetButtonEnabled = false
            self.objectWillChange.send()
        }
        
        // すべての処理をバックグラウンドスレッドで実行
        DispatchQueue.global(qos: .userInitiated).async {
            // PMD用の初期設定
            self.initializePMDWorkArea()
            
            // オーディオエンジンを開始
            DispatchQueue.main.async {
                self.audioEngine?.updateState() // 全音源の状態を更新してから
                self.audioEngine?.start()      // オーディオエンジンを開始
                self.appendLog("オーディオエンジン開始 - 全音源初期化完了")
            }
            
            // メインループ - タイマーベースでCPUを実行
            // タイマーを使用して処理を分割
            let processingTime: TimeInterval = 0.01 // 10ミリ秒ごとに処理
            let instructionsPerBatch = 10000 // 一度に処理する命令数
            var loopSteps = 0
            var lastUpdateTime = Date()
            
            // メインループ
            while !self.shouldStop {
                // CPU命令を一定数処理
                for _ in 0..<instructionsPerBatch {
                    _ = self.cpu.step()
                    loopSteps += 1
                    
                    // 停止要求があれば即座に中断
                    if self.shouldStop {
                        break
                    }
                }
                
                // 定期的に音源状態を更新
                let now = Date()
                if now.timeIntervalSince(lastUpdateTime) >= 0.05 { // 50msごとに更新
                    lastUpdateTime = now
                    
                    // 全音源の状態をオーディオエンジンに反映
                    DispatchQueue.main.async {
                        self.audioEngine?.updateState() // 全音源の状態を更新
                        
                        // チャンネル情報を更新
                        self.updateChannelInfo()
                        
                        // UI状態更新
                        self.status = "PMD88実行中...（\(loopSteps)ステップ）"
                        self.objectWillChange.send()
                    }
                }
                
                // 少し待機してCPUに余裕を持たせる
                Thread.sleep(forTimeInterval: processingTime)
            }
            
            // 再生終了の処理
            self.appendLog("PMD実行完了: \(loopSteps)ステップ実行")
            
            // 全チャンネルを停止
            self.stopAllChannels()
            
            // UI状態を更新
            DispatchQueue.main.async {
                self.programRunning = false
                self.status = "PMD88音楽停止"
                self.runButtonEnabled = true
                self.stopButtonEnabled = false
                self.resetButtonEnabled = true
                self.objectWillChange.send()
            }
            
            // 最終更新
            self.updateChannelInfo()
        }
    }
    
    // すべての音源を停止
    private func stopAllChannels() {
        // FM音源のキーオフ処理
        for ch in 0..<6 {
            let fmKeyOffRegister: UInt8 = 0x28
            let fmKeyOffValue: UInt8 = UInt8(ch) // チャンネル番号に応じた値
            portOut(port: 0xA0, value: fmKeyOffRegister)
            portOut(port: 0xA1, value: fmKeyOffValue)
        }
        
        // SSG音量ゼロ設定
        for ch in 0..<3 {
            let ssgVolumeRegister: UInt8 = UInt8(0x08 + ch)
            portOut(port: 0xA0, value: ssgVolumeRegister)
            portOut(port: 0xA1, value: 0x00) // 音量ゼロ
        }
    }
    
    // PMDワークエリアの初期化
    private func initializePMDWorkArea() {
        appendLog("PMDワークエリアの初期化")
        
        // D88ファイルが読み込まれているか確認
        if let d88Data = self.d88Data {
            // D88ファイルのヘッダ情報を解析
            appendLog("D88ファイルデータを解析: \(d88Data.count)バイト")
            
            // D88ファイルからPMDデータを抽出してメモリに転送
            if d88Data.count > 0x2B0 {  // 最低限のヘッダサイズ
                // D88ファイルの構造に基づいてデータを抽出
                // 通常、D88ファイルは0x20バイトのヘッダと、各トラックのデータで構成されています
                
                // PMDデータの開始アドレス（0x4C00）にデータを転送
                let pmdDataStartAddr = 0x4C00
                let maxDataSize = min(d88Data.count - 0x2B0, 0x1000)  // 最大4KBまで
                
                appendLog("PMDデータをメモリアドレス0x\(String(format: "%04X", pmdDataStartAddr))に転送: \(maxDataSize)バイト")
                
                // データをメモリに転送
                for i in 0..<maxDataSize {
                    if pmdDataStartAddr + i < cpu.memory.count {
                        cpu.memory[pmdDataStartAddr + i] = d88Data[0x2B0 + i]
                    }
                }
                
                // 音色データの転送（0x6000から）
                let toneDataStartAddr = 0x6000
                if d88Data.count > 0x2B0 + maxDataSize + 0x100 {  // 音色データがある場合
                    let toneDataSize = min(d88Data.count - (0x2B0 + maxDataSize), 0x1000)  // 最大4KBまで
                    
                    appendLog("音色データをメモリアドレス0x\(String(format: "%04X", toneDataStartAddr))に転送: \(toneDataSize)バイト")
                    
                    // データをメモリに転送
                    for i in 0..<toneDataSize {
                        if toneDataStartAddr + i < cpu.memory.count {
                            cpu.memory[toneDataStartAddr + i] = d88Data[0x2B0 + maxDataSize + i]
                        }
                    }
                }
            } else {
                appendLog("⚠️ D88ファイルのサイズが小さすぎます: \(d88Data.count)バイト")
            }
        } else {
            appendLog("⚠️ D88ファイルが読み込まれていません")
        }
        
        // メモリ範囲をクリア (0x1000-0x1FFF)
        for addr in 0x1000...0x1FFF {
            cpu.memory[addr] = 0
        }
        
        // 各データのアドレスを設定（PMDGのワークエリア定義に基づく）
        // 曲データアドレス (mmlbuf)
        cpu.memory[0x1000] = 0x00 // L
        cpu.memory[0x1001] = 0x4C // H (0x4C00 = th101.datのロード位置)
        
        // 音色データアドレス (tondat)
        cpu.memory[0x1002] = 0x00 // L
        cpu.memory[0x1003] = 0x60 // H (0x6000 = 音色データのロード位置)
        
        // 効果音データアドレス (efftbl)
        cpu.memory[0x1004] = 0x00 // L
        cpu.memory[0x1005] = 0x60 // H (0x6000 = 効果音データのロード位置)
        
        // SSGの初期設定（全チャンネルをリセット）
        for i in 0..<16 {
            cpu.opnaRegisters[i] = 0
        }
        
        // ミキサー設定: 全チャンネルのトーンを有効化
        cpu.opnaRegisters[0x07] = 0b00111000 // ビット0-2:トーン有効、ビット3-5:ノイズ無効
        
        // 全チャンネルの音量を設定
        cpu.opnaRegisters[0x08] = 0x0F // チャンネルA 音量最大
        cpu.opnaRegisters[0x09] = 0x0F // チャンネルB 音量最大
        cpu.opnaRegisters[0x0A] = 0x0F // チャンネルC 音量最大
        
        // PMDの開始ルーチンを呼び出す（pmd2gの開始アドレス + オフセット）
        appendLog("PMD初期化処理を開始")
        cpu.pc = 0xAA00 // PMD2の開始アドレス
        cpu.h = 0x4C    // 曲データのあるメモリページ
        cpu.l = 0x00    // オフセット
        
        // 初期化処理を実行（短いループで）
        var initSteps = 0
        while initSteps < 100_000 && !shouldStop {
            _ = cpu.step()
            initSteps += 1
            
            // 曲データの読み込みが完了した場所で一旦停止
            if cpu.pc == 0xAA03 || initSteps % 10000 == 0 {
                appendLog("PMD初期化実行中...ステップ数: \(initSteps), PC=\(String(format:"0x%04X", cpu.pc))")
            }
            
            // PMDの演奏開始後は抜ける
            if initSteps > 10000 {
                break
            }
        }
        
        // チャンネル情報を初期化
        self.updateChannelInfo()
    }
    
    // 停止処理
    func stop() {
        // 停止フラグを設定
        shouldStop = true
        
        // すぐに反映されるようにUI状態を更新
        DispatchQueue.main.async {
            self.status = "停止処理中..."
            self.objectWillChange.send()
        }
        
        // 停止が完了するまで少し待機
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            // 確実に停止したことを確認
            if self.programRunning {
                self.programRunning = false
                
                // すべての音源をリセット
                self.stopAllChannels()
                
                // 状態更新
                DispatchQueue.main.async {
                    self.status = "停止しました"
                    self.runButtonEnabled = true
                    self.stopButtonEnabled = false
                    self.resetButtonEnabled = true
                    self.objectWillChange.send()
                }
                
                // チャンネル情報の最終更新
                self.updateChannelInfo()
            }
        }
    }

}
