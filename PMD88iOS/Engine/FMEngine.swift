import Foundation
import AVFoundation

/// FM音源エンジン
/// YM2608/OPNAのFM音源部分を担当
class FMEngine {
    // FM音源用オペレータ構造体
    struct FMOperator {
        var detune: Int = 0       // デチューン
        var multiple: Int = 1     // 周波数逓倍率
        var totalLevel: Int = 0   // 出力レベル (0-127)
        var keyScale: Int = 0     // キースケール
        var attackRate: Int = 0   // アタックレート
        var decayRate: Int = 0    // ディケイレート
        var sustainRate: Int = 0  // サスティンレート
        var releaseRate: Int = 0  // リリースレート
        var sustainLevel: Int = 0 // サスティンレベル
        var waveform: Int = 0     // 波形選択
        var phase: Float = 0      // 位相
        var envelope: Float = 0   // 現在のエンベロープ値
        var output: Float = 0     // オペレータ出力値
        var phaseIncrement: Float = 0 // 位相増加量
        var lastOutput: Float = 0 // 前回の出力値
        var frequency: Float = 0  // 周波数
        
        // エンベロープの状態
        enum EnvelopeState {
            case attack, decay, sustain, release, off
        }
        var envelopeState: EnvelopeState = .off
        var envelopeLevel: Float = 0  // 現在のエンベロープレベル (0-1023)
        var envelopeCounter: Float = 0 // エンベロープカウンター
        
        // キーオン/オフフラグ
        var keyOn: Bool = false
        var keyOnTime: TimeInterval = 0 // キーオンが発生した時間
    }
    
    // FM音源チャンネル構造体
    struct FMChannel {
        var operators: [FMOperator] = Array(repeating: FMOperator(), count: 4)
        var algorithm: Int = 0     // 接続アルゴリズム (0-7)
        var feedback: Int = 0      // フィードバック量 (0-7)
        var frequency: Float = 0    // 周波数設定値
        var block: Int = 0         // オクターブ (0-7)
        var keyOn: Bool = false    // キーオン状態
        var output: Float = 0      // チャンネル出力値
        var fnum: Int = 0          // F-Number値
        var pan: Int = 3           // パンニング (0=右, 1=左, 2=無し, 3=両方)
        var lastOutputs: [Float] = [0, 0] // 前回の出力値 [左, 右]
        var noteNumber: Int = 0     // MIDIノート番号相当値 (0-127)
        
        // 音名とオクターブを計算
        mutating func noteName() -> String {
            // PMD88の音名計算方法に基づいて実装
            // F-Numberから音名を計算
            if fnum == 0 {
                return "---"
            }
            
            // 音名の配列（PMD88と同じ順序）
            let noteNames = ["C", "C+", "D", "D+", "E", "F", "F+", "G", "G+", "A", "A+", "B"]
            
            // F-Numberから音名のインデックスを計算
            // PMD88の計算方法に基づく近似値
            let fnumValues = [617, 654, 693, 734, 778, 824, 873, 925, 980, 1038, 1100, 1165]
            
            // 最も近いF-Number値を探す
            var closestIndex = 0
            var minDiff = Int.max
            
            for (index, value) in fnumValues.enumerated() {
                let diff = abs(fnum - value)
                if diff < minDiff {
                    minDiff = diff
                    closestIndex = index
                }
            }
            
            // MIDIノート番号を計算して保存 (C-1 = 0, G9 = 127)
            // オクターブは0゙0として1゙1とする
            self.noteNumber = closestIndex + (block + 1) * 12
            
            // 音名とオクターブを組み合わせて返す
            return "\(noteNames[closestIndex])\(block)"  
        }
        
        // 詳細なチャンネル情報を取得
        mutating func getDetailedInfo() -> String {
            let note = noteName()
            let fnumHex = String(format: "%04X", fnum)
            let algInfo = "ALG:\(algorithm) FB:\(feedback)"
            let panInfo = ["R", "L", "-", "C"][pan]
            
            // オペレータのレベル情報を取得
            var opLevels = ""
            for (i, op) in operators.enumerated() {
                opLevels += "OP\(i+1):\(String(format: "%02d", 127-op.totalLevel)) "
            }
            
            return "\(note) F#:\(fnumHex) \(algInfo) PAN:\(panInfo) \(opLevels)"
        }
    }
    
    private var fmChannels: [FMChannel] = Array(repeating: FMChannel(), count: 6)
    private let fmChannelsLock = NSLock() // FMチャンネル用ロック
    
    private let sampleRate: Float
    private let fmClock: Float
    
    // FM音源用の定数テーブル
    private var sinTable: [Float] = Array(repeating: 0, count: 1024)
    
    init(sampleRate: Float, fmClock: Float) {
        self.sampleRate = sampleRate
        self.fmClock = fmClock
        
        initFMSynthesizer()
    }
    
    // FM音源の初期化
    private func initFMSynthesizer() {
        for ch in 0..<fmChannels.count {
            fmChannels[ch] = FMChannel()
            fmChannels[ch].lastOutputs = [0.0, 0.0]
            
            for op in 0..<4 {
                fmChannels[ch].operators[op] = FMOperator()
                // オペレータの初期化
                fmChannels[ch].operators[op].envelopeState = .off
                fmChannels[ch].operators[op].envelopeLevel = 1023.0 // 最大減衰（無音）
                fmChannels[ch].operators[op].keyOn = false
            }
        }
        
        // サインテーブルの生成
        generateSineTable()
        
        print("🎹 FM音源初期化完了: \(fmChannels.count)チャンネル")
    }
    
    // サインテーブルを生成
    private func generateSineTable() {
        for i in 0..<1024 {
            let angle = Float(i) * 2.0 * Float.pi / 1024.0
            let value = sin(angle)
            sinTable[i] = value
        }
    }
    
    // デバッグ用カウンター
    private var debugCounter: Int = 0
    
    // FMパラメータを直接設定するメソッド
    func setFMParameters(channel: Int, fnum: Int, block: Int, algorithm: Int) {
        guard channel < fmChannels.count else { return }
        
        // チャンネルパラメータを設定
        fmChannels[channel].fnum = fnum
        fmChannels[channel].block = block
        fmChannels[channel].algorithm = algorithm
        
        // 周波数を計算
        let frequency = calcFMFrequency(fnum, block)
        fmChannels[channel].frequency = frequency
        
        // オペレータのパラメータを設定
        for op in 0..<4 {
            // 各オペレータの周波数を設定
            fmChannels[channel].operators[op].frequency = frequency
            
            // アタックを速くして音が確実に出るようにする
            fmChannels[channel].operators[op].attackRate = 31
            fmChannels[channel].operators[op].decayRate = 0
            fmChannels[channel].operators[op].sustainRate = 0
            fmChannels[channel].operators[op].releaseRate = 15
            
            // オペレータの音量を設定 (最後のオペレータのみ音量を上げる)
            if op == 3 {
                fmChannels[channel].operators[op].totalLevel = 32 // 音量を上げる
            } else {
                fmChannels[channel].operators[op].totalLevel = 127 // 他は最小音量
            }
        }
        
        print("🎹 FM\(channel+1)のパラメータを設定: FNUM=\(fnum), BLOCK=\(block), ALG=\(algorithm), 音名=\(calcNoteName(fnum: fnum, block: block))")
    }
    
    // FM音源のサンプル生成
    func generateSample(_ timeStep: Float) -> Float {
        fmChannelsLock.lock()
        defer { fmChannelsLock.unlock() }
        
        var mixedOutput: Float = 0.0
        
        // 後で記録するためにローカル変数に保存
        var _: Float = 0.0
        var activeChannels = 0
        
        // 各FMチャンネルの処理
        for ch in 0..<min(6, fmChannels.count) { // 6チャンネル全て処理（YM2608/OPNA仕様）
            // 各オペレータのキーオン状態を確認
            var hasActiveOperator = false
            for op in 0..<4 {
                if fmChannels[ch].operators[op].keyOn {
                    hasActiveOperator = true
                    break
                }
            }
            
            if !hasActiveOperator {
                continue // アクティブなオペレータがない場合は処理しない
            }
            
            activeChannels += 1
            
            // チャンネルの基本周波数を計算
            let baseFreq = calcFMFrequency(Int(fmChannels[ch].fnum), fmChannels[ch].block)
            
            // オペレータの出力を計算
            var opOutputs: [Float] = [0, 0, 0, 0]
            var feedback: Float = 0.0
            
            // フィードバック量を計算（オペレータ1用）
            if fmChannels[ch].feedback > 0 {
                let fbMultiplier = Float(fmChannels[ch].feedback) * 0.05 // フィードバック調整
                feedback = fmChannels[ch].operators[0].output * fbMultiplier
            }
            
            // 各オペレータの出力を計算
            for op in 0..<4 {
                if !fmChannels[ch].operators[op].keyOn {
                    continue // キーオフなら処理しない
                }
                
                // オペレータの周波数を計算（デチューンと倍率を適用）
                let opFreq = baseFreq * Float(fmChannels[ch].operators[op].multiple) * getDetuneMultiplier(fmChannels[ch].operators[op].detune)
                
                // 位相を更新（0に近い値での異常な振動を防止）
                var phase = fmChannels[ch].operators[op].phase
                if opFreq > 0.1 { // 周波数が十分大きい場合のみ更新
                    phase += timeStep * opFreq
                    while phase >= 1.0 {
                        phase -= 1.0
                    }
                    fmChannels[ch].operators[op].phase = phase
                }
                
                // 入力変調（アルゴリズムに依存）
                var modulatedPhase = phase
                
                // アルゴリズムに基づく変調の適用
                switch fmChannels[ch].algorithm {
                case 0: // アルゴリズム0: オペレータを直列接続 (1->2->3->4)
                    if op == 0 {
                        modulatedPhase += feedback
                    } else if op == 1 {
                        modulatedPhase += opOutputs[0]
                    } else if op == 2 {
                        modulatedPhase += opOutputs[1]
                    } else if op == 3 {
                        modulatedPhase += opOutputs[2]
                    }
                case 1: // アルゴリズム1: (1->3->4), (2->3->4)
                    if op == 0 {
                        modulatedPhase += feedback
                    } else if op == 1 {
                        modulatedPhase += 0 // 独立
                    } else if op == 2 {
                        modulatedPhase += opOutputs[0] + opOutputs[1]
                    } else if op == 3 {
                        modulatedPhase += opOutputs[2]
                    }
                case 2: // アルゴリズム2: (1->3->4), (2->4)
                    if op == 0 {
                        modulatedPhase += feedback
                    } else if op == 1 {
                        modulatedPhase += 0 // 独立
                    } else if op == 2 {
                        modulatedPhase += opOutputs[0]
                    } else if op == 3 {
                        modulatedPhase += opOutputs[1] + opOutputs[2]
                    }
                case 3: // アルゴリズム3: (1->2->4), (3->4)
                    if op == 0 {
                        modulatedPhase += feedback
                    } else if op == 1 {
                        modulatedPhase += opOutputs[0]
                    } else if op == 2 {
                        modulatedPhase += 0 // 独立
                    } else if op == 3 {
                        modulatedPhase += opOutputs[1] + opOutputs[2]
                    }
                case 4: // アルゴリズム4: (1->2), (3->4), 2と4が出力
                    if op == 0 {
                        modulatedPhase += feedback
                    } else if op == 1 {
                        modulatedPhase += opOutputs[0]
                    } else if op == 2 {
                        modulatedPhase += 0 // 独立
                    } else if op == 3 {
                        modulatedPhase += opOutputs[2]
                    }
                case 5: // アルゴリズム5: (1->2), (1->3), (1->4)
                    if op == 0 {
                        modulatedPhase += feedback
                    } else {
                        modulatedPhase += opOutputs[0]
                    }
                case 6: // アルゴリズム6: (1->2), 1,3,4は独立
                    if op == 0 {
                        modulatedPhase += feedback
                    } else if op == 1 {
                        modulatedPhase += opOutputs[0]
                    } else {
                        modulatedPhase += 0 // 独立
                    }
                case 7: // アルゴリズム7: 全オペレータ独立
                    if op == 0 {
                        modulatedPhase += feedback
                    } else {
                        modulatedPhase += 0 // 独立
                    }
                default: // その他はアルゴリズム0と同様に処理
                    if op == 0 {
                        modulatedPhase += feedback
                    } else if op == 1 {
                        modulatedPhase += opOutputs[0]
                    } else if op == 2 {
                        modulatedPhase += opOutputs[1]
                    } else if op == 3 {
                        modulatedPhase += opOutputs[2]
                    }
                }
                
                // 位相を0-1の範囲に収める
                while modulatedPhase >= 1.0 {
                    modulatedPhase -= 1.0
                }
                while modulatedPhase < 0.0 {
                    modulatedPhase += 1.0
                }
                
                // サイン波生成
                let sineIndex = Int(modulatedPhase * 1023) & 1023
                let sineValue = sinTable[sineIndex]
                
                // エンベロープ処理（単純化）
                let level = min(Float(fmChannels[ch].operators[op].totalLevel) / 127.0, 1.0) // 範囲チェック
                let envelopeValue = 1.0 - level // トータルレベルが高いほど音量は小さくなる
                
                // 出力計算
                let output = sineValue * envelopeValue * 0.5 // 音量調整
                opOutputs[op] = output
                fmChannels[ch].operators[op].output = output
                
                // チャンネル出力に加算（アルゴリズムに応じて）
                if (fmChannels[ch].algorithm == 7) || // アルゴリズム7は全て並列
                   (fmChannels[ch].algorithm == 0 && op == 3) || // アルゴリズム0は最後のオペレータのみ出力
                   (fmChannels[ch].algorithm == 4 && (op == 3 || op == 1)) // アルゴリズム4は3と1が出力
                {
                    fmChannels[ch].output += output
                }
            }
            
            // ミキシング - 音量を増やす
            mixedOutput += fmChannels[ch].output * 0.5 // チャンネル音量を増大
            fmChannels[ch].output = 0.0 // 次回のために初期化
        }
        
        // サンプル値を記録
        // 直近のサンプルを配列に保存
        if sampleIndex >= lastSamples.count {
            sampleIndex = 0
        }
        
        // 音が出ていない場合はテスト音を生成
        if activeChannels > 0 && abs(mixedOutput) < 0.01 {
            // キーオンしているのに音が出ていない場合は強制的に音を生成
            let testTone = sin(Float(sampleIndex % 100) / 100.0 * 2.0 * Float.pi) * 0.1
            mixedOutput = testTone
            print("⚠️ FMチャンネルがアクティブなのに音が出ていないためテスト音を生成")
        }
        
        lastSamples[sampleIndex] = mixedOutput
        sampleIndex += 1
        
        // デバッグ用：アクティブなチャンネル数と音量を定期的に出力
        debugCounter += 1
        if debugCounter >= 22050 { // 約0.5秒ごとに出力
            debugCounter = 0
            if activeChannels > 0 {
                print("🎹 アクティブFMチャンネル数: \(activeChannels), 最大音量: \(lastSamples.max() ?? 0)")
                
                // チャンネルの状態を詳細に出力
                for ch in 0..<fmChannels.count {
                    if fmChannels[ch].keyOn {
                        print("  - FM\(ch+1): 音名=\(calcNoteName(fnum: fmChannels[ch].fnum, block: fmChannels[ch].block)), キーオン=\(fmChannels[ch].keyOn), アルゴリズム=\(fmChannels[ch].algorithm)")
                    }
                }
            }
        }
        
        return mixedOutput
    }
    
    // FM音源の周波数計算
    private func calcFMFrequency(_ freq: Int, _ block: Int) -> Float {
        let f = Float(freq)
        let safeBlock = max(1, block) // ブロックが1未満の場合は1にする
        let baseFreq = fmClock / (Float(144) * (2.0 * 1024.0)) // FM音源の基準周波数
        return baseFreq * f * powf(2.0, Float(safeBlock - 1))
    }
    
    // FM音源の音名計算
    private func calcNoteName(fnum: Int, block: Int) -> String {
        if fnum == 0 {
            return "---"
        }
        
        // 音名の配列（C, C#, D, D#, E, F, F#, G, G#, A, A#, B）
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        
        // FNUMから音名のインデックスを計算
        // 基準値: FNUM=617でA4（40Hz）、Block=4
        let fnumLog = log(Double(fnum) / 617.0) / log(2.0)
        let noteIndex = Int((fnumLog * 12.0).rounded())
        
        // 音名とオクターブを組み合わせる
        let adjustedIndex = (noteIndex % 12 + 12) % 12  // 負の値に対応
        let adjustedOctave = block + (noteIndex / 12)
        
        return "\(noteNames[adjustedIndex])\(adjustedOctave)"
    }
    
    // デチューン値から倍率を計算
    private func getDetuneMultiplier(_ detune: Int) -> Float {
        // 範囲を制限して安全に処理
        let safeDetune = max(min(detune, 3), -3)
        switch safeDetune {
        case -3: return 0.94
        case -2: return 0.96
        case -1: return 0.98
        case 0: return 1.0
        case 1: return 1.02
        case 2: return 1.04
        case 3: return 1.06
        default: return 1.0
        }
    }
    
    // エンベロープ処理
    private func updateEnvelope(op: inout FMOperator, timeStep: Float, keyScale: Int, block: Int) {
        // キーオン/オフに応じた状態遷移
        if op.keyOn && op.envelopeState == .off {
            // キーオン時はアタック状態に
            op.envelopeState = .attack
            op.envelopeLevel = 1023.0 // 最大減衰から開始
        } else if !op.keyOn && op.envelopeState != .off {
            // キーオフ時はリリース状態に
            op.envelopeState = .release
        }
        
        // キースケールに基づくレート調整
        let ksRate = calculateKeyScaleRate(keyScale, block)
        
        // 状態に応じたエンベロープ処理
        switch op.envelopeState {
        case .attack:
            // アタックレート計算
            let attackRate = min(63, op.attackRate * 2 + ksRate)
            if attackRate > 0 {
                // アタック処理（指数関数的減少）
                let rate = powf(2.0, Float(attackRate) / 4.0) * timeStep * 44100.0
                op.envelopeLevel -= rate * (op.envelopeLevel / 1023.0) * 1023.0
                
                // 最小値に達したらディケイ状態へ
                if op.envelopeLevel <= 0.0 {
                    op.envelopeLevel = 0.0
                    op.envelopeState = .decay
                }
            }
            
        case .decay:
            // ディケイレート計算
            let decayRate = min(63, op.decayRate * 2 + ksRate)
            if decayRate > 0 {
                // ディケイ処理（線形増加）
                let rate = powf(2.0, Float(decayRate) / 4.0) * timeStep * 44100.0
                op.envelopeLevel += rate
                
                // サスティンレベルに達したらサスティン状態へ
                let sustainLevel = Float(op.sustainLevel) * 1023.0 / 15.0
                if op.envelopeLevel >= sustainLevel {
                    op.envelopeLevel = sustainLevel
                    op.envelopeState = .sustain
                }
            }
            
        case .sustain:
            // サスティンレート計算
            let sustainRate = min(63, op.sustainRate * 2 + ksRate)
            if sustainRate > 0 {
                // サスティン処理（線形増加）
                let rate = powf(2.0, Float(sustainRate) / 4.0) * timeStep * 44100.0
                op.envelopeLevel += rate
                
                // 最大値に達したらオフ状態へ
                if op.envelopeLevel >= 1023.0 {
                    op.envelopeLevel = 1023.0
                    op.envelopeState = .off
                }
            }
            
        case .release:
            // リリースレート計算
            let releaseRate = min(63, op.releaseRate * 4 + ksRate)
            if releaseRate > 0 {
                // リリース処理（線形増加）
                let rate = powf(2.0, Float(releaseRate) / 4.0) * timeStep * 44100.0
                op.envelopeLevel += rate
                
                // 最大値に達したらオフ状態へ
                if op.envelopeLevel >= 1023.0 {
                    op.envelopeLevel = 1023.0
                    op.envelopeState = .off
                }
            }
            
        case .off:
            // オフ状態では最大減衰
            op.envelopeLevel = 1023.0
        }
        
        // エンベロープレベルから出力レベルへの変換
        // 0-1023のエンベロープレベルを0-1の出力レベルに変換
        op.envelope = powf(10.0, -op.envelopeLevel / 256.0)
    }
    
    // キースケールレートの計算
    private func calculateKeyScaleRate(_ keyScale: Int, _ block: Int) -> Int {
        if keyScale == 0 {
            return 0
        }
        
        // キースケールに応じたレート調整
        let blockRate = block * 2
        
        switch keyScale {
        case 1: return blockRate
        case 2: return blockRate * 3 / 2
        case 3: return blockRate * 2
        default: return 0
        }
    }
    
    // レジスタ値に基づいてFM音源状態を更新
    func updateState(registers: [UInt8]) {
        fmChannelsLock.lock()
        defer { fmChannelsLock.unlock() }
        
        print("🎹 FM音源レジスタ更新: \(registers.count) バイト")
        
        // デバッグ出力
        print("🎹 FMエンジン状態更新開始")
        
        // オペレータパラメータの更新 (0x30-0x9F)
        for ch in 0..<min(6, fmChannels.count) {
            // チャンネル番号の調整（0-2は通常のチャンネル、3-5は拡張チャンネル）
            let chOffset = ch < 3 ? ch : ch + 1
            
            // 各オペレータのパラメータを更新
            for op in 0..<4 {
                // オペレータのレジスタアドレス計算
                // オペレータのレジスタアドレスは複雑なマッピングになっている
                let baseAddr = 0x30 + (op * 4) + (chOffset / 3) * 0x20
                let opOffset = chOffset % 3
                
                // DT/ML (Detune/Multiple) - 0x30-0x3F
                if registers.count > baseAddr + opOffset {
                    let dtMl = registers[Int(baseAddr + opOffset)]
                    fmChannels[ch].operators[op].detune = Int((dtMl >> 4) & 0x07)
                    fmChannels[ch].operators[op].multiple = Int(dtMl & 0x0F)
                    
                    // デバッグ出力
                    if ch == 0 && op == 0 {
                        print("🎹 CH\(ch) OP\(op) DT/ML: \(dtMl) (DT:\(fmChannels[ch].operators[op].detune), ML:\(fmChannels[ch].operators[op].multiple))")
                    }
                }
                
                // TL (Total Level) - 0x40-0x4F
                if registers.count > baseAddr + opOffset + 0x10 {
                    let tl = registers[Int(baseAddr + opOffset + 0x10)]
                    fmChannels[ch].operators[op].totalLevel = Int(tl & 0x7F)
                    
                    // デバッグ出力
                    if ch == 0 && op == 0 {
                        print("🎹 CH\(ch) OP\(op) TL: \(tl) (Level:\(fmChannels[ch].operators[op].totalLevel))")
                    }
                }
                
                // KS/AR (Key Scale/Attack Rate) - 0x50-0x5F
                if registers.count > baseAddr + opOffset + 0x20 {
                    let ksAr = registers[Int(baseAddr + opOffset + 0x20)]
                    fmChannels[ch].operators[op].keyScale = Int((ksAr >> 6) & 0x03)
                    fmChannels[ch].operators[op].attackRate = Int(ksAr & 0x1F)
                    
                    // デバッグ出力
                    if ch == 0 && op == 0 {
                        print("🎹 CH\(ch) OP\(op) KS/AR: \(ksAr) (KS:\(fmChannels[ch].operators[op].keyScale), AR:\(fmChannels[ch].operators[op].attackRate))")
                    }
                }
                
                // DR (Decay Rate) - 0x60-0x6F
                if registers.count > baseAddr + opOffset + 0x30 {
                    let dr = registers[Int(baseAddr + opOffset + 0x30)]
                    fmChannels[ch].operators[op].decayRate = Int(dr & 0x1F)
                    
                    // デバッグ出力
                    if ch == 0 && op == 0 {
                        print("🎹 CH\(ch) OP\(op) DR: \(dr) (Rate:\(fmChannels[ch].operators[op].decayRate))")
                    }
                }
                
                // SR (Sustain Rate) - 0x70-0x7F
                if registers.count > baseAddr + opOffset + 0x40 {
                    let sr = registers[Int(baseAddr + opOffset + 0x40)]
                    fmChannels[ch].operators[op].sustainRate = Int(sr & 0x1F)
                    
                    // デバッグ出力
                    if ch == 0 && op == 0 {
                        print("🎹 CH\(ch) OP\(op) SR: \(sr) (Rate:\(fmChannels[ch].operators[op].sustainRate))")
                    }
                }
                
                // SL/RR (Sustain Level/Release Rate) - 0x80-0x8F
                if registers.count > baseAddr + opOffset + 0x50 {
                    let slRr = registers[Int(baseAddr + opOffset + 0x50)]
                    fmChannels[ch].operators[op].sustainLevel = Int((slRr >> 4) & 0x0F)
                    fmChannels[ch].operators[op].releaseRate = Int(slRr & 0x0F)
                    
                    // デバッグ出力
                    if ch == 0 && op == 0 {
                        print("🎹 CH\(ch) OP\(op) SL/RR: \(slRr) (SL:\(fmChannels[ch].operators[op].sustainLevel), RR:\(fmChannels[ch].operators[op].releaseRate))")
                    }
                }
            }
            
            // FB/ALG (Feedback/Algorithm) - 0xB0-0xB2, 0xB4-0xB6
            if registers.count > 0xB0 + chOffset {
                let fbAlg = registers[Int(0xB0 + chOffset)]
                fmChannels[ch].feedback = Int((fbAlg >> 3) & 0x07)
                fmChannels[ch].algorithm = Int(fbAlg & 0x07)
                
                // デバッグ出力
                if ch == 0 {
                    print("🎹 CH\(ch) FB/ALG: \(fbAlg) (FB:\(fmChannels[ch].feedback), ALG:\(fmChannels[ch].algorithm))")
                }
            }
        }
        
        // キーオン/オフ処理 (0x28)
        if registers.count > 0x28 {
            let keyOnReg = registers[Int(0x28)]
            
            // 常にキーオンレジスタの値を詳細にログ出力
            print("🔑 キーオンレジスタ(0x28)の値: 0x\(String(format: "%02X", keyOnReg))")
            
            // YM2608/OPNAのキーオンレジスタの解釈
            // bit 0-2: チャンネル番号 (0-7)
            // bit 3: チャンネルタイプ (0=FM, 1=拡張FM)
            // bit 4-7: スロットマスク (bit4=S1, bit5=S2, bit6=S3, bit7=S4)
            
            let channelRaw = Int(keyOnReg & 0x07) // チャンネル番号 (0-7)
            let isExtended = (keyOnReg & 0x08) != 0 // 拡張FMチャンネルかどうか
            let slotMask = (keyOnReg >> 4) & 0x0F // スロットマスク (bit 4-7)
            
            // 実際のチャンネル番号に変換 (0-5)
            let channel = isExtended ? channelRaw + 3 : channelRaw
            
            // 有効なチャンネル番号か確認
            if channel < fmChannels.count {
                // キーオン状態を判定
                let isKeyOn = slotMask != 0 // スロットマスクが0でなければキーオン
                
                // チャンネル全体のキーオン状態を更新
                let oldChannelKeyOn = fmChannels[channel].keyOn
                fmChannels[channel].keyOn = isKeyOn
                
                // キーオン状態の変化をログ出力
                if oldChannelKeyOn != isKeyOn {
                    print("🔑 CH\(channel) キーオン状態変化: \(oldChannelKeyOn ? "オン" : "オフ") -> \(isKeyOn ? "オン" : "オフ")")
                }
                
                // 各オペレータのキーオン/オフ状態を更新
                for op in 0..<4 {
                    let opBit = 1 << op
                    let opKeyOn = (slotMask & UInt8(opBit)) != 0
                    
                    // キーオン状態が変わった場合のみ処理
                    if fmChannels[channel].operators[op].keyOn != opKeyOn {
                        // 状態変化を記録
                        let oldOpKeyOn = fmChannels[channel].operators[op].keyOn
                        fmChannels[channel].operators[op].keyOn = opKeyOn
                        
                        // 常に状態変化を詳細にログ出力
                        print("🔑 CH\(channel) OP\(op) キーオン状態変化: \(oldOpKeyOn ? "オン" : "オフ") -> \(opKeyOn ? "オン" : "オフ"), スロットマスク: 0x\(String(format: "%02X", slotMask))")
                        
                        if opKeyOn {
                            // キーオン時の処理
                            fmChannels[channel].operators[op].keyOnTime = Date().timeIntervalSince1970
                            fmChannels[channel].operators[op].envelopeState = .attack
                            fmChannels[channel].operators[op].envelopeLevel = 1023.0 // 最大減衰から開始
                            fmChannels[channel].operators[op].phase = 0.0 // 位相リセット
                            
                            // 音名と周波数情報を出力
                            let noteName = getChannelNoteName(channel: channel)
                            print("🎹 CH\(channel) OP\(op) キーオン成功! 音名: \(noteName), F-Num: \(fmChannels[channel].fnum), Block: \(fmChannels[channel].block)")
                        } else {
                            // キーオフ時の処理
                            fmChannels[channel].operators[op].envelopeState = .release
                            print("🎹 CH\(channel) OP\(op) キーオフ")
                        }
                    }
                }
                
                // チャンネルのキーオン状態が変化した場合のデバッグ出力
                if oldChannelKeyOn != isKeyOn {
                    print("🎹 FM CH\(channel) キー\(isKeyOn ? "オン" : "オフ") (スロットマスク: \(String(format:"%04b", slotMask)))")
                    
                    // デバッグ出力を強化 - 全チャンネルのキーオン状態を表示
                    var activeChannels = ""
                    for ch in 0..<fmChannels.count {
                        if fmChannels[ch].keyOn {
                            activeChannels += "CH\(ch) "
                        }
                    }
                    print("🎹 アクティブFMチャンネル: \(activeChannels.isEmpty ? "なし" : activeChannels)")
                }
            } else {
                print("⚠️ 無効なチャンネル番号: \(channel) (raw: \(channelRaw), extended: \(isExtended))")
            }
            
            // キーオン/オフレジスタの値を常に表示（デバッグ用）
            print("🔍 レジスタ0x28の値: \(String(format: "0x%02X", keyOnReg))")
        } else {
            print("⚠️ レジスタ0x28が見つかりません。レジスタ配列サイズ: \(registers.count)")
        }
        
        // 周波数設定 (0xA0-0xA2, 0xA4-0xA6, 0xA8-0xAA, 0xAC-0xAE)
        for ch in 0..<min(6, fmChannels.count) {
            // チャンネル番号の調整（0-2は通常のチャンネル、3-5は拡張チャンネル）
            let regOffset = ch < 3 ? ch : ch + 1 // チャンネル3は0xA8から始まる
            
            if registers.count > 0xA0 + regOffset && registers.count > 0xA4 + regOffset {
                let freqLow = registers[Int(0xA0 + regOffset)]
                let freqHighBlock = registers[Int(0xA4 + regOffset)]
                
                let newFnum = Int(freqLow) + ((Int(freqHighBlock) & 0x07) << 8)
                let newBlock = Int((freqHighBlock >> 3) & 0x07)
                
                // 値が変わった場合のみ更新
                if fmChannels[ch].fnum != newFnum || fmChannels[ch].block != newBlock {
                    fmChannels[ch].fnum = newFnum
                    fmChannels[ch].block = newBlock
                    
                    // 周波数計算
                    fmChannels[ch].frequency = Float(fmChannels[ch].fnum)
                    
                    // ブロック値が適切な範囲にあることを確認
                    if fmChannels[ch].block <= 0 {
                        fmChannels[ch].block = 1 // 最小値は1
                    }
                }
            }
            
            // アルゴリズムとフィードバック (0xB0-0xB2)
            if registers.count > 0xB0 + ch {
                let algFb = registers[Int(0xB0 + ch)]
                fmChannels[ch].algorithm = Int(algFb & 0x07)
                fmChannels[ch].feedback = Int((algFb >> 3) & 0x07)
            }
            
            // 各オペレータのパラメータ設定
            for op in 0..<4 {
                let opIndexMap: [(Int, Int)] = [
                    (0, 0), (1, 2), (2, 1), (3, 3)  // 正しいオペレータインデックスマッピング
                ]
                
                let slotIndex = opIndexMap[op].1
                let baseOffset = ch + (slotIndex * 4)
                
                // レジスタインデックスが範囲内かチェック
                if registers.count > 0x40 + baseOffset {
                    // トータルレベル (0x40-0x4F)
                    fmChannels[ch].operators[op].totalLevel = Int(registers[Int(0x40 + baseOffset)] & 0x7F)
                }
                
                if registers.count > 0x30 + baseOffset {
                    // デチューン/倍率 (0x30-0x3F)
                    let dtMl = registers[Int(0x30 + baseOffset)]
                    let dtValue = Int((dtMl >> 4) & 0x07)
                    fmChannels[ch].operators[op].detune = dtValue > 3 ? dtValue - 7 : dtValue // 正しいデチューン値の計算
                    
                    fmChannels[ch].operators[op].multiple = Int(dtMl & 0x0F)
                    if fmChannels[ch].operators[op].multiple == 0 {
                        fmChannels[ch].operators[op].multiple = 1 // 0は0.5倍だが、簡略化のため1倍に
                    }
                }
                
                // その他のパラメータも同様に範囲チェックを追加
                if registers.count > 0x50 + baseOffset {
                    // アタックレート (0x50-0x5F)
                    fmChannels[ch].operators[op].attackRate = Int(registers[Int(0x50 + baseOffset)] & 0x1F)
                }
                
                if registers.count > 0x60 + baseOffset {
                    // ディケイレート (0x60-0x6F)
                    fmChannels[ch].operators[op].decayRate = Int(registers[Int(0x60 + baseOffset)] & 0x1F)
                }
                
                if registers.count > 0x70 + baseOffset {
                    // サスティンレート (0x70-0x7F)
                    fmChannels[ch].operators[op].sustainRate = Int(registers[Int(0x70 + baseOffset)] & 0x1F)
                }
                
                if registers.count > 0x80 + baseOffset {
                    // リリースレート (0x80-0x8F)
                    fmChannels[ch].operators[op].releaseRate = Int(registers[Int(0x80 + baseOffset)] & 0x0F)
                }
            }
        }
    }
    
    // 指定したチャンネルの音名を取得するメソッド
    func getChannelNoteName(channel: Int) -> String {
        guard channel >= 0 && channel < fmChannels.count else {
            return "---"
        }
        
        fmChannelsLock.lock()
        defer { fmChannelsLock.unlock() }
        
        // キーオンされていない場合は音名を表示しない
        if !fmChannels[channel].keyOn {
            return "---"
        }
        
        // 音名を計算して返す
        return fmChannels[channel].noteName()
    }
    
    // 直近のサンプル値を取得するメソッド
    private var lastSamples: [Float] = Array(repeating: 0.0, count: 100)
    private var sampleIndex: Int = 0
    
    // 指定した数のサンプル値を取得
    func getLastSamples(count: Int) -> [Float] {
        let sampleCount = min(count, lastSamples.count)
        return Array(lastSamples.suffix(sampleCount))
    }
    
    // キーオン処理
    func keyOn(channel: Int, slots: UInt8) {
        guard channel >= 0 && channel < fmChannels.count else { return }
        
        fmChannelsLock.lock()
        defer { fmChannelsLock.unlock() }
        
        fmChannels[channel].keyOn = true
        
        // 各オペレータのキーオン処理
        for op in 0..<4 {
            // スロットマスクを確認
            let slotMask = UInt8(1 << op)
            let isSlotOn = (slots & slotMask) != 0
            
            if isSlotOn {
                fmChannels[channel].operators[op].keyOn = true
                fmChannels[channel].operators[op].envelopeState = .attack
                fmChannels[channel].operators[op].keyOnTime = CACurrentMediaTime()
            }
        }
        
        print("🎹 チャンネル\(channel)のキーオン設定: スロット=0x\(String(format: "%02X", slots))")
    }
    
    // PMD88のワークエリアの解析結果を出力
    func printPMD88WorkingAreaStatus(registers: [UInt8]) {
        // キーオンレジスタの状態を確認
        if registers.count > 0x28 {
            let keyOnReg = registers[Int(0x28)]
            print("🎹 PMD88 キーオンレジスタ(0x28): \(String(format: "0x%02X", keyOnReg))")
            
            // アクティブなチャンネルを表示
            var activeChannels = ""
            for ch in 0..<fmChannels.count {
                if fmChannels[ch].keyOn {
                    activeChannels += "CH\(ch)(\(fmChannels[ch].noteName())) "
                }
            }
            print("🎹 アクティブFMチャンネル: \(activeChannels.isEmpty ? "なし" : activeChannels)")
        }
        
        // 各チャンネルの音名とオクターブを表示
        print("🎹 FMチャンネルの音名:")
        for ch in 0..<fmChannels.count {
            let note = fmChannels[ch].noteName()
            print("  - CH\(ch): \(note) (F-Number: \(fmChannels[ch].fnum), Block: \(fmChannels[ch].block), KeyOn: \(fmChannels[ch].keyOn ? "●" : "○"))")
        }
    }
}
