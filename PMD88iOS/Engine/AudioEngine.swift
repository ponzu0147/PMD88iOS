import Foundation
import AVFoundation

/// PMD88用オーディオエンジン
/// YM2608/OPNA音源をエミュレートし、SSG、FM、RHYTHM、ADPCMの各音源を統合管理
class AudioEngine {
    private let engine = AVAudioEngine()
    private var playerNode: AVAudioPlayerNode?
    private var isRunning = false
    
    // Z80エミュレータへの参照
    private weak var z80: PMD88iOS.Z80?
    
    // 各音源エンジン
    var ssgEngine: SSGEngine!
    var fmEngine: FMEngine!
    var rhythmEngine: RhythmEngine!
    var adpcmEngine: ADPCMEngine!
    
    // 音声パラメータ
    private let sampleRate: Float = 44100.0
    private let bufferDuration: Float = 0.05  // 50ms
    private let cpuClock: Float = 3993600.0   // PC-8801の3.9936MHz
    private var bufferQueue: [AVAudioPCMBuffer] = []
    private let bufferCount = 3
    
    // 初期化
    init(z80: PMD88iOS.Z80? = nil) {
        self.z80 = z80
        
        // 各音源エンジンの初期化
        ssgEngine = SSGEngine(sampleRate: sampleRate, cpuClock: cpuClock)
        fmEngine = FMEngine(sampleRate: 44100.0, fmClock: 7987200.0)
        rhythmEngine = RhythmEngine(sampleRate: sampleRate)
        adpcmEngine = ADPCMEngine(sampleRate: sampleRate, adpcmClock: cpuClock)
        
        setupEngine()
        print("🎵 AudioEngine初期化完了")
    }
    
    // Z80エミュレータを設定
    func setZ80(_ z80: Z80) {
        self.z80 = z80
        print("🎵 Z80エミュレータ接続完了")
    }
    
    // オーディオエンジンのセットアップ
    private func setupEngine() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
            print("🔊 AudioSession設定完了")
        } catch {
            print("❌ AudioSessionエラー: \(error)")
        }
    }
    
    // オーディオバッファの生成
    private func generateAudioBuffer() -> AVAudioPCMBuffer? {
        let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 2)!  // ステレオ出力
        let frameCount = AVAudioFrameCount(sampleRate * bufferDuration)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            print("❌ PCMバッファの作成に失敗")
            return nil
        }
        
        guard let leftChannelData = buffer.floatChannelData?[0],
              let rightChannelData = buffer.floatChannelData?[1] else {
            print("❌ チャンネルデータへのアクセス失敗")
            return nil
        }
        
        let samples = Int(frameCount)
        let timeStep: Float = 1.0 / sampleRate
        
        // デバッグ情報出力
        print("🎵 バッファ生成開始: \(samples)サンプル, タイムステップ: \(timeStep)")
        
        // テスト用に直接正弦波を生成するフラグ
        let useDirectSineWave = false
        print("🎵 useDirectSineWave設定: \(useDirectSineWave)")
        
        var maxAmplitude: Float = 0.0
        
        if useDirectSineWave {
            print("🎵 テスト用正弦波生成パスを実行")
            // テスト用に440Hzの正弦波を生成
            let frequency: Float = 440.0
            let amplitude: Float = 0.5
            
            for i in 0..<samples {
                let t = Float(i) * timeStep
                let sineValue = sin(2.0 * Float.pi * frequency * t) * amplitude
                
                leftChannelData[i] = sineValue
                rightChannelData[i] = sineValue
                
                // 最大振幅を記録
                maxAmplitude = max(maxAmplitude, abs(sineValue))
            }
            
            print("🎵 テスト用正弦波生成完了")
        } else {
            print("🎵 実際の音源エンジン使用パスを実行")
            // 通常の音源エンジンを使用
            for i in 0..<samples {
                // 各音源からサンプルを生成
                let ssgSample = ssgEngine.generateSample(timeStep)
                let fmSample = fmEngine.generateSample(timeStep)
                let rhythmSample = rhythmEngine.generateSample()
                let adpcmSample = adpcmEngine.generateSample(timeStep)
                
                // 音量を大幅に増加させる
                let leftSample = (ssgSample * 1.0 + fmSample * 2.0 + rhythmSample * 0.8 + adpcmSample * 0.5) * 8.0
                let rightSample = (ssgSample * 1.0 + fmSample * 2.0 + rhythmSample * 0.8 + adpcmSample * 0.5) * 8.0
                
                // 最大振幅を記録
                maxAmplitude = max(maxAmplitude, abs(leftSample))
                
                // デバッグ出力（最初の数サンプルのみ）
                if i < 10 {
                    print("Sample \(i): SSG=\(ssgSample), FM=\(fmSample), Rhythm=\(rhythmSample), ADPCM=\(adpcmSample)")
                }
                
                // クリッピング
                leftChannelData[i] = max(min(leftSample, 1.0), -1.0)
                rightChannelData[i] = max(min(rightSample, 1.0), -1.0)
            }
        }
        
        // 最大振幅を出力
        print("🔊 生成されたバッファの最大振幅: \(maxAmplitude)")
        
        // バッファ生成完了
        buffer.frameLength = frameCount
        return buffer
    }
    
    // FMチャンネルの設定を改善
    private func initializeFMTone() {
        guard let z80 = z80 else { return }
        
        print("🎹 FMチャンネル初期化設定")
        
        // 全FMチャンネルをリセット
        for ch in 0..<6 {
            // キーオフ
            z80.opnaRegisters[0x28] = UInt8(ch)
        }
        
        // チャンネル1の基本パラメータ設定（テスト用）
        let ch = 1  // チャンネル1を使用
        
        // 音色設定（各オペレータのパラメータ）
        // DT/ML (Detune/Multiple)
        z80.opnaRegisters[0x30 + ch] = 0x01  // OP1: DT=0, ML=1
        z80.opnaRegisters[0x38 + ch] = 0x01  // OP2: DT=0, ML=1
        z80.opnaRegisters[0x34 + ch] = 0x01  // OP3: DT=0, ML=1
        z80.opnaRegisters[0x3C + ch] = 0x01  // OP4: DT=0, ML=1
        
        // TL (Total Level) - 音量設定を改善
        z80.opnaRegisters[0x40 + ch] = 0x20  // OP1: TL=32 (より大きな音に)
        z80.opnaRegisters[0x48 + ch] = 0x20  // OP2: TL=32
        z80.opnaRegisters[0x44 + ch] = 0x20  // OP3: TL=32
        z80.opnaRegisters[0x4C + ch] = 0x00  // OP4: TL=0 (最大音量)
        
        // KS/AR (Key Scale/Attack Rate)
        z80.opnaRegisters[0x50 + ch] = 0x1F  // OP1: KS=0, AR=31
        z80.opnaRegisters[0x58 + ch] = 0x1F  // OP2: KS=0, AR=31
        z80.opnaRegisters[0x54 + ch] = 0x1F  // OP3: KS=0, AR=31
        z80.opnaRegisters[0x5C + ch] = 0x1F  // OP4: KS=0, AR=31
        
        // DR (Decay Rate)
        z80.opnaRegisters[0x60 + ch] = 0x0A  // OP1: DR=10 (より速い減衰)
        z80.opnaRegisters[0x68 + ch] = 0x0A  // OP2: DR=10
        z80.opnaRegisters[0x64 + ch] = 0x0A  // OP3: DR=10
        z80.opnaRegisters[0x6C + ch] = 0x0A  // OP4: DR=10
        
        // SR (Sustain Rate)
        z80.opnaRegisters[0x70 + ch] = 0x05  // OP1: SR=5
        z80.opnaRegisters[0x78 + ch] = 0x05  // OP2: SR=5
        z80.opnaRegisters[0x74 + ch] = 0x05  // OP3: SR=5
        z80.opnaRegisters[0x7C + ch] = 0x07  // OP4: SR=7
        
        // SL/RR (Sustain Level/Release Rate)
        z80.opnaRegisters[0x80 + ch] = 0x0A  // OP1: SL=0, RR=10
        z80.opnaRegisters[0x88 + ch] = 0x0A  // OP2: SL=0, RR=10
        z80.opnaRegisters[0x84 + ch] = 0x0A  // OP3: SL=0, RR=10
        z80.opnaRegisters[0x8C + ch] = 0x0F  // OP4: SL=0, RR=15
        
        // アルゴリズムとフィードバック
        z80.opnaRegisters[0xB0 + ch] = 0x37  // ALG=7, FB=3
        
        // 周波数設定（A=440Hz、BLOCK=4）
        let fnum = 0x157  // A4の周波数数値
        let block = 4     // オクターブ
        
        z80.opnaRegisters[0xA4 + ch] = UInt8((block << 3) | (fnum >> 8))  // FNUM上位ビット + BLOCK
        z80.opnaRegisters[0xA0 + ch] = UInt8(fnum & 0xFF)                 // FNUM下位ビット
        
        // キーオンレジスタ設定 - 全オペレータをON
        let slotMask: UInt8 = 0xF0  // 全スロットON (bit 4-7)
        let channelNum: UInt8 = UInt8(ch)  // チャンネル番号を UInt8 に変換
        z80.opnaRegisters[0x28] = slotMask | channelNum  // キーオンレジスタに書き込み
        
        print("🎹 FMチャンネル\(ch)の初期化完了 - FNUM=\(fnum), BLOCK=\(block), ALG=7, FB=3")
        print("🎹 各オペレータのTL値: OP1=\(z80.opnaRegisters[0x40 + ch]), OP2=\(z80.opnaRegisters[0x48 + ch]), OP3=\(z80.opnaRegisters[0x44 + ch]), OP4=\(z80.opnaRegisters[0x4C + ch])")
        
        // キーオンレジスタの詳細解析
        analyzeKeyOnRegister()
    }
    
    // キーオンレジスタ（0x28）の詳細な解析と実装
    private func analyzeKeyOnRegister() {
        guard let z80 = z80 else { return }
        
        let keyOnReg = z80.opnaRegisters[0x28]
        print("🔑 キーオンレジスタ詳細解析:")
        print("  値: 0x\(String(format: "%02X", keyOnReg))")
        
        // キーオンビットの解析をより詳細に
        let slotMask = (keyOnReg >> 4) & 0x0F  // bit4-7がスロットマスク
        let channelRaw = keyOnReg & 0x07       // bit0-2がチャンネル番号
        let channelGroup = (keyOnReg & 0x04) >> 2 // チャンネルグループ
        
        // チャンネル番号の正確な解釈
        let actualChannel = channelGroup == 0 ? channelRaw : channelRaw + 3
        
        print("  チャンネル: \(channelRaw) (グループ\(channelGroup) 実際のチャンネル\(actualChannel))")
        print("  スロットマスク: \(String(format: "%04b", slotMask))")
        
        // スロット状態を表示
        let slotStates = [
            (slotMask & 0x08) != 0 ? "ON" : "--",
            (slotMask & 0x04) != 0 ? "ON" : "--",
            (slotMask & 0x02) != 0 ? "ON" : "--",
            (slotMask & 0x01) != 0 ? "ON" : "--"
        ]
        print("  スロット状態: \(slotStates[0])-\(slotStates[1])-\(slotStates[2])-\(slotStates[3])")
    }
    
    // アクティブなFMチャンネルの詳細を出力
    private func printActiveFMChannelDetails() {
        guard let z80 = z80 else { return }
        
        print("🎵 アクティブFMチャンネル詳細:")
        
        // 全6チャンネルを確認
        for ch in 0..<6 {
            // チャンネルごとのレジスタベースアドレス計算
            let baseAddr = ch < 3 ? 0x00 : 0x100
            let chOffset = ch % 3
            
            // F-Number と Block を取得
            let fnumL = z80.opnaRegisters[baseAddr + 0xA0 + chOffset]
            let fnumH = z80.opnaRegisters[baseAddr + 0xA4 + chOffset]
            let fnum = (Int(fnumH & 0x07) << 8) | Int(fnumL)
            let block = (fnumH >> 3) & 0x07
            
            // ALG と FB を取得
            let algFB = z80.opnaRegisters[baseAddr + 0xB0 + chOffset]
            let alg = algFB & 0x07
            let fb = (algFB >> 3) & 0x07
            
            // オペレータのパラメータを取得
            let op1TL = z80.opnaRegisters[baseAddr + 0x40 + chOffset]
            let op2TL = z80.opnaRegisters[baseAddr + 0x48 + chOffset]
            let op3TL = z80.opnaRegisters[baseAddr + 0x44 + chOffset]
            let op4TL = z80.opnaRegisters[baseAddr + 0x4C + chOffset]
            
            // キーオン状態を確認
            let keyOnReg = z80.opnaRegisters[0x28]
            let channel = keyOnReg & 0x07
            let channelGroup = (keyOnReg & 0x04) >> 2
            let actualChannel = channelGroup == 0 ? channel : channel + 3
            let slotMask = (keyOnReg >> 4) & 0x0F
            let isKeyOn = actualChannel == ch && slotMask != 0
            
            // F-Numが0でない、またはキーオンされているチャンネルを詳細表示
            if fnum != 0 || isKeyOn {
                print("  CH\(ch): F-Num=\(fnum), Block=\(block), ALG=\(alg), FB=\(fb), KeyOn=\(isKeyOn ? "○" : "×")")
                print("    OP1: TL=\(op1TL), OP2: TL=\(op2TL), OP3: TL=\(op3TL), OP4: TL=\(op4TL)")
                
                // エンベロープ関連パラメータも出力
                let op1AR = z80.opnaRegisters[baseAddr + 0x50 + chOffset] & 0x1F
                let op1DR = z80.opnaRegisters[baseAddr + 0x60 + chOffset] & 0x1F
                let op1SR = z80.opnaRegisters[baseAddr + 0x70 + chOffset] & 0x1F
                let op1RR = z80.opnaRegisters[baseAddr + 0x80 + chOffset] & 0x0F
                
                print("    OP1 Envelope: AR=\(op1AR), DR=\(op1DR), SR=\(op1SR), RR=\(op1RR)")
            }
        }
    }

    // FMエンジンの状態を詳細に表示
    private func checkFMEngineState() {
        guard let z80 = z80 else { return }
        
        // キーオンレジスタの解析
        let keyOnReg = z80.opnaRegisters[0x28]
        let slotMask = (keyOnReg >> 4) & 0x0F
        let channel = keyOnReg & 0x07
        let actualChannel = (keyOnReg & 0x04) == 0 ? channel : channel + 3
        
        print("🎹 FMエンジン状態:")
        print("  キーオン: 0x\(String(format: "%02X", keyOnReg))")
        print("  チャンネル: \(actualChannel), スロット: \(String(format: "%04b", slotMask))")
        
        // サンプル値の確認
        let testSample = fmEngine.generateSample(1.0 / sampleRate)
        print("  サンプル値: \(testSample)")
        
        if testSample == 0.0 {
            print("⚠️ サンプル値がゼロです - 以下を確認:")
            print("  - スロットマスク設定 (0x\(String(format: "%X", slotMask)))")
            print("  - TL値（音量）設定")
            print("  - FMエンジンの実装")
        }
    }
    
    // 状態更新
    public func updateState() {
        if let z80 = z80 {
            // 更新前の状態を確認
            let keyOnRegBefore = z80.opnaRegisters[0x28]
            
            // 各音源エンジンの状態を更新
            ssgEngine.updateState(registers: z80.opnaRegisters)
            fmEngine.updateState(registers: z80.opnaRegisters)
            rhythmEngine.updateState(registers: z80.opnaRegisters)
            adpcmEngine.updateState(registers: z80.opnaRegisters)
            
            // キーオン/オフ処理が行われたか確認
            let keyOnRegAfter = z80.opnaRegisters[0x28]
            if keyOnRegBefore != keyOnRegAfter {
                print("🔑 キーオン状態変化: 0x\(String(format: "%02X", keyOnRegBefore)) → 0x\(String(format: "%02X", keyOnRegAfter))")
                analyzeKeyOnRegister()
                
                // キーオン時は詳細チェックを実行
                if keyOnRegAfter != 0 {
                    checkFMEngineState()
                }
            }
            
            // 定期的に詳細チェックを実行
            if Int.random(in: 0..<100) < 5 { // 5%の確率でチェック実行
                checkFMEngineState()
            }
        } else {
            print("⚠️ Z80参照がnilです")
        }
    }
    
    // SSG音源の状態更新（下位互換性のため）
    public func updateSSGState() {
        // 全音源の状態を更新するメソッドを呼び出す
        updateState()
    }
    
    // オーディオエンジン開始
    func start() {
        // 既存のエンジンを完全に停止
        completeStop()
        
        print("🎵 オーディオエンジン開始処理")
        
        // Z80エミュレータの設定
        if z80 != nil {
            print("🎵 Z80エミュレータ接続済み")
        } else {
            print("⚠️ Z80エミュレータ未接続 - テスト音のみ再生します")
        }
        
        // オーディオセッションの設定
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            
            // ボリュームを確認
            let volume = session.outputVolume
            print("🔊 システム音量: \(volume)")
            if volume < 0.1 {
                print("⚠️ システム音量が低すぎます（\(volume)）")
            }
        } catch {
            print("❌ オーディオセッション設定エラー: \(error)")
            return
        }
        
        // オーディオエンジンの設定
        print("🔊 AVAudioEngine設定開始")
        
        // 既存の接続をクリア
        engine.reset()
        
        // 出力フォーマットの取得
        let mainMixer = engine.mainMixerNode
        let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 2)!
        
        // プレイヤーノードの作成と接続
        playerNode = AVAudioPlayerNode()
        if let player = playerNode {
            engine.attach(player)
            engine.connect(player, to: mainMixer, format: format)
            print("🔊 プレイヤーノード接続完了")
            
            // FMチャンネルの初期化
            initializeFMTone()
            
            // FMエンジンの状態をチェック
            monitorFMEngineOutput()
            
            // テスト用にカスタムFM音を追加
            setupTestFMSound()
            
            // エンジン開始前に音源の状態を更新
            updateState()
            
            // FM音源の状態を詳細チェック
            checkFMEngineState()
            
            // エンジン開始
            do {
                try engine.start()
                print("🔊 AVAudioEngine開始成功")
                
                // バッファ生成
                if let buffer = generateAudioBuffer() {
                    print("🎵 オーディオバッファ生成成功: \(buffer.frameLength)フレーム")
                    
                    // バッファをスケジュール
                    player.scheduleBuffer(buffer, at: nil, options: .loops) {
                        print("🎵 バッファ再生完了コールバック")
                        // 必要に応じて追加のバッファをスケジュール
                    }
                    
                    // 再生開始
                    player.play()
                    isRunning = true
                    print("🎵 オーディオ再生開始 - テスト音とPMD88の音声が再生されます")
                    
                    // 再生状態を定期的に確認する処理を追加
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        if let isPlaying = self?.playerNode?.isPlaying, isPlaying {
                            print("✅ 再生中確認: 音声出力アクティブ")
                            // 定期的にFMエンジンの状態をチェック
                            self?.checkFMEngineState()
                        } else {
                            print("⚠️ 再生状態異常: 音声出力が開始されていない可能性")
                            // 再度再生を試みる
                            self?.playerNode?.play()
                        }
                    }
                } else {
                    print("❌ バッファ生成失敗")
                }
            } catch {
                print("❌ オーディオエンジン開始エラー: \(error.localizedDescription)")
            }
        } else {
            print("❌ PlayerNode作成失敗")
        }
    }
    
    // オーディオエンジン停止
    func stop() {
        print("🔊 オーディオエンジン停止開始")
        
        // 再生状態をオフに（最初に設定）
        isRunning = false
        
        // 再生中のプレイヤーノードを確実に停止
        if let player = playerNode {
            player.pause()
            player.stop()
            print("🔊 プレイヤーノード停止")
        }
        
        // 完全停止処理
        completeStop()
        
        // 各音源エンジンの状態をリセット
        resetAllEngines()
        
        print("🔊 オーディオエンジン停止完了")
    }
    
    // 全音源エンジンのリセット
    private func resetAllEngines() {
        // 各音源エンジンのキーオフ処理やリセット処理を行う
        if let z80 = z80 {
            // 全チャンネルキーオフ用のレジスタ設定
            z80.opnaRegisters[0x28] = 0x00 // 全チャンネルキーオフ
            
            // 各音源の状態を更新
            ssgEngine.updateState(registers: z80.opnaRegisters)
            fmEngine.updateState(registers: z80.opnaRegisters)
            rhythmEngine.updateState(registers: z80.opnaRegisters)
            adpcmEngine.updateState(registers: z80.opnaRegisters)
            
            print("🎵 全音源エンジンリセット完了")
        }
    }
    
    // 完全停止処理
    private func completeStop() {
        // 現在のプレイヤーノードを停止
        if let player = playerNode {
            // 再生中かどうかに関わらず強制的に停止
            player.stop()
            
            // バッファをリセット
            player.reset()
            
            // エンジンから切り離す
            engine.detach(player)
            playerNode = nil
            print("🔊 プレイヤーノード解放")
        }
        
        // エンジンを停止
        do {
            // エンジンの実行状態に関わらず強制的に停止
            engine.stop()
            print("🔊 AVAudioEngine停止")
            
            // エンジンを完全にリセット
            engine.reset()
            print("🔊 AVAudioEngineリセット完了")
            
            // オーディオセッションを非アクティブにする
            try AVAudioSession.sharedInstance().setActive(false)
            print("🔊 オーディオセッション非アクティブ化")
        } catch {
            print("⚠️ オーディオエンジン停止エラー: \(error)")
        }
    }
    
    // 実行中かどうか - より確実な判定に
    func isPlaying() -> Bool {
        // playerNodeがnilでなく、かつisRunningフラグがtrueの場合のみ再生中と判断
        return isRunning && playerNode != nil
    }
    
    // FMチャンネルの状態を確認
    private func checkActiveFMChannels() {
        guard let z80 = z80 else { return }
        
        var activeChannels = [Int]()
        
        // 各チャンネルのFNUM、BLOCK、ALGORITHMを確認
        for ch in 0..<6 {
            let baseAddr = ch < 3 ? 0xA0 : 0xA4
            let chOffset = ch % 3
            
            let fnumL = z80.opnaRegisters[baseAddr + chOffset]
            let fnumH = z80.opnaRegisters[baseAddr + 0x10 + chOffset]
            let fnum = (Int(fnumH & 0x07) << 8) | Int(fnumL)
            let block = (fnumH >> 3) & 0x07
            
            // アルゴリズムとフィードバック（CH3以降は+100h）
            let alg_fb_addr = (ch < 3) ? 0xB0 + chOffset : 0x1B0 + (ch - 3)
            let alg_fb = z80.opnaRegisters[alg_fb_addr]
            let algorithm = alg_fb & 0x07
            let feedback = (alg_fb >> 3) & 0x07
            
            // FNUMが0でなければ有効なチャンネル
            if fnum != 0 {
                activeChannels.append(ch)
                print("🎹 FMチャンネル\(ch)アクティブ: FNUM=\(fnum), BLOCK=\(block), ALG=\(algorithm), FB=\(feedback)")
            }
        }
        
        if activeChannels.isEmpty {
            print("⚠️ アクティブなFMチャンネルがありません")
        }
    }
    
    // テスト用にFMチャンネルを直接設定
    private func setupTestFMSound() {
        guard let z80 = z80 else { return }
        
        print("🎵 テスト音声を設定します")
        
        // チャンネル0を使用（チャンネル1は曲で使用される可能性があるため）
        let ch = 0
        
        // すべてのオペレータのTLを調整（音量を上げる）
        z80.opnaRegisters[0x40 + ch] = 0x10  // OP1: TL=16 (かなり大きな音量)
        z80.opnaRegisters[0x48 + ch] = 0x20  // OP2: TL=32
        z80.opnaRegisters[0x44 + ch] = 0x20  // OP3: TL=32
        z80.opnaRegisters[0x4C + ch] = 0x00  // OP4: TL=0 (最大音量)
        
        // KS/AR (Key Scale/Attack Rate) - 速い立ち上がり
        z80.opnaRegisters[0x50 + ch] = 0x1F  // OP1: KS=0, AR=31
        z80.opnaRegisters[0x58 + ch] = 0x1F  // OP2: KS=0, AR=31
        z80.opnaRegisters[0x54 + ch] = 0x1F  // OP3: KS=0, AR=31
        z80.opnaRegisters[0x5C + ch] = 0x1F  // OP4: KS=0, AR=31
        
        // アルゴリズムとフィードバック - 単純な音色
        z80.opnaRegisters[0xB0 + ch] = 0x07  // ALG=7 (各オペレータが直接出力), FB=0
        
        // 周波数設定（C4=261.6Hz, BLOCK=3）
        z80.opnaRegisters[0xA4 + ch] = 0x1C  // BLOCK=3, FNUM上位ビット
        z80.opnaRegisters[0xA0 + ch] = 0x6E  // FNUM下位ビット
        
        // キーオン設定 - 全スロットON
        z80.opnaRegisters[0x28] = 0xF0 | UInt8(ch)  // 全スロットON + チャンネル番号
        
        print("🎵 テスト音設定完了: CH\(ch) ALG=7 FB=0, C4音")
    }
    
    // FMエンジンの状態をモニタリング
    private func monitorFMEngineOutput() {
        guard let z80 = z80 else { return }
        
        // サンプル値をテスト生成
        print("🎵 FM音源サンプル値モニタリング:")
        
        // 複数のサンプルを生成してチェック
        var nonZeroSamples = 0
        var totalAmplitude: Float = 0.0
        
        for i in 0..<10 {
            let sample = fmEngine.generateSample(1.0 / sampleRate)
            print("  サンプル\(i): \(sample)")
            
            if abs(sample) > 0.0001 {
                nonZeroSamples += 1
                totalAmplitude += abs(sample)
            }
        }
        
        // 結果を評価
        print("  非ゼロサンプル数: \(nonZeroSamples)/10")
        
        if nonZeroSamples == 0 {
            print("⚠️ すべてのサンプルがゼロです - FMエンジンが正しく音を生成していません")
            
            // キーオンレジスタの詳細解析
            analyzeKeyOnRegister()
            
            // チャンネル1の状態を詳細に出力
            let ch = 1
            print("  CH\(ch)設定詳細:")
            print("    FNUM: 0x\(String(format: "%04X", (Int(z80.opnaRegisters[0xA4 + ch] & 0x07) << 8) | Int(z80.opnaRegisters[0xA0 + ch])))")
            print("    BLOCK: \(z80.opnaRegisters[0xA4 + ch] >> 3)")
            print("    ALG/FB: 0x\(String(format: "%02X", z80.opnaRegisters[0xB0 + ch]))")
            print("    OP1 TL: \(z80.opnaRegisters[0x40 + ch])")
            print("    OP2 TL: \(z80.opnaRegisters[0x48 + ch])")
            print("    OP3 TL: \(z80.opnaRegisters[0x44 + ch])")
            print("    OP4 TL: \(z80.opnaRegisters[0x4C + ch])")
        } else {
            print("✅ FMエンジンは音を生成しています。平均振幅: \(totalAmplitude / Float(nonZeroSamples))")
        }
    }
}
