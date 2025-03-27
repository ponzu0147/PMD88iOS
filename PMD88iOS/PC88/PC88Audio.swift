//
//  PC88Audio.swift
//  PMD88iOS
//
//  Created by 越川将人 on 2025/03/23.
//

import Foundation
import AVFoundation
import Combine

// MARK: - PC88オーディオ機能
class PC88Audio {
    // 親クラスへの参照
    private weak var pc88: PC88Core?
    
    // オーディオエンジン
    private var audioEngine: AudioEngine?
    
    // チャンネル情報
    private var fmChannelInfo: [Int: ChannelInfo] = [:]
    private var ssgChannelInfo: [Int: ChannelInfo] = [:]
    private var isRhythmActive: Bool = false
    private var isADPCMActive: Bool = false
    
    // PublisherとSubject
    private let fmChannelSubject = CurrentValueSubject<[Int: ChannelInfo], Never>([:])
    private let ssgChannelSubject = CurrentValueSubject<[Int: ChannelInfo], Never>([:])
    private let rhythmActiveSubject = CurrentValueSubject<Bool, Never>(false)
    private let adpcmActiveSubject = CurrentValueSubject<Bool, Never>(false)
    
    // 公開するPublisher
    var fmChannelPublisher: AnyPublisher<[Int: ChannelInfo], Never> {
        return fmChannelSubject.eraseToAnyPublisher()
    }
    
    var ssgChannelPublisher: AnyPublisher<[Int: ChannelInfo], Never> {
        return ssgChannelSubject.eraseToAnyPublisher()
    }
    
    var rhythmActivePublisher: AnyPublisher<Bool, Never> {
        return rhythmActiveSubject.eraseToAnyPublisher()
    }
    
    var adpcmActivePublisher: AnyPublisher<Bool, Never> {
        return adpcmActiveSubject.eraseToAnyPublisher()
    }
    
    // 初期化
    init(pc88: PC88Core) {
        self.pc88 = pc88
    }
    
    // オーディオエンジンのセットアップ
    func setupAudio() {
        guard let pc88 = pc88 else { return }
        
        // オーディオエンジンの初期化
        audioEngine = AudioEngine(z80: pc88.cpu)
        
        // オーディオセッションの設定
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
            pc88.debug.appendLog("オーディオセッション初期化成功")
        } catch {
            pc88.debug.appendLog("オーディオセッション初期化エラー: \(error.localizedDescription)")
        }
    }
    
    // オーディオエンジンの開始
    func startAudio() {
        audioEngine?.start()
    }
    
    // オーディオエンジンの停止
    func stopAudio() {
        audioEngine?.stop()
    }
    
    // オーディオエンジンの状態更新
    func updateAudioState() {
        audioEngine?.updateState()
    }
    
    // チャンネル情報の更新
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
        guard let pc88 = pc88 else { return }
        
        // FM音源チャンネル情報の更新（FM1〜FM6）
        for i in 0..<6 {
            let baseAddr = PMDWorkArea.fmChannelBase + (i * PMDWorkArea.fmChannelSize)
            
            // アドレス情報（演奏中のデータポインタ）
            let addrL = pc88.cpu.memory[baseAddr]
            let addrH = pc88.cpu.memory[baseAddr + 1]
            let address = UInt16(addrH) << 8 | UInt16(addrL)
            
            // 音色番号
            let toneNumber = pc88.cpu.memory[baseAddr + 0x02]
            
            // 音量
            let volume = pc88.cpu.memory[baseAddr + 0x04]
            
            // キーオン状態の判定を改善
            // PMD88ワーキングエリアから直接チャンネルの状態を取得
            
            // 1. チャンネルの状態フラグを取得
            let statusFlag = pc88.cpu.memory[baseAddr + 0x16] // チャンネル状態フラグ
            let isChannelActive = (statusFlag & 0x80) != 0 // ビット7がアクティブフラグ
            
            // 2. キーオンレジスタの確認
            // レジスタの仕様: 上位4ビットがチャンネル番号、下位4ビットがスロットとオペレータ
            let keyOnRegister = pc88.cpu.opnaRegisters[OPNARegister.keyOnOff]
            
            // チャンネル番号に応じたマスクを生成
            let slotMask: UInt8 = 0x0F // 下位4ビットがスロットとオペレータ
            let channelMask: UInt8
            if i < 3 { // FM1-3
                channelMask = UInt8(i << 4) // チャンネル番号を0-2に設定
            } else { // FM4-6
                channelMask = UInt8((i - 3) << 4) | 0x04 // チャンネル番号を0-2に設定、スロットフラグを設定
            }
            
            // キーオンレジスタの値を確認
            let keyOnValue = keyOnRegister & slotMask
            let isKeyOn = keyOnValue != 0 && (keyOnRegister & 0xF0) == channelMask
            
            // 3. その他の条件を確認
            let hasValidAddress = address != 0
            let hasVolume = volume > 0
            
            // 4. PMDワークエリアの状態も確認
            // PMD88のワーキングエリアからチャンネルのアクティブ状態を確認
            let pmdWorkAreaBase = 0x0100 // PMD88ワーキングエリアのベースアドレス
            let fmActiveFlags = pc88.cpu.memory[pmdWorkAreaBase + 0x0B] // FMチャンネルのアクティブフラグ
            let isFMActiveInPMD = (fmActiveFlags & (1 << i)) != 0
            
            // 上記の条件を組み合わせて判定
            // チャンネルがアクティブか、キーオンされているか、PMDワークエリアでアクティブな場合
            let isPlaying = isChannelActive || isKeyOn || isFMActiveInPMD || (hasValidAddress && hasVolume)
            
            // デバッグ出力
            if i == 0 || i == 2 { // FM1とFM3の状態をデバッグ出力
                print("FM\(i+1) - KeyOn: \(isKeyOn), Active: \(isChannelActive), PMDActive: \(isFMActiveInPMD), Address: \(address), Volume: \(volume), IsPlaying: \(isPlaying)")
            }
            
            // 音名の計算
            let fnum1Addr = 0xA0 + i
            let fnum2Addr = 0xA4 + i
            let fnum1 = pc88.cpu.opnaRegisters[fnum1Addr]
            let fnum2 = pc88.cpu.opnaRegisters[fnum2Addr]
            let fnum = UInt16(fnum2 & 0x07) << 8 | UInt16(fnum1)
            let block = (fnum2 >> 3) & 0x07
            let note = calculateNoteName(fnum: fnum, block: block)
            
            // チャンネル情報を更新
            var info = ChannelInfo()
            info.isActive = isPlaying // 再生中かどうかで活性化状態を判定
            info.playingAddress = Int(address)
            info.toneNumber = Int(toneNumber)
            info.volume = Int(volume)
            info.type = "FM"
            info.number = i + 1
            info.address = Int(address)
            info.note = note
            info.instrument = Int(toneNumber)
            info.isPlaying = isPlaying
            
            fmChannelInfo[i] = info
        }
        
        // SSG音源チャンネル情報の更新（SSG1〜SSG3）
        for i in 0..<3 {
            let baseAddr = PMDWorkArea.ssgChannelBase + (i * PMDWorkArea.ssgChannelSize)
            
            // アドレス情報（演奏中のデータポインタ）
            let addrL = pc88.cpu.memory[baseAddr]
            let addrH = pc88.cpu.memory[baseAddr + 1]
            let address = UInt16(addrH) << 8 | UInt16(addrL)
            
            // 音色番号
            let toneNumber = pc88.cpu.memory[baseAddr + 0x02]
            
            // 音量
            let volume = pc88.cpu.memory[baseAddr + 0x04]
            
            // 周波数レジスタから音名を計算
            let freqLAddr = 0x00 + (i * 2)
            let freqHAddr = 0x01 + (i * 2)
            let freqL = pc88.cpu.opnaRegisters[freqLAddr]
            let freqH = pc88.cpu.opnaRegisters[freqHAddr]
            let freq = UInt16(freqH) << 8 | UInt16(freqL)
            let note = calculateSSGNoteName(freq: freq)
            
            // 音量レジスタとPMDワークエリアから演奏状態を判定
            let volumeReg = pc88.cpu.opnaRegisters[OPNARegister.ssgVolumeBase + i]
            
            // PMDワークエリアのSSGチャンネル状態を取得
            let statusOffset = PMDWorkArea.ssgStatusBase + i
            let ssgStatus = pc88.cpu.memory[statusOffset]
            
            // 演奏状態の判定ロジックを改善
            // 1. 音量が0より大きい
            // 2. ワークエリアのステータスがアクティブを示している
            // 3. 演奏アドレスが有効
            let isPlaying = (volumeReg < 15) && (ssgStatus & 0x01) != 0 && address != 0
            
            // チャンネル情報を更新
            var info = ChannelInfo()
            info.isActive = address != 0
            info.playingAddress = Int(address)
            info.toneNumber = Int(toneNumber)
            info.volume = Int(volume)
            info.type = "SSG"
            info.number = i + 1
            info.address = Int(address)
            info.note = note
            info.instrument = Int(toneNumber)
            info.isPlaying = isPlaying
            
            ssgChannelInfo[i] = info
        }
        
        // リズム音源の状態を更新
        let rhythmStatus = pc88.cpu.memory[PMDWorkArea.rhythmStatusAddr]
        isRhythmActive = rhythmStatus != 0
        
        // ADPCM音源の状態を更新
        let adpcmStatus = pc88.cpu.memory[PMDWorkArea.adpcmStatusAddr]
        isADPCMActive = adpcmStatus != 0
        
        // PublisherとSubjectを更新
        fmChannelSubject.send(fmChannelInfo)
        ssgChannelSubject.send(ssgChannelInfo)
        rhythmActiveSubject.send(isRhythmActive)
        adpcmActiveSubject.send(isADPCMActive)
    }
    
    // FM音源の音名計算
    private func calculateNoteName(fnum: UInt16, block: UInt8) -> String {
        // FNUMから音名を計算
        // FNUM: 0〜2047の範囲で、1オクターブを2^(1/12)の12等分した値
        // Block: 0〜7の範囲で、オクターブを表す
        
        if fnum == 0 {
            return "---"
        }
        
        // 音名の配列（C, C#, D, D#, E, F, F#, G, G#, A, A#, B）
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        
        // FNUMから音名のインデックスを計算
        // 基準値: FNUM=617でA4（440Hz）、Block=4
        let fnumLog = log(Double(fnum) / 617.0) / log(2.0)
        let noteIndex = (fnumLog * 12.0).rounded()
        
        // 音名とオクターブを組み合わせる
        let noteNameIndex = (noteIndex >= 0 ? Int(noteIndex) % 12 : (12 + Int(noteIndex) % 12) % 12)
        let octave = Int(block)
        
        return "\(noteNames[noteNameIndex])\(octave)"
    }
    
    // SSG音源の音名計算
    private func calculateSSGNoteName(freq: UInt16) -> String {
        if freq == 0 {
            return "---"
        }
        
        // 音名の配列（C, C#, D, D#, E, F, F#, G, G#, A, A#, B）
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        
        // SSGの周波数計算式: f = 1.79MHz / (16 * n)
        // n: レジスタ値（0〜4095）
        // 基準値: n=3822でA3（220Hz）
        
        let freqLog = log(Double(3822) / Double(freq)) / log(2.0)
        let noteIndex = (freqLog * 12.0).rounded()
        
        // 音名とオクターブを組み合わせる
        let noteNameIndex = (noteIndex >= 0 ? Int(noteIndex) % 12 : (12 + Int(noteIndex) % 12) % 12)
        let octave = 3 + Int(noteIndex) / 12
        
        return "\(noteNames[noteNameIndex])\(octave)"
    }
    
    // すべての音源を停止
    func stopAllChannels() {
        guard let pc88 = pc88 else { return }
        
        // FM音源のキーオフ処理
        for ch in 0..<6 {
            let fmKeyOffRegister: UInt8 = UInt8(OPNARegister.keyOnOff)
            let fmKeyOffValue: UInt8 = UInt8(ch) // チャンネル番号に応じた値
            pc88.portOut(port: 0xA0, value: fmKeyOffRegister)
            pc88.portOut(port: 0xA1, value: fmKeyOffValue)
        }
        
        // SSG音量ゼロ設定
        for ch in 0..<3 {
            let ssgVolumeRegister: UInt8 = UInt8(OPNARegister.ssgVolumeBase + ch)
            pc88.portOut(port: 0xA0, value: ssgVolumeRegister)
            pc88.portOut(port: 0xA1, value: UInt8(0)) // 音量ゼロ
        }
        
        // リズム音源停止
        pc88.portOut(port: 0xA0, value: UInt8(OPNARegister.rhythmKeyOnOff))
        pc88.portOut(port: 0xA1, value: UInt8(0))
        
        // ADPCM停止
        pc88.portOut(port: 0xA0, value: UInt8(OPNARegister.adpcmControl))
        pc88.portOut(port: 0xA1, value: UInt8(0))
    }
    
    // チャンネル情報の取得
    func getFMChannelInfo() -> [Int: ChannelInfo] {
        return fmChannelInfo
    }
    
    func getSSGChannelInfo() -> [Int: ChannelInfo] {
        return ssgChannelInfo
    }
    
    func isRhythmChannelActive() -> Bool {
        return isRhythmActive
    }
    
    func isADPCMChannelActive() -> Bool {
        return isADPCMActive
    }
    
    // FM音源のキーオン状態を確認し、必要に応じて強制的にキーオンする
    func checkFMKeyOnStatus() {
        guard let pc88 = pc88 else { return }
        
        // キーオンレジスタの値を取得
        let keyOnReg = pc88.cpu.opnaRegisters[OPNARegister.keyOnOff]
        
        // デバッグ出力
        pc88.debug.appendLog("キーオン状態確認: レジスタ0x28=0x\(String(format: "%02X", keyOnReg))")
        
        // チャンネルの状態を確認するフラグ
        var hasActiveChannels = false
        
        // PMDワークエリアからFMチャンネルの状態を取得
        for ch in 0..<6 {
            let statusOffset = PMDWorkArea.fmStatusBase + ch
            let fmStatus = pc88.cpu.memory[statusOffset]
            
            // チャンネルがアクティブな場合
            if (fmStatus & 0x01) != 0 {
                hasActiveChannels = true
                let chBit = ch % 3
                let group = ch / 3
                
                // チャンネルのキーオンビットを確認
                let groupOffset = group * 4
                // 現在のキーオン状態を確認
                let currentKeyOnBits = (keyOnReg & 0xF0) >> 4
                let isKeyOn = (keyOnReg & 0x0F) != 0 && currentKeyOnBits == chBit + groupOffset
                
                // キーオン状態をデバッグ出力
                pc88.debug.appendLog("  - キーオンレジスタ: 0x\(String(format: "%02X", keyOnReg)), キーオン状態: \(isKeyOn ? "オン" : "オフ")")
                
                // 必要なチャンネルのキーオン状態を強制的に設定
                let newKeyOnValue = 0xF0 | (chBit + groupOffset)
                pc88.debug.appendLog("チャンネル\(ch)はアクティブです (ステータス: 0x\(String(format: "%02X", fmStatus)))")
                
                // レジスタに書き込み
                pc88.cpu.opnaRegisters[OPNARegister.keyOnOff] = UInt8(newKeyOnValue)
                
                // オーディオエンジンにも反映
                if let audioEngine = audioEngine {
                    audioEngine.fmEngine.keyOn(channel: ch, slots: 0x0F) // 全スロットをオン
                    
                    // 各チャンネルのパラメータを確認
                    let fnum = (Int(pc88.cpu.opnaRegisters[0xA4 + ch]) & 0x3F) << 8 | Int(pc88.cpu.opnaRegisters[0xA0 + ch])
                    let block = (pc88.cpu.opnaRegisters[0xA4 + ch] >> 3) & 0x07
                    let algorithm = pc88.cpu.opnaRegisters[0xB0 + ch] & 0x07
                    
                    pc88.debug.appendLog("  - パラメータ: FNUM=\(fnum), BLOCK=\(block), ALG=\(algorithm)")
                    
                    // エンジンにパラメータを設定
                    audioEngine.fmEngine.setFMParameters(channel: ch, fnum: fnum, block: Int(block), algorithm: Int(algorithm))
                }
            }
        }
        
        // アクティブなチャンネルがない場合は強制的にFM5とFM6をオンにする
        if !hasActiveChannels {
            pc88.debug.appendLog("アクティブなチャンネルが見つからないため、FM5とFM6を強制的にオンにします")
            
            // FM5とFM6をオンにする
            for ch in [4, 5] {
                let chBit = ch % 3
                let group = ch / 3
                let newKeyOnValue = 0xF0 | (chBit + group * 4)
                
                // レジスタに書き込み
                pc88.cpu.opnaRegisters[OPNARegister.keyOnOff] = UInt8(newKeyOnValue)
                
                // オーディオエンジンにも反映
                if let audioEngine = audioEngine {
                    audioEngine.fmEngine.keyOn(channel: ch, slots: 0x0F) // 全スロットをオン
                    
                    // テストパラメータを設定
                    let fnum = ch == 4 ? 653 : 617  // B0とB1の音程に対応するFNUM値
                    let block = ch == 4 ? 0 : 1     // FM5はB0、FM6はB1
                    let algorithm = 0               // アルゴリズムは0
                    
                    // エンジンにパラメータを設定
                    audioEngine.fmEngine.setFMParameters(channel: ch, fnum: fnum, block: block, algorithm: algorithm)
                }
            }
        }
        
        // FM音源のサンプル値をモニタリング
        if let audioEngine = audioEngine {
            let samples = audioEngine.fmEngine.getLastSamples(count: 10)
            var nonZeroCount = 0
            
            pc88.debug.appendLog("🎵 FM音源サンプル値モニタリング:")
            for (i, sample) in samples.enumerated() {
                pc88.debug.appendLog("  サンプル\(i): \(sample)")
                if abs(sample) > 0.01 {
                    nonZeroCount += 1
                }
            }
            
            pc88.debug.appendLog("  非ゼロサンプル数: \(nonZeroCount)/\(samples.count)")
            
            if nonZeroCount == 0 {
                pc88.debug.appendLog("⚠️ すべてのサンプルがゼロです - FMエンジンが正しく音を生成していません")
                
                // テスト音を生成
                pc88.debug.appendLog("🎵 テスト音声を設定します")
                setupTestTone()
            }
        }
    }
    
    // テスト音を設定
    private func setupTestTone() {
        guard let pc88 = pc88, let audioEngine = audioEngine else { return }
        
        // チャンネル0とチャンネル4にテスト音を設定
        let channels = [0, 4]  // FM1とFM5にテスト音を設定
        
        for ch in channels {
            // オペレータ設定
            for op in 0..<4 {
                let opBase = ch < 3 ? 0 : 0x100  // FM4-6はレジスタオフセットが異なる
                let chOffset = ch % 3
                
                // DT/ML (マルチプル値を増やす)
                pc88.cpu.opnaRegisters[opBase + 0x30 + chOffset + op * 4] = op == 3 ? 5 : 1
                
                // TL (オペレータ4だけ音量を上げる)
                pc88.cpu.opnaRegisters[opBase + 0x40 + chOffset + op * 4] = op == 3 ? 16 : 127
                
                // KS/AR
                pc88.cpu.opnaRegisters[opBase + 0x50 + chOffset + op * 4] = 31  // 最速アタック
                
                // DR
                pc88.cpu.opnaRegisters[opBase + 0x60 + chOffset + op * 4] = 0
                
                // SR
                pc88.cpu.opnaRegisters[opBase + 0x70 + chOffset + op * 4] = 0
                
                // SL/RR
                pc88.cpu.opnaRegisters[opBase + 0x80 + chOffset + op * 4] = 0
            }
        }
        
        // FB/ALG
        pc88.cpu.opnaRegisters[0xB0] = 7  // ALG=7 (単純な正弦波)
        
        // 周波数設定 (C4音 = 261.6Hz)
        pc88.cpu.opnaRegisters[0xA4] = 0x24  // BLOCK=4
        pc88.cpu.opnaRegisters[0xA0] = 0x71  // FNUM=0x271 (C4音)
        
        // キーオン
        pc88.cpu.opnaRegisters[OPNARegister.keyOnOff] = 0xF0  // すべてのオペレータをオン
        
        // オーディオエンジンに反映
        audioEngine.updateFMRegisters(registers: pc88.cpu.opnaRegisters)
        
        // 各チャンネルをキーオン
        for ch in channels {
            audioEngine.fmEngine.keyOn(channel: ch, slots: 0x0F)
            pc88.debug.appendLog("🎵 テスト音設定完了: CH\(ch) ALG=7 FB=0, C4音")
        }
    }
}
