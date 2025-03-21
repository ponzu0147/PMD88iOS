//
//  PC88.swift
//  PMD88iOS
//
//  Created by 越川将人 on 2025/03/21.
//

import SwiftUI
import Foundation

class PC88: ObservableObject {
    @Published var status = "Ready"
    @Published var cpu = Z80()
    @Published var programRunning = false
    @Published var lastLog = ""
    @Published var lastDebugLog = ""
    @Published var stepCount = 0
    @Published var lastError = ""
    @Published var runButtonEnabled = true
    @Published var stopButtonEnabled = false
    @Published var resetButtonEnabled = true
    
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
        audioEngine = AudioEngine(z80: cpu)
    }
    
    // テスト用の正弦波を再生する関数
    func playSineWave() {
        print("📱 正弦波再生開始")
        audioEngine?.start()
    }
    
    // テスト用の正弦波を停止する関数
    func stopSineWave() {
        print("📱 正弦波再生停止")
        audioEngine?.stop()
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
        cpu.reset()
        appendLog("CPU初期化完了")
        
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
        cpu.setPortMapping(forBoard: .pc8801_23)
        appendLog("PC-8801-23ボードのポートマッピング設定完了")
        
        // SSGの初期設定（アプリ起動時に音が出るようにテスト設定）
        // チャンネルA周波数設定 (440Hz近辺)
        cpu.opnaRegisters[0x00] = 0x50 // 周波数ローバイト
        cpu.opnaRegisters[0x01] = 0x01 // 周波数ハイバイト
        
        // ミキサー設定: チャンネルAのみトーン有効、他は無効化
        cpu.opnaRegisters[0x07] = 0xFE // チャンネルAのみトーン有効
        
        // チャンネルAの音量を最大に
        cpu.opnaRegisters[0x08] = 0x0F // 音量最大（0-15の値）
        
        appendLog("SSG初期設定: チャンネルA 440Hz、最大音量")
        
        // オーディオエンジンを更新
        audioEngine?.updateSSGState()
        
        appendLog("========== エミュレータ初期化完了 ==========")
        appendDebugInfo()
        
        DispatchQueue.main.async {
            self.status = "初期化完了 - 実行ボタンを押してください"
        }
    }
    
    // エミュレータを停止する関数
    func stop() {
        appendLog("エミュレータ停止コマンド受信")
        shouldStop = true
        cpu.isStopped = true
        appendLog("CPU実行停止フラグ設定")
        DispatchQueue.main.async {
            self.programRunning = false
            self.status = "停止しました"
        }
        appendLog("エミュレータ停止処理完了")
        
        // 音声エンジンの停止
        audioEngine?.stop()
        
        // UI更新
        DispatchQueue.main.async {
            self.runButtonEnabled = true
            self.stopButtonEnabled = false
            self.resetButtonEnabled = true
        }
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
    
    // Z80 CPUを実行する関数
    func run() {
        // 初期化前にチェック
        guard cpu.pc == 0xAA00 else {
            appendLog("⚠️ 初期化が未完了です。実行を中止します。")
            return
        }
        
        // テスト用にSSGの設定を行う（440Hz）
        // チャンネルA周波数設定 (440Hz近辺): F = 3579545/(16*period)
        // period = 3579545/(16*440) ≈ 508
        cpu.opnaRegisters[0x00] = 0x50 // 周波数ローバイト
        cpu.opnaRegisters[0x01] = 0x01 // 周波数ハイバイト (01h << 8 | 50h = 0x0150 = 336)
        
        // ミキサー設定: チャンネルAのみトーン有効、他は無効化
        cpu.opnaRegisters[0x07] = 0xFE // チャンネルAのみトーン有効
        
        // チャンネルAの音量を最大に
        cpu.opnaRegisters[0x08] = 0x0F // 音量最大（0-15の値）
        
        appendLog("テスト用OPNAレジスタ設定：SSGチャンネルA 440Hz トーン")
        
        // SSGの状態を更新
        audioEngine?.updateSSGState()
        
        // SSGの現在の状態を出力
        appendDebugInfo()
        
        // デバッグモード有効化
        cpu.debugMode = true
        appendLog("デバッグモード有効化")
        appendLog("開始時のPC=\(String(format: "0x%04X", cpu.pc))")
        appendLog("初期ポート出力カウンター: \(cpu.outPortCounter)")
        
        // 実行開始時間を記録
        let startTime = Date.timeIntervalSinceReferenceDate
        appendLog("実行開始時間: \(startTime)")
        
        // オーディオエンジンを開始
        audioEngine?.start()
        
        // 実行状態を更新（メインスレッドで行う）
        DispatchQueue.main.async {
            self.programRunning = true
            self.runButtonEnabled = false
            self.stopButtonEnabled = true
            self.resetButtonEnabled = false
            self.status = "実行中..."
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            appendLog("バックグラウンドスレッドで実行開始")
            appendLog("メインループ開始")
            
            // メインループ
            var stepCount = 0
            let lastUpdateTime = Date.timeIntervalSinceReferenceDate
            var lastSSGUpdateTime = lastUpdateTime
            var isRunning = true
            
            while isRunning && !self.cpu.isStopped {
                // CPU命令を1ステップ実行
                _ = self.cpu.step()
                stepCount += 1
                
                // メインスレッドから停止命令をチェック
                DispatchQueue.main.sync {
                    isRunning = self.programRunning
                }
                
                // 1000ステップごとにUI更新とステータスチェック
                if stepCount % 1000 == 0 {
                    let currentTime = Date.timeIntervalSinceReferenceDate
                    
                    // SSGの状態更新（より頻繁に）
                    if currentTime - lastSSGUpdateTime > 0.005 { // 5ミリ秒ごとに更新
                        lastSSGUpdateTime = currentTime
                        audioEngine?.updateSSGState()
                    }
                    
                    // ログ出力（最初の10回だけ）
                    if stepCount <= 10000 {
                        self.appendLog("ステップ \(stepCount): PC=\(String(format: "0x%04X", self.cpu.pc)) 命令=\(String(format: "0x%02X", self.cpu.memory[self.cpu.pc]))")
                        
                        // ポート出力カウンターを確認
                        if stepCount == 1000 {
                            self.appendLog("✅ ポート出力検出: カウンター=\(self.cpu.outPortCounter)")
                        }
                    }
                    
                    // 10000ステップごとに実行時間を確認
                    if stepCount % 10000 == 0 {
                        let elapsed = currentTime - startTime
                        self.appendLog("実行経過: \(stepCount)ステップ, \(String(format: "%.2f", elapsed))秒")
                        
                        // UI更新
                        DispatchQueue.main.async {
                            self.stepCount = stepCount
                            self.status = "\(stepCount)ステップ実行, \(String(format: "%.2f", elapsed))秒"
                        }
                        
                        // SSGの状態確認と更新を強制
                        if stepCount % 50000 == 0 {
                            self.appendLog("==== \(50000)ステップ経過 チェックポイント ====")
                            self.appendLog("ステップ数: \(stepCount)")
                            self.appendLog("ポート出力カウンター: \(self.cpu.outPortCounter)")
                            self.appendLog("✅ 正常動作中: ポート出力数=\(self.cpu.outPortCounter)")
                            
                            // OPNA状態確認
                            var ssgBaseInfo = "  【表FM】 SSG基本:"
                            ssgBaseInfo += "[00]=\(String(format: "%02X", self.cpu.opnaRegisters[0x00])) "
                            ssgBaseInfo += "[01]=\(String(format: "%02X", self.cpu.opnaRegisters[0x01])) "
                            ssgBaseInfo += "[07]=\(String(format: "%02X", self.cpu.opnaRegisters[0x07])) "
                            ssgBaseInfo += "[08]=\(String(format: "%02X", self.cpu.opnaRegisters[0x08])),"
                            self.appendLog("OPNAレジスタ状態:")
                            self.appendLog(ssgBaseInfo)
                            
                            // ポートマッピング確認
                            var mapInfo = "ポートマッピング: "
                            for (port, mapped) in self.cpu.portMap where port >= 0x44 && port <= 0x47 {
                                mapInfo += "[\(String(format: "%02X", port))→\(String(format: "%02X", mapped))], "
                            }
                            self.appendLog(mapInfo)
                            
                            self.appendLog("現在のポートベース: \(String(format: "%02X", self.cpu.currentPortBase))")
                            
                            // CPU状態表示
                            self.appendDebugInfo()
                        }
                    }
                    
                    // CPUに余裕を持たせる
                    usleep(100) // 0.1ミリ秒休止
                }
            }
            
            // 終了処理
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.programRunning = false
                self.runButtonEnabled = true
                self.stopButtonEnabled = false
                self.resetButtonEnabled = true
                
                // 実行時間計測
                let elapsed = Date.timeIntervalSinceReferenceDate - startTime
                self.appendLog("========== エミュレータ実行終了 ==========")
                self.appendLog("実行時間: \(String(format: "%.2f", elapsed))秒")
                self.status = "実行終了: \(String(format: "%.2f", elapsed))秒"
                
                // 停止理由
                if self.cpu.isStopped {
                    self.appendLog("停止理由: CPU停止フラグON")
                } else {
                    self.appendLog("停止理由: 外部からの停止要求")
                }
            }
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
}
