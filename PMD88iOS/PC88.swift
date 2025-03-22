//
//  PC88.swift
//  PMD88iOS
//
//  Created by 越川将人 on 2025/03/21.
//

import SwiftUI
import Foundation
import AVFoundation

// Z80クラスを明示的にインポート
@_exported import struct Foundation.Data

class PC88: ObservableObject {
    @Published var status = "Ready"
    @Published var cpu = Z80()
    @Published var programRunning = false
    @Published var lastLog = ""
    
    // チャンネル情報を保持する構造体
    struct ChannelInfo: Identifiable {
        var id = UUID()
        var type: String          // "FM", "SSG", "RHYTHM", "ADPCM"のいずれか
        var number: Int           // チャンネル番号（1始まり）
        var address: UInt16       // 演奏中のアドレス
        var isPlaying: Bool       // 演奏中かどうか
        var note: String          // 音名（例：「C4」）
        var volume: Int           // 音量（0-127）
        var instrument: Int       // 音色番号
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
    
    // FM1チャンネルの追加情報
    @Published var fm1FnumValue = "0x0000"          // BLOCK/FNUM値
    @Published var fm1Volume = 0                     // 音量
    @Published var fm1Length = 0                     // 残りの長さ
    @Published var fm1PartLoop = "0x0000"           // 演奏終了時の戻り先
    
    // 追加モニタリング情報
    @Published var songDataAddress = "0x0000"        // 曲データアドレス
    @Published var fm1Position = "0x0000"           // FM1チャンネル位置
    @Published var keyOnRegisterValue = "0x00"       // キーオンレジスタ値
    @Published var isChannelActive = false           // チャンネルがアクティブかどうか
    
    // 実行開始・停止フラグ
    private var shouldStop = false
    private var lastPortOutTime = 0
    private var lastPortCheckTime = 0
    
    private var audioEngine: AudioEngine?
    
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
    
    // テスト用の正弦波を再生する関数
    func playSineWave() {
        print("📱 音声再生開始")
        
        // SSGの初期設定でテスト音を設定
        // チャンネルA周波数設定 (440Hz)
        cpu.opnaRegisters[0x00] = 0x50 // 周波数ローバイト
        cpu.opnaRegisters[0x01] = 0x01 // 周波数ハイバイト (01:50 = 336)
        
        // ミキサー設定: チャンネルAのみトーン有効
        cpu.opnaRegisters[0x07] = 0xFE // チャンネルAのみトーン有効
        
        // チャンネルAの音量を最大に
        cpu.opnaRegisters[0x08] = 0x0F // 音量最大
        
        // SSG状態を更新してから再生開始
        audioEngine?.updateSSGState()
        
        // オーディオエンジンが初期化されていなかったら再初期化
        if audioEngine == nil {
            setupAudio()
        }
        
        // 再生開始（強制的に）
        audioEngine?.stop() // 一旦停止して
        audioEngine?.start() // 再開始
        
        appendLog("音声再生開始: 440Hzテスト音")
    }
    
    // テスト用の正弦波を停止する関数
    func stopSineWave() {
        print("📱 音声再生停止")
        audioEngine?.stop()
        
        // 全チャンネルをミュート
        cpu.opnaRegisters[0x08] = 0x00
        cpu.opnaRegisters[0x09] = 0x00
        cpu.opnaRegisters[0x0A] = 0x00
        
        appendLog("音声再生停止")
    }
    
    // ファイルを読み込む関数（アプリバンドルから）
    private func readFile(fromPath path: String) -> Data? {
        appendLog("ファイル読み込み開始: \(path)")
        
        // 絶対パスの場合はそのまま使用、そうでなければバンドルから読み込む
        if path.hasPrefix("/") {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                appendLog("ファイル読み込み成功: \(path) (\(data.count)バイト)")
                return data
            } catch {
                appendLog("ファイル読み込みエラー: \(path) (\(error.localizedDescription))")
                DispatchQueue.main.async {
                    self.lastError = "ファイル読み込みエラー: \(path), \(error.localizedDescription)"
                }
                return nil
            }
        } else {
            // バンドルからファイルを読み込む
            guard let fileURL = Bundle.main.url(forResource: path, withExtension: nil) else {
                appendLog("バンドル内にファイルが見つかりません: \(path)")
                DispatchQueue.main.async {
                    self.lastError = "バンドル内にファイルが見つかりません: \(path)"
                }
                return nil
            }
            
            do {
                let data = try Data(contentsOf: fileURL)
                appendLog("バンドルからファイル読み込み成功: \(path) (\(data.count)バイト)")
                return data
            } catch {
                appendLog("バンドルからのファイル読み込みエラー: \(path) (\(error.localizedDescription))")
                DispatchQueue.main.async {
                    self.lastError = "バンドルからのファイル読み込みエラー: \(path), \(error.localizedDescription)"
                }
                return nil
            }
        }
    }
    
    // D88ディスクイメージを読み込む関数
    func loadD88(_ disk: D88Disk) {
        appendLog("========== エミュレータ初期化開始 ==========")
        
        // 音声エンジンを停止
        audioEngine?.stop()
        
        cpu.reset()
        appendLog("CPU初期化完了")
        
        // Z80のレジスタが正しく初期化されたことを確認
        appendLog("Z80 opnaRegisters配列サイズ: \(cpu.opnaRegisters.count)")
        
        // opnaRegistersの初期化を確認
        for i in 0..<cpu.opnaRegisters.count {
            cpu.opnaRegisters[i] = 0
        }
        appendLog("opnaRegisters配列を0で初期化完了")
        
        cpu.pc = 0xAA00 // PMD2の開始アドレス
        appendLog("開始アドレス設定: 0xAA00")
        
        // PMD2を読み込む
        if let pmd2Data = readFile(fromPath: "pmd2g") {
            cpu.loadProgram(at: 0xAA00, data: pmd2Data)
            appendLog("pmd2g読み込み完了: \(pmd2Data.count)バイト（アドレス0xAA00）")
            DispatchQueue.main.async {
                self.status = "pmd2g読み込み完了: \(pmd2Data.count)バイト"
            }
        } else {
            appendLog("⚠️ pmd2gの読み込みに失敗しました")
        }
        
        // 音楽データを読み込む
        if let musicData = readFile(fromPath: "th101.dat") {
            // データの整合性を確認
            appendLog("TH101.datファイルサイズ: \(musicData.count)バイト")
            
            // ファイル内容のチェック
            var fileHeader = "TH101ファイルヘッダ: "
            for i in 0..<min(32, musicData.count) {
                fileHeader += String(format: "%02X ", musicData[i])
            }
            appendLog(fileHeader)
            
            // メモリにロードする前にメモリ領域をクリア
            for i in 0x4C00..<(0x4C00 + min(musicData.count + 256, 0x1000)) {
                if i < cpu.memory.count {
                    cpu.memory[i] = 0
                }
            }
            appendLog("メモリ領域クリア完了: 0x4C00-0x\(String(format: "%04X", 0x4C00 + min(musicData.count + 256, 0x1000) - 1))")
            
            // データをメモリにロード
            cpu.loadProgram(at: 0x4C00, data: musicData)
            appendLog("TH101読み込み完了: \(musicData.count)バイト（アドレス0x4C00）")
            
            // メモリにロードされた最初の数バイトを表示してデバッグ
            var firstBytes = "TH101先頭バイト: "
            for i in 0..<min(16, musicData.count) {
                firstBytes += String(format: "%02X ", musicData[i])
            }
            appendLog(firstBytes)
            
            // メモリに実際にロードされているか確認
            var memoryBytes = "メモリ[0x4C00]の内容: "
            for i in 0..<min(16, musicData.count) {
                memoryBytes += String(format: "%02X ", cpu.memory[0x4C00 + i])
            }
            appendLog(memoryBytes)
            
            // メモリの内容が一致しているか確認
            var mismatchFound = false
            for i in 0..<min(musicData.count, 256) {
                if cpu.memory[0x4C00 + i] != musicData[i] {
                    appendLog("❗️ メモリ不一致: アドレス 0x\(String(format: "%04X", 0x4C00 + i)) - ファイル: \(String(format: "%02X", musicData[i])) vs メモリ: \(String(format: "%02X", cpu.memory[0x4C00 + i]))")
                    mismatchFound = true
                    if i > 10 { break } // 最初の数個の不一致のみ表示
                }
            }
            
            if !mismatchFound {
                appendLog("✅ メモリ整合性確認: ファイル内容とメモリ内容が一致")
            }
            
            // PMD88のワークエリアをデバッグ表示
            debugPMDWorkingArea()
            
            DispatchQueue.main.async {
                self.status = "TH101読み込み完了: \(musicData.count)バイト"
            }
        } else {
            appendLog("⚠️ 音楽データ(TH101)の読み込みに失敗しました")
        }
        
        // MCGデータを読み込む
        if let mcgData = readFile(fromPath: "mcg") {
            cpu.loadProgram(at: 0xA600, data: mcgData)
            appendLog("MCG読み込み完了: \(mcgData.count)バイト（アドレス0xA600）")
            DispatchQueue.main.async {
                self.status = "MCG読み込み完了: \(mcgData.count)バイト"
            }
        } else {
            appendLog("⚠️ MCGデータの読み込みに失敗しました")
        }
        
        // EFFEC.DATを読み込む
        if let effecData = readFile(fromPath: "effec.dat") {
            cpu.loadProgram(at: 0x6000, data: effecData)
            appendLog("EFFEC.DAT読み込み完了: \(effecData.count)バイト（アドレス0x6000）")
            DispatchQueue.main.async {
                self.status = "EFFEC.DAT読み込み完了: \(effecData.count)バイト"
            }
        } else {
            appendLog("⚠️ EFFEC.DATの読み込みに失敗しました")
        }
        
        // PC8801-23ボードをセットアップ
        cpu.setPortMapping(forBoard: BoardTypeConstants.pc8801_23)
        appendLog("PC-8801-23ボードのポートマッピング設定完了")
        
        // SSGの初期設定（アプリ起動時に音が出るようにテスト設定）
        // すべてのSSGレジスタを確実に初期化
        appendLog("SSGレジスタの初期化開始")
        for i in 0..<16 {
            cpu.opnaRegisters[i] = 0
        }
        
        // チャンネルA周波数設定 (440Hz近辺)
        cpu.opnaRegisters[0x00] = 0x50 // 周波数ローバイト
        cpu.opnaRegisters[0x01] = 0x01 // 周波数ハイバイト
        
        // ミキサー設定: チャンネルAのみトーン有効、他は無効化
        cpu.opnaRegisters[0x07] = 0xFE // チャンネルAのみトーン有効
        
        // チャンネルAの音量を最大に
        cpu.opnaRegisters[0x08] = 0x0F // 音量最大（0-15の値）
        
        appendLog("SSG初期設定: チャンネルA 440Hz、最大音量")
        
        // OPNAレジスタの状態確認
        var registers = "OPNAレジスタ初期状態: "
        for i in 0...0x0F {
            registers += String(format: "[%02X]=%02X ", i, cpu.opnaRegisters[i])
        }
        appendLog(registers)
        
        // オーディオエンジンを更新して初期状態を設定
        setupAudio() // AudioEngineを再初期化
        
        // AudioEngineがnilでないことを確認
        if audioEngine != nil {
            appendLog("オーディオエンジン初期化成功")
            audioEngine?.updateSSGState()
        } else {
            appendLog("⚠️ オーディオエンジン初期化失敗")
            // 再度初期化を試みる
            setupAudio()
        }
        
        appendLog("========== エミュレータ初期化完了 ==========")
        appendDebugInfo()
        
        DispatchQueue.main.async {
            self.status = "初期化完了 - 実行ボタンを押してください"
        }
    }
    
    // エミュレータを停止する関数
    func stop() {
        appendLog("エミュレータ停止コマンド受信")
        
        // 停止フラグを設定
        shouldStop = true
        cpu.isStopped = true
        appendLog("CPU実行停止フラグ設定")
        
        // 全チャンネルをキーオフ状態にする
        appendLog("全音源チャンネルをキーオフ状態に設定")
        
        // FM音源の全チャンネルをキーオフ
        cpu.opnaRegisters[0x28] = 0x00 // 全FMチャンネルキーオフ
        
        // SSG音源の全チャンネルをミュート
        cpu.opnaRegisters[0x08] = 0x00 // チャンネルA音量ゼロ
        cpu.opnaRegisters[0x09] = 0x00 // チャンネルB音量ゼロ
        cpu.opnaRegisters[0x0A] = 0x00 // チャンネルC音量ゼロ
        
        // リズム音源を無効化
        cpu.opnaRegisters[0x1B] = 0x00 // リズム音源無効
        
        // ADPCMを無効化
        cpu.opnaRegisters[0x10] = 0x00 // ADPCMレジスタリセット
        
        // 音声エンジンの停止（先に音源を停止してからエンジンを停止）
        if let engine = audioEngine {
            // 各音源エンジンにキーオフ状態を反映
            engine.updateState() // すべての音源の状態を一度に更新
            
            // 各音源の状態を個別に確認
            let fmKeyOnReg = cpu.opnaRegisters[0x28]
            appendLog("🎹 FM音源キーオンレジスタ: \(String(format: "0x%02X", fmKeyOnReg))")
            
            // 少し待機してからエンジンを停止
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                engine.stop()
                self.appendLog("音声エンジン停止完了")
            }
        }
        
        // UI状態更新
        DispatchQueue.main.async {
            self.programRunning = false
            self.status = "停止しました"
            self.runButtonEnabled = true
            self.stopButtonEnabled = false
            self.resetButtonEnabled = true
        }
        
        appendLog("エミュレータ停止処理完了")
    }
    
    // CPU状態を表示する関数
    private func showCPUState() {
        appendLog("==== CPU状態 ====")
        appendLog("PC: \(String(format: "0x%04X", cpu.pc))")
        appendLog("A: \(String(format: "0x%02X", cpu.a)), F: \(String(format: "0x%02X", cpu.f))")
        appendLog("BC: \(String(format: "0x%04X", cpu.bc())), DE: \(String(format: "0x%04X", cpu.de())), HL: \(String(format: "0x%04X", cpu.hl()))")
        appendLog("SP: \(String(format: "0x%04X", cpu.sp)), IX: \(String(format: "0x%04X", cpu.ix())), IY: \(String(format: "0x%04X", cpu.iy()))")
        appendLog("================")
    }
    
    // デバッグログを表示する関数
    func showDebugLog() {
        appendLog("デバッグログ表示リクエスト受信")
        
        // デバッグ情報を構築
        let timestamp = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timeString = formatter.string(from: timestamp)
        
        var debugInfo = "===== PMD88デバッグログ [\(timeString)] =====\n"
        
        // OPNAレジスタの状態を表示
        let nonZeroRegs = self.cpu.opnaRegisters.enumerated().filter { $0.element != 0 }
        var regInfo = "【OPNAレジスタ状態】\n"
        if nonZeroRegs.isEmpty {
            regInfo += "  全て0（書き込みなし）\n"
        } else {
            // レジスタグループごとに表示
            regInfo += "  【表FM音源】\n"
            
            // FM音源パラメータグループ
            let fmGroups = [
                (0x00, 0x0F, "SSG/制御"),
                (0x10, 0x1F, "リズム・ADPCM"),
                (0x20, 0x2F, "タイマー・フラグ"),
                (0x30, 0x3F, "FM音色1"),
                (0x40, 0x4F, "FM音色2"),
                (0x50, 0x5F, "FM音色3"),
                (0x60, 0x6F, "FM音色4"),
                (0x70, 0x7F, "FM音色5"),
                (0x80, 0x8F, "FM音色6"),
                (0x90, 0x9F, "FM音色7"),
                (0xA0, 0xAF, "FM周波数1"),
                (0xB0, 0xBF, "FM周波数2/アルゴリズム")
            ]
            
            for (start, end, groupName) in fmGroups {
                let regsInGroup = nonZeroRegs.filter { $0.offset >= start && $0.offset <= end }
                if !regsInGroup.isEmpty {
                    regInfo += "    ● \(groupName): "
                    let regValues = regsInGroup.map { "[\(String(format: "%02X", $0.offset))]=\(String(format: "%02X", $0.element))" }
                    regInfo += regValues.joined(separator: ", ") + "\n"
                }
            }
            
            // 裏FM音源があれば表示
            let backFM = nonZeroRegs.filter { $0.offset >= 0x100 }
            if !backFM.isEmpty {
                regInfo += "  【裏FM音源】\n"
                for (start, end, groupName) in fmGroups {
                    let regsInGroup = backFM.filter { $0.offset >= (start + 0x100) && $0.offset <= (end + 0x100) }
                    if !regsInGroup.isEmpty {
                        regInfo += "    ● \(groupName): "
                        let regValues = regsInGroup.map { "[\(String(format: "%02X", $0.offset - 0x100))]=\(String(format: "%02X", $0.element))" }
                        regInfo += regValues.joined(separator: ", ") + "\n"
                    }
                }
            }
        }
        debugInfo += regInfo + "\n"
        
        // ポートマッピング情報を表示
        var portInfo = "【ポートマッピング状態】\n"
        let portMapEntries = self.cpu.portMap.map { "\(String(format: "%02X", $0.key))→\(String(format: "%02X", $0.value))" }
        if portMapEntries.isEmpty {
            portInfo += "  マッピングなし\n"
        } else {
            portInfo += "  " + portMapEntries.joined(separator: ", ") + "\n"
        }
        debugInfo += portInfo + "\n"
        
        // CPU状態を表示
        let cpuState = "【CPU状態】\n" +
            "  PC: \(String(format: "%04X", self.cpu.pc))\n" +
            "  A: \(String(format: "%02X", self.cpu.a)), F: \(String(format: "%02X", self.cpu.f))\n" +
            "  BC: \(String(format: "%04X", self.cpu.bc())), DE: \(String(format: "%04X", self.cpu.de())), HL: \(String(format: "%04X", self.cpu.hl()))\n" +
            "  SP: \(String(format: "%04X", self.cpu.sp)), IX: \(String(format: "%04X", self.cpu.ix())), IY: \(String(format: "%04X", self.cpu.iy()))\n"
        debugInfo += cpuState + "\n"
        
        // ポート状態を表示
        var portStates = "【ポート状態】\n"
        let ports = self.cpu.ports.filter { $0.value != 0 }
        if ports.isEmpty {
            portStates += "  全て0（書き込みなし）\n"
        } else {
            for (port, value) in ports.sorted(by: { $0.key < $1.key }) {
                portStates += "  Port[\(String(format: "%02X", port))]: \(String(format: "%02X", value))\n"
            }
        }
        debugInfo += portStates + "\n"
        
        // メモリダンプ（重要な領域のみ）
        let memoryAreas = [
            ("PMD2領域(0xAA00)", 0xAA00, 64),
            ("音楽データ領域(0x4C00)", 0x4C00, 64),
            ("スタック領域", self.cpu.sp, 32)
        ]
        
        var memoryDump = "【メモリダンプ（重要領域）】\n"
        for (name, addr, size) in memoryAreas {
            memoryDump += "  \(name):\n"
            for row in 0..<(size / 16 + (size % 16 > 0 ? 1 : 0)) {
                let rowAddr = addr + row * 16
                var hexLine = "    \(String(format: "%04X", rowAddr)): "
                var asciiLine = " | "
                
                for col in 0..<min(16, size - row * 16) {
                    let byteAddr = rowAddr + col
                    let byte = self.cpu.memory[byteAddr]
                    hexLine += String(format: "%02X ", byte)
                    
                    // ASCII表示（印字可能な文字のみ）
                    if byte >= 32 && byte <= 126 {
                        asciiLine += String(UnicodeScalar(byte))
                    } else {
                        asciiLine += "."
                    }
                }
                
                memoryDump += hexLine + asciiLine + "\n"
            }
            memoryDump += "\n"
        }
        debugInfo += memoryDump
        
        // 最終ステップ情報
        debugInfo += "【実行状態】\n"
        debugInfo += "  ステップ数: \(stepCount)\n"
        debugInfo += "  ポート出力カウンター: \(self.cpu.outPortCounter)\n"
        debugInfo += "  実行状態: \(programRunning ? "実行中" : "停止中")\n\n"
        
        // デバッグ情報をコンソールに出力
        print("\n==================================================")
        print(debugInfo)
        print("==================================================\n")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // UIにもデバッグ情報を表示
            self.lastDebugLog = "===== PMD88デバッグログ =====\n\n" + self.lastLog + "\n\n" + debugInfo + "\n\n" + self.cpu.debugLog.joined(separator: "\n")
        }
    }
    
    // エミュレータ実行
    func run() {
        appendLog("エミュレータ実行開始")
        DispatchQueue.main.async {
            self.status = "実行中..."
            self.programRunning = true
            self.runButtonEnabled = false
            self.stopButtonEnabled = true
            self.resetButtonEnabled = false
        }
        
        shouldStop = false
        cpu.isStopped = false
        _ = 0
        
        // エミュレータ初期化完了ログ
        appendLog("エミュレータ開始: PC=\(String(format: "0x%04X", self.cpu.pc))")
        
        // SSG初期化
        audioEngine?.updateSSGState()
        
        // オーディオ再生を開始
        audioEngine?.start()
        appendLog("オーディオ再生開始")
        
        // エミュレーションループをバックグラウンドスレッドで実行
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            var localStepCount = 0
            let startTime = Date()
            var lastUpdateTime = startTime
            
            // エミュレーションループ
            while !self.shouldStop && !self.cpu.isStopped && localStepCount < 10_000_000 {
                // Z80ステップ実行とSSG更新
                if localStepCount % 1000 == 0 { // およそ5ミリ秒ごと
                    // SSG状態の更新
                    self.audioEngine?.updateSSGState()
                }
                
                // Z80ステップ実行
                let result = self.cpu.step()
                if result == 0 {
                    // CPUが停止状態（エラーなど）
                    break
                }
                
                localStepCount += 1
                
                // 定期的な状態更新（メインスレッドで）
                let now = Date()
                if now.timeIntervalSince(lastUpdateTime) >= 0.2 { // 200ミリ秒ごとに更新
                    lastUpdateTime = now
                    DispatchQueue.main.async {
                        self.stepCount = localStepCount
                        self.status = "実行中... ステップ数: \(localStepCount)"
                    }
                    
                    // CPUに少し休ませる
                    Thread.sleep(forTimeInterval: 0.001)
                }
            }
            
            // 最終的なステップ数をメインスレッドで更新
            DispatchQueue.main.async {
                self.stepCount = localStepCount
            }
            
            // 実行が終了したらメインスレッドでUIを更新
            DispatchQueue.main.async {
                self.programRunning = false
                self.status = "実行終了（\(localStepCount)ステップ）"
                self.runButtonEnabled = true
                self.stopButtonEnabled = false
                self.resetButtonEnabled = true
            }
            
            self.appendLog("エミュレータ実行終了: \(localStepCount)ステップ実行")
            self.appendDebugInfo()
        }
    }
    
    // SSGの状態を含むデバッグ情報を出力
    private func appendDebugInfo() {
        appendLog("==== CPU状態 ====")
        appendLog("PC: \(String(format: "0x%04X", cpu.pc))")
        appendLog("A: \(String(format: "0x%02X", cpu.a)), F: \(String(format: "0x%02X", cpu.f))")
        appendLog("BC: \(String(format: "0x%04X", cpu.bc())), DE: \(String(format: "0x%04X", cpu.de())), HL: \(String(format: "0x%04X", cpu.hl()))")
        appendLog("SP: \(String(format: "0x%04X", cpu.sp)), IX: \(String(format: "0x%04X", cpu.ix())), IY: \(String(format: "0x%04X", cpu.iy()))")
        appendLog("================")
    }
    
    func appendLog(_ message: String) {
        let timestamp = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timeString = formatter.string(from: timestamp)
        
        let logMessage = "[\(timeString)] \(message)"
        print(logMessage)
        
        // UIの更新はメインスレッドで行う必要がある
        if Thread.isMainThread {
            // すでにメインスレッドにいる場合は直接更新
            self.lastLog += logMessage + "\n"
            // 最大行数を制限
            let lines = self.lastLog.components(separatedBy: "\n")
            if lines.count > 1000 {
                self.lastLog = lines.suffix(500).joined(separator: "\n") + "\n"
            }
        } else {
            // バックグラウンドスレッドからの場合はメインスレッドに投げる
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.lastLog += logMessage + "\n"
                // 最大行数を制限
                let lines = self.lastLog.components(separatedBy: "\n")
                if lines.count > 1000 {
                    self.lastLog = lines.suffix(500).joined(separator: "\n") + "\n"
                }
                
                // デバッグログも更新してUIが常に最新のものを表示するように
                if self.lastDebugLog.isEmpty {
                    self.lastDebugLog = self.lastLog
                }
            }
        }
    }
    
    private func emulateStep() {
        guard programRunning else { return }
        
        // Z80ステップ実行
        let result = cpu.step()
        if result == 0 {
            // CPUが停止状態（エラーなど）
            stop()
            return
        }
        
        // ローカル変数としてステップをカウント
        let localStepCount = stepCount + 1
        
        // メインスレッドでステップカウントを更新
        DispatchQueue.main.async {
            self.stepCount = localStepCount
        }
    }
    
    // デバッグ用：オーディオエンジンの状態をチェック
    func checkAudioEngine() -> String {
        guard audioEngine != nil else {
            return "オーディオエンジンが初期化されていません"
        }
        
        // オーディオセッションの状態をチェック
        let session = AVAudioSession.sharedInstance()
        let volume = session.outputVolume
        let categoryString: String
        
        switch session.category {
        case .playback:
            categoryString = "再生"
        case .record:
            categoryString = "録音"
        case .playAndRecord:
            categoryString = "再生と録音"
        default:
            categoryString = "その他"
        }
        
        var result = "オーディオ状態:\n"
        result += "- セッション: \(categoryString)\n"
        result += "- システム音量: \(volume)\n"
        result += "- アクティブ: \(session.isOtherAudioPlaying ? "他のオーディオ再生中" : "専有")\n"
        
        return result
    }
    
    // PMD88のワークエリアをデバッグ表示する関数
    // 重要なレジスタの状態を確認するメソッド
    func checkCriticalRegisters() {
        appendLog("=== 重要なOPNAレジスタ状態確認 ===")
        
        // キーオンレジスタ (0x28)
        let keyOnReg = cpu.opnaRegisters[0x28]
        appendLog("キーオンレジスタ(0x28): \(String(format: "0x%02X", keyOnReg))")
        
        // チャンネル情報の解析
        let channelRaw = Int(keyOnReg & 0x07)
        let isExtended = (keyOnReg & 0x08) != 0
        let slotMask = (keyOnReg >> 4) & 0x0F
        let channel = isExtended ? channelRaw + 3 : channelRaw
        
        appendLog("  - チャンネル: \(channel) (raw: \(channelRaw), 拡張: \(isExtended ? "あり" : "なし"))")
        appendLog("  - スロットマスク: \(String(format: "%04b", slotMask))")
        
        // 各FMチャンネルの周波数設定を確認
        appendLog("各FMチャンネルの周波数設定:")
        for ch in 0..<6 {
            // チャンネル番号の調整（0-2は通常のチャンネル、3-5は拡張チャンネル）
            let regOffset = ch < 3 ? ch : ch + 1
            
            if 0xA0 + regOffset < cpu.opnaRegisters.count && 0xA4 + regOffset < cpu.opnaRegisters.count {
                let freqLow = cpu.opnaRegisters[Int(0xA0 + regOffset)]
                let freqHighBlock = cpu.opnaRegisters[Int(0xA4 + regOffset)]
                
                let fnum = Int(freqLow) + ((Int(freqHighBlock) & 0x07) << 8)
                let block = Int((freqHighBlock >> 3) & 0x07)
                
                appendLog("  - CH\(ch): F-Number=\(fnum), Block=\(block)")
            }
        }
        
        // リズム音源の状態を確認
        if 0x10 < cpu.opnaRegisters.count {
            let rhythmReg = cpu.opnaRegisters[0x10]
            appendLog("リズム音源レジスタ(0x10): \(String(format: "0x%02X", rhythmReg))")
        }
    }
    
    // PMD88のフック処理の状態を確認するメソッド
    func checkPMD88Hooks() {
        appendLog("=== PMD88フック処理状態確認 ===")
        
        // PMDの主要なフック処理のアドレス
        let pmdhk1Addr = 0xAA5F // 音楽再生メインルーチン
        let pmdhk2Addr = 0xB9CA // ボリューム制御
        let pmdhk3Addr = 0xB70E // リズム音源のキーオン処理
        
        // 現在のPCがどのフック処理に近いか確認
        let pc = cpu.pc
        
        if (pc >= pmdhk1Addr - 0x20 && pc <= pmdhk1Addr + 0x20) {
            appendLog("現在PMDHK1(音楽再生メイン)付近で実行中: PC=\(String(format: "0x%04X", pc))")
        } else if (pc >= pmdhk2Addr - 0x20 && pc <= pmdhk2Addr + 0x20) {
            appendLog("現在PMDHK2(ボリューム制御)付近で実行中: PC=\(String(format: "0x%04X", pc))")
        } else if (pc >= pmdhk3Addr - 0x20 && pc <= pmdhk3Addr + 0x20) {
            appendLog("現在PMDHK3(リズム音源キーオン)付近で実行中: PC=\(String(format: "0x%04X", pc))")
        }
        
        // PMDのワークエリアの重要な値を確認
        let workAreas = [
            (address: 0x1000, name: "曲データアドレス（L,H）"),
            (address: 0x1002, name: "チャンネルステータス"),
            (address: 0x1100, name: "FMチャンネル1ワークエリア")
        ]
        
        for (addr, name) in workAreas {
            if addr < cpu.memory.count && addr + 1 < cpu.memory.count {
                let value = (Int(cpu.memory[addr + 1]) << 8) | Int(cpu.memory[addr])
                appendLog("\(name): 0x\(String(format: "%04X", value))")
            }
        }
    }
    
    // PMD88のワークエリアから各チャンネルの情報を取得して更新
    func updateChannelInfo() {
        // FMチャンネル情報の更新（1〜6チャンネル）
        updateFMChannelInfo()
        
        // SSGチャンネル情報の更新（1〜3チャンネル）
        updateSSGChannelInfo()
        
        // リズム音源情報の更新
        updateRhythmChannelInfo()
        
        // ADPCM情報の更新
        updateADPCMChannelInfo()
        
        // PMD88ワークエリアのFM1アドレス(0xBD61)を監視
        updatePMD88WorkAreaMonitor()
    }
    
    // FMチャンネル情報を更新
    private func updateFMChannelInfo() {
        // FMチャンネルのワークエリアは0x1100から始まる
        // 各チャンネルのデータ構造サイズは0x50バイト
        let fmWorkAreaBase = 0x1100
        var updatedChannels: [ChannelInfo] = []
        
        for ch in 0..<6 {
            let offset = fmWorkAreaBase + ch * 0x50
            
            // 安全チェック
            guard offset + 0x10 < cpu.memory.count else { continue }
            
            // アドレス情報の取得（演奏中のデータポインタ）
            let addrLow = cpu.memory[offset + 0x04]
            let addrHigh = cpu.memory[offset + 0x05]
            let address = UInt16(addrHigh) << 8 | UInt16(addrLow)
            
            // 演奏中かどうかのフラグ（0以外なら演奏中）
            let statusFlag = cpu.memory[offset + 0x00]
            let isPlaying = statusFlag != 0
            
            // 音色番号
            let instrument = Int(cpu.memory[offset + 0x06])
            
            // 音量（0-127）
            let volume = Int(cpu.memory[offset + 0x08])
            
            // 音名の取得（FMエンジンから取得）
            var note = "---"
            if let audioEngine = audioEngine, isPlaying {
                note = audioEngine.fmEngine.getChannelNoteName(channel: ch)
            }
            
            // チャンネル情報の作成
            let channelInfo = ChannelInfo(
                type: "FM",
                number: ch + 1,
                address: address,
                isPlaying: isPlaying,
                note: note,
                volume: volume,
                instrument: instrument
            )
            
            updatedChannels.append(channelInfo)
        }
        
        // UIを更新するためにメインスレッドで実行
        DispatchQueue.main.async {
            self.fmChannels = updatedChannels
        }
    }
    
    // SSGチャンネル情報を更新
    private func updateSSGChannelInfo() {
        // SSGチャンネルのワークエリアは0x1350から始まる
        // 各チャンネルのデータ構造サイズは0x50バイト
        let ssgWorkAreaBase = 0x1350
        var updatedChannels: [ChannelInfo] = []
        
        for ch in 0..<3 {
            let offset = ssgWorkAreaBase + ch * 0x50
            
            // 安全チェック
            guard offset + 0x10 < cpu.memory.count else { continue }
            
            // アドレス情報の取得（演奏中のデータポインタ）
            let addrLow = cpu.memory[offset + 0x04]
            let addrHigh = cpu.memory[offset + 0x05]
            let address = UInt16(addrHigh) << 8 | UInt16(addrLow)
            
            // 演奏中かどうかのフラグ（0以外なら演奏中）
            let statusFlag = cpu.memory[offset + 0x00]
            let isPlaying = statusFlag != 0
            
            // 音色番号
            let instrument = Int(cpu.memory[offset + 0x06])
            
            // 音量（0-15）
            let volume = Int(cpu.memory[offset + 0x08])
            
            // 音名（簡易的な実装）
            let note = isPlaying ? "SSG音" : "---"
            
            // チャンネル情報の作成
            let channelInfo = ChannelInfo(
                type: "SSG",
                number: ch + 1,
                address: address,
                isPlaying: isPlaying,
                note: note,
                volume: volume,
                instrument: instrument
            )
            
            updatedChannels.append(channelInfo)
        }
        
        // UIを更新するためにメインスレッドで実行
        DispatchQueue.main.async {
            self.ssgChannels = updatedChannels
        }
    }
    
    // リズム音源情報を更新
    private func updateRhythmChannelInfo() {
        // リズム音源のワークエリアは0x1500付近
        let rhythmWorkAreaBase = 0x1500
        var updatedChannels: [ChannelInfo] = []
        
        // リズム音源の種類（6種類）
        let rhythmTypes = ["BD", "SD", "TOP", "HH", "TOM", "RIM"]
        
        for (index, name) in rhythmTypes.enumerated() {
            // リズムフラグの取得（0x1500 + 0x10付近）
            let rhythmFlagOffset = rhythmWorkAreaBase + 0x10
            
            // 安全チェック
            guard rhythmFlagOffset < cpu.memory.count else { continue }
            
            // リズムフラグ（各ビットが各リズム音源に対応）
            let rhythmFlag = cpu.memory[rhythmFlagOffset]
            let isPlaying = (rhythmFlag & (1 << index)) != 0
            
            // 音量（固定値）
            let volume = isPlaying ? 15 : 0
            
            // チャンネル情報の作成
            let channelInfo = ChannelInfo(
                type: "RHYTHM",
                number: index + 1,
                address: UInt16(rhythmWorkAreaBase + index),
                isPlaying: isPlaying,
                note: name,
                volume: volume,
                instrument: index
            )
            
            updatedChannels.append(channelInfo)
        }
        
        // UIを更新するためにメインスレッドで実行
        DispatchQueue.main.async {
            self.rhythmChannels = updatedChannels
        }
    }
    
    // ADPCM情報を更新
    private func updateADPCMChannelInfo() {
        // ADPCM情報のワークエリアは0x1600付近
        let adpcmWorkAreaBase = 0x1600
        
        // 安全チェック
        guard adpcmWorkAreaBase + 0x10 < cpu.memory.count else { return }
        
        // ADPCMのステータスフラグ
        let statusFlag = cpu.memory[adpcmWorkAreaBase]
        let isPlaying = statusFlag != 0
        
        // アドレス情報
        let addrLow = cpu.memory[adpcmWorkAreaBase + 0x04]
        let addrHigh = cpu.memory[adpcmWorkAreaBase + 0x05]
        let address = UInt16(addrHigh) << 8 | UInt16(addrLow)
        
        // チャンネル情報の作成
        let channelInfo = ChannelInfo(
            type: "ADPCM",
            number: 1,
            address: address,
            isPlaying: isPlaying,
            note: isPlaying ? "ADPCM" : "---",
            volume: isPlaying ? 15 : 0,
            instrument: 0
        )
        
        // UIを更新するためにメインスレッドで実行
        DispatchQueue.main.async {
            self.adpcmChannel = channelInfo
        }
    }
    
    // PMD88ワークエリアの情報を監視する関数
    private func updatePMD88WorkAreaMonitor() {
        // FM1チャンネルのワークエリアのベースアドレス
        let fm1BaseAddress = 0xBD61
        let pmdMainWorkArea = 0x1000 // PMDのメインワークエリア
        
        // 安全チェック
        guard fm1BaseAddress + 30 < cpu.memory.count else { return }
        guard pmdMainWorkArea + 100 < cpu.memory.count else { return }
        
        // PMDメインワークエリアから曲データアドレスを取得
        let songDataLow = cpu.memory[pmdMainWorkArea]
        let songDataHigh = cpu.memory[pmdMainWorkArea + 1]
        let songDataAddr = UInt16(songDataHigh) << 8 | UInt16(songDataLow)
        
        // FM1チャンネル位置を取得 (0x1020-0x1021)
        let fm1PosLow = cpu.memory[pmdMainWorkArea + 0x20]
        let fm1PosHigh = cpu.memory[pmdMainWorkArea + 0x21]
        let fm1Pos = UInt16(fm1PosHigh) << 8 | UInt16(fm1PosLow)
        
        // FM1チャンネルのワークエリアの監視
        // 1. 演奏中のアドレス (offset 0, 2バイト)
        let addrLow = cpu.memory[fm1BaseAddress]
        let addrHigh = cpu.memory[fm1BaseAddress + 1]
        let currentValue = UInt16(addrHigh) << 8 | UInt16(addrLow)
        
        // 16進数表記と10進数表記を作成
        let hexValue = String(format: "0x%04X", currentValue)
        let decimalValue = Int(currentValue)
        
        // 前回の値と比較して変化を検出
        let hasChanged = currentValue != previousFm1Value
        
        // 値が変化した場合はログに出力
        if hasChanged {
            appendLog("📊 FM1アドレス(0xBD61)が変化: \(String(format: "0x%04X", previousFm1Value)) → \(hexValue)")
            previousFm1Value = currentValue
        }
        
        // 2. 演奏終了時の戻り先 (offset 2, 2バイト)
        let loopLow = cpu.memory[fm1BaseAddress + 2]
        let loopHigh = cpu.memory[fm1BaseAddress + 3]
        let loopAddr = UInt16(loopHigh) << 8 | UInt16(loopLow)
        let loopAddrHex = String(format: "0x%04X", loopAddr)
        
        // 3. 残りの長さ (offset 4, 1バイト)
        let length = Int(cpu.memory[fm1BaseAddress + 4])
        
        // 4. BLOCK/FNUM値 (offset 5, 2バイト)
        let fnumLow = cpu.memory[fm1BaseAddress + 5]
        let fnumHigh = cpu.memory[fm1BaseAddress + 6]
        let fnum = UInt16(fnumHigh) << 8 | UInt16(fnumLow)
        let fnumHex = String(format: "0x%04X", fnum)
        
        // 5. 音量 (offset 12, 1バイト)
        let volume = Int(cpu.memory[fm1BaseAddress + 12])
        
        // 6. キーオンレジスタの状態を取得
        let keyOnRegValue = cpu.opnaRegisters[0x28]
        
        // 7. チャンネルのアクティブ状態を確認
        let isActive = fm1Pos != 0 || currentValue != 0 || fnum != 0
        
        // 8. チャンネルの状態変化を検出
        let stateChanged = hasChanged || (previousFm1Fnum != fnum) || (previousFm1Volume != volume)
        
        // 状態が変化した場合は詳細ログを出力
        if stateChanged {
            appendLog("🎹 FM1チャンネル状態変化: addr=\(hexValue), fnum=\(fnumHex), vol=\(volume), keyOn=\(String(format: "0x%02X", keyOnRegValue))")
            
            // 状態を更新
            previousFm1Fnum = fnum
            previousFm1Volume = volume
        }
        
        // 9. メインワークエリアの曲データアドレスが変化したか確認
        if songDataAddr != previousSongDataAddr {
            appendLog("🎵 PMD曲データアドレス変化: \(String(format: "0x%04X", previousSongDataAddr)) → \(String(format: "0x%04X", songDataAddr))")
            previousSongDataAddr = songDataAddr
        }
        
        // UIを更新するためにメインスレッドで実行
        DispatchQueue.main.async {
            self.fm1AddressHexValue = hexValue
            self.fm1AddressDecimalValue = decimalValue
            self.fm1AddressChanged = hasChanged
            self.fm1PartLoop = loopAddrHex
            self.fm1Length = length
            self.fm1FnumValue = fnumHex
            self.fm1Volume = volume
            
            // 追加情報を設定
            self.songDataAddress = String(format: "0x%04X", songDataAddr)
            self.fm1Position = String(format: "0x%04X", fm1Pos)
            self.keyOnRegisterValue = String(format: "0x%02X", keyOnRegValue)
            self.isChannelActive = isActive
        }
    }
    
    func debugPMDWorkingArea() {
        appendLog("=== PMD88ワークエリアのデバッグ情報 ===")
        
        // PMDのメインワークエリアは1000H〜1FFFHにある
        // PMD88固有のワークエリアは3297H以降にある
        
        // キーオンレジスタの状態を最初に表示
        if cpu.opnaRegisters.count > 0x28 {
            let keyOnReg = cpu.opnaRegisters[0x28]
            appendLog("🎹 キーオンレジスタ(0x28): 0x\(String(format: "%02X", keyOnReg))")
        }
        
        // PMD88固有のワークエリアを表示
        let pmd88WorkAreas = [
            (address: 0x3297, name: "partb", desc: "現在処理中のパート番号"),
            (address: 0x3299, name: "syousetu", desc: "小節カウント"),
            (address: 0x3301, name: "opncount", desc: "OPNカウント"),
            (address: 0x3331, name: "fnum", desc: "演奏中のBLOCK/FNUM値のベースアドレス"),
            (address: 0x3335, name: "volume", desc: "ボリュームのベースアドレス")
        ]
        
        appendLog("\n【PMD88固有ワークエリア】")
        for area in pmd88WorkAreas {
            if area.address < cpu.memory.count {
                let value = cpu.memory[area.address]
                appendLog(String(format: "%04X: %02X - %@ (%@)", area.address, value, area.name, area.desc))
            }
        }
        
        // 各パートのfnumとvolumeを表示
        appendLog("\n【パート情報】")
        for part in 1...9 {  // パート1〜9まで表示
            // パートに対応するオフセットを計算（簡易版）
            let partOffset = part * 32  // 各パートのデータサイズは約32バイト
            
            // fnum（演奏中のBLOCK/FNUM値）
            var fnumStr = "不明"
            if 0x3331 + partOffset + 1 < cpu.memory.count {
                let fnumLow = cpu.memory[0x3331 + partOffset]
                let fnumHigh = cpu.memory[0x3331 + partOffset + 1]
                let fnum = (UInt16(fnumHigh) << 8) | UInt16(fnumLow)
                fnumStr = "0x\(String(format: "%04X", fnum))"
            }
            
            // volume（ボリューム）
            var volumeStr = "不明"
            if 0x3335 + partOffset < cpu.memory.count {
                let volume = cpu.memory[0x3335 + partOffset]
                volumeStr = "\(volume)"
            }
            
            appendLog("パート\(part): fnum=\(fnumStr), volume=\(volumeStr)")
        }
        
        // PMDの主要なフック処理のアドレスを確認
        let pmdhk1Addr = 0xAA5F // 音楽再生メインルーチン
        let pmdhk2Addr = 0xB9CA // ボリューム制御
        let pmdhk3Addr = 0xB70E // リズム音源のキーオン処理
        
        appendLog("PMDフック処理状態:")
        appendLog("- PMDHK1(0xAA5F): PC=\(String(format: "0x%04X", cpu.pc)) (音楽再生メイン)")
        appendLog("- PMDHK2(0xB9CA): ボリューム制御")
        appendLog("- PMDHK3(0xB70E): リズム音源キーオン")
        
        // チャンネル情報を更新
        updateChannelInfo()
        
        // 重要なワークエリアの値を表示
        let workAreas = [
            (address: 0x1000, name: "曲データアドレス（L,H）"),
            (address: 0x1002, name: "音色データアドレス（L,H）"),
            (address: 0x1004, name: "効果音データアドレス（L,H）"),
            (address: 0x1006, name: "VRTC割り込みフック"),
            (address: 0x100A, name: "ステータス"),
            (address: 0x100B, name: "ステータス2"),
            (address: 0x1018, name: "テンポ"),
            (address: 0x1020, name: "FMチャンネル1位置（L,H）"),
            (address: 0x1022, name: "FMチャンネル2位置（L,H）"),
            (address: 0x1024, name: "FMチャンネル3位置（L,H）"),
            (address: 0x1030, name: "SSGチャンネル1位置（L,H）"),
            (address: 0x1032, name: "SSGチャンネル2位置（L,H）"),
            (address: 0x1034, name: "SSGチャンネル3位置（L,H）")
        ]
        
        for area in workAreas {
            let valueL = cpu.memory[area.address]
            let valueH = cpu.memory[area.address + 1]
            let value16 = (Int(valueH) << 8) | Int(valueL)
            appendLog(String(format: "%04X: %02X %02X (%04X) - %@", area.address, valueL, valueH, value16, area.name))
        }
        
        // SSGレジスタの値を表示（状態を詳しく確認）
        appendLog("\n【SSGレジスタの状態】")
        for i in 0..<16 {
            appendLog(String(format: "SSG[%02X]: %02X", i, cpu.opnaRegisters[i]))
        }
        
        // キーオン/オフ状態の詳細解析（FMログは抑制）
        if cpu.opnaRegisters.count > 0x28 {
            // FMエンジンのログは出力しない
        }
        
        // FM音源のレジスタ状態詳細表示は抑制
        // FMエンジンのログは出力しない
        
        // TH101.datのヘッダ情報
        appendLog("\n【TH101.datヘッダ情報】")
        if cpu.memory[0x4C00] >= 0x00 { // PMDの形式チェック
            let title = String(bytes: cpu.memory[0x4C01..<0x4C11], encoding: .shiftJIS) ?? "不明"
            appendLog("タイトル: \(title)")
            
            let memoAddr = (Int(cpu.memory[0x4C12]) << 8) | Int(cpu.memory[0x4C11])
            appendLog(String(format: "メモ位置: %04X", memoAddr))
            
            // PMD88フック処理状態の詳細確認
            appendLog("\n=== PMD88フック処理状態確認 ===")
            appendLog("曲データアドレス（L,H）: 0x\(String(format: "%04X", (Int(cpu.memory[0x1001]) << 8) | Int(cpu.memory[0x1000])))")
            appendLog("チャンネルステータス: 0x\(String(format: "%04X", (Int(cpu.memory[0x1003]) << 8) | Int(cpu.memory[0x1002])))")
            appendLog("FMチャンネル1ワークエリア: 0x\(String(format: "%04X", (Int(cpu.memory[0x1021]) << 8) | Int(cpu.memory[0x1020])))")
            
            // FMキーオン状態の詳細確認は抑制
            // FMエンジンのログは出力しない
            
            // 音色データのアドレスを表示
            let toneAddrFM = (Int(cpu.memory[0x4C14]) << 8) | Int(cpu.memory[0x4C13])
            let toneAddrSSG = (Int(cpu.memory[0x4C16]) << 8) | Int(cpu.memory[0x4C15])
            appendLog(String(format: "FM音色データ位置: %04X", toneAddrFM))
            appendLog(String(format: "SSG音色データ位置: %04X", toneAddrSSG))
            
            // 実際の曲データの先頭バイトを表示
            appendLog("\n【曲データの先頭部分】")
            let songDataStart = 0x4C17 // 通常は0x4C17から曲データが始まる
            var songBytes = ""
            for i in 0..<16 {
                songBytes += String(format: "%02X ", cpu.memory[songDataStart + i])
            }
            appendLog("曲データ先頭: \(songBytes)")
        } else {
            appendLog("TH101.datの形式が不明です（PMDフォーマットではない可能性）")
        }
        
        appendLog("=== デバッグ情報表示終了 ===")
    }
    
    // PMD音楽を再生する関数
    func runPMDMusic() {
        guard !programRunning else {
            appendLog("すでにプログラムは実行中です")
            return
        }
        
        // 音声エンジンの初期化確認
        if audioEngine == nil {
            appendLog("オーディオエンジンを初期化します")
            setupAudio()
        }
        
        // PMD88の実行
        appendLog("PMD88音楽再生を開始します")
        DispatchQueue.main.async {
            self.status = "PMD88実行中..."
            self.programRunning = true
            self.runButtonEnabled = false
            self.stopButtonEnabled = true
            self.resetButtonEnabled = false
        }
        
        // pmd2gプログラムを実行
        shouldStop = false
        
        DispatchQueue.global().async { [weak self] in
            guard let self = self else { return }
            
            // PMD用の初期設定 - ワークエリアの初期化
            self.appendLog("PMDワークエリアの初期化")
            
            // メモリ範囲をクリア (0x1000-0x1FFF)
            for addr in 0x1000...0x1FFF {
                self.cpu.memory[addr] = 0
            }
            
            // 各データのアドレスを設定（PMDGのワークエリア定義に基づく）
            // 曲データアドレス (mmlbuf)
            self.cpu.memory[0x1000] = 0x00 // L
            self.cpu.memory[0x1001] = 0x4C // H (0x4C00 = th101.datのロード位置)
            
            // 音色データアドレス (tondat)
            self.cpu.memory[0x1002] = 0x00 // L
            self.cpu.memory[0x1003] = 0x60 // H (0x6000 = 音色データのロード位置)
            
            // 効果音データアドレス (efftbl)
            self.cpu.memory[0x1004] = 0x00 // L
            self.cpu.memory[0x1005] = 0x60 // H (0x6000 = 効果音データのロード位置)
            
            // SSGの初期設定（全チャンネルをリセット）
            for i in 0..<16 {
                self.cpu.opnaRegisters[i] = 0
            }
            
            // ミキサー設定: 全チャンネルのトーンを有効化
            self.cpu.opnaRegisters[0x07] = 0b00111000 // ビット0-2:トーン有効、ビット3-5:ノイズ無効
            
            // 全チャンネルの音量を設定
            self.cpu.opnaRegisters[0x08] = 0x0F // チャンネルA 音量最大
            self.cpu.opnaRegisters[0x09] = 0x0F // チャンネルB 音量最大
            self.cpu.opnaRegisters[0x0A] = 0x0F // チャンネルC 音量最大
            
            // チャンネル情報を初期化
            self.updateChannelInfo()
            
            // PMDの開始ルーチンを呼び出す（pmd2gの開始アドレス + オフセット）
            self.appendLog("PMD初期化処理を開始")
            self.cpu.pc = 0xAA00 // PMD2の開始アドレス
            self.cpu.h = 0x4C    // 曲データのあるメモリページ
            self.cpu.l = 0x00    // オフセット
            
            // 初期化処理を実行
            var initSteps = 0
            while initSteps < 100_000 && !self.shouldStop {
                _ = self.cpu.step()
                initSteps += 1
                
                // 曲データの読み込みが完了した場所で一旦停止
                if self.cpu.pc == 0xAA03 || initSteps % 10000 == 0 {
                    self.appendLog("PMD初期化実行中...ステップ数: \(initSteps), PC=\(String(format:"0x%04X", self.cpu.pc))")
                }
                
                // PMDの演奏開始後は抜ける
                if initSteps > 10000 {
                    break
                }
            }
            
            self.appendLog("PMD初期化完了: \(initSteps)ステップ実行")
            
            // ワークエリアの状態とSSGレジスタを表示
            self.debugPMDWorkingArea()
            
            // オーディオエンジンを開始
            DispatchQueue.main.async {
                self.audioEngine?.updateState() // 全音源の状態を更新してから
                self.audioEngine?.start()      // オーディオエンジンを開始
                self.appendLog("オーディオエンジン開始 - 全音源初期化完了")
            }
            
            // メインループ実行 - PMDを定期的に処理
            self.appendLog("PMDメインループ実行開始")
            var loopSteps = 0
            var lastUpdateTime = Date()
            
            while !self.shouldStop {
                // しばらくCPUを実行
                for _ in 0..<10000 {
                    _ = self.cpu.step()
                    loopSteps += 1
                }
                
                // 定期的に音源状態を更新
                let now = Date()
                if now.timeIntervalSince(lastUpdateTime) >= 0.05 { // 50msごとに更新
                    lastUpdateTime = now
                    
                    // 全音源の状態をオーディオエンジンに反映
                    DispatchQueue.main.async {
                        self.audioEngine?.updateState() // 全音源（FM、SSG、リズム、ADPCM）の状態を更新
                        
                        // チャンネル情報を更新
                        self.updateChannelInfo()
                        
                        // デバッグ用にキーオンレジスタの値をログに出力
                        if loopSteps % 50000 == 0 {
                            let keyOnReg = self.cpu.opnaRegisters[0x28]
                            self.appendLog("🎹 キーオンレジスタ(0x28): \(String(format: "0x%02X", keyOnReg))")
                            
                            // PMD88ワークエリアの状態を出力
                            self.audioEngine?.fmEngine.printPMD88WorkingAreaStatus(registers: self.cpu.opnaRegisters)
                            
                            // 重要なレジスタの状態を確認
                            self.checkCriticalRegisters()
                        }
                        
                        self.status = "PMD88実行中...（\(loopSteps)ステップ）"
                    }
                    
                    // 定期的にワークエリアとレジスタの状態をログに出力
                    if loopSteps % 100000 == 0 {
                        self.appendLog("実行中ステップ数: \(loopSteps)")
                        self.debugPMDWorkingArea()
                        
                        // FMチャンネルのキーオン状態を確認
                        let keyOnReg = self.cpu.opnaRegisters[0x28]
                        let slotMask = (keyOnReg >> 4) & 0x0F
                        let channelRaw = Int(keyOnReg & 0x07)
                        let isExtended = (keyOnReg & 0x08) != 0
                        let channel = isExtended ? channelRaw + 3 : channelRaw
                        
                        self.appendLog("🎹 FMチャンネル\(channel)のキーオン状態: スロットマスク=\(String(format: "%04b", slotMask))")
                        
                        // PMD88のフック処理の状態を確認
                        self.checkPMD88Hooks()
                    }
                }
                
                // 長時間実行の保護
                if loopSteps > 10_000_000 {
                    self.appendLog("実行上限に達しました")
                    break
                }
            }
            
            self.appendLog("PMD実行完了: \(loopSteps)ステップ実行")
            
            // 最終的なワークエリアの状態を表示
            self.debugPMDWorkingArea()
            
            DispatchQueue.main.async {
                self.programRunning = false
                self.runButtonEnabled = true
                self.stopButtonEnabled = false
                self.resetButtonEnabled = true
                self.status = "PMD実行完了"
            }
        }
    }
}
