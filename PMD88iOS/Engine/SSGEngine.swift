import Foundation
import AVFoundation

/// SSG（Sound Source Generator）エンジン
/// YM2608/OPNAのSSG部分（AY-3-8910互換）を担当
class SSGEngine {
    // SSGチャンネル構造体
    struct SSGChannel {
        var frequency: Float = 0
        var volume: Float = 0
        var phase: Float = 0
        var enabled: Bool = false
        var noiseEnabled: Bool = false
        var envelopeEnabled: Bool = false
        var lastOutput: Float = 0.0  // 前回の出力値（波形の連続性のため）
        var periodCounter: Int = 0   // 周期カウンター
        var periodValue: Int = 0     // 周期値
    }
    
    // ノイズ生成器
    struct NoiseGenerator {
        var frequency: Float = 0
        var phase: Float = 0
        var value: Float = 1.0
        var shiftRegister: UInt16 = 0x8000  // ノイズ生成用シフトレジスタ
    }
    
    // エンベロープ生成器
    struct EnvelopeGenerator {
        var period: Float = 0
        var phase: Float = 0
        var shape: UInt8 = 0  // エンベロープ形状
        var counter: Float = 0
        var level: Float = 0  // 現在のエンベロープレベル (0-15)
        var cycle: Int = 0    // エンベロープサイクル数
    }
    
    private var channels: [SSGChannel] = Array(repeating: SSGChannel(), count: 3)
    private var noiseGen = NoiseGenerator()
    private var envelopeGen = EnvelopeGenerator()
    private let channelsLock = NSLock() // スレッドセーフのためのロック
    
    private let sampleRate: Float
    private let cpuClock: Float
    
    // SSGレジスタ
    private var ssgRegisters: [UInt8] = Array(repeating: 0, count: 16)
    
    init(sampleRate: Float, cpuClock: Float) {
        self.sampleRate = sampleRate
        self.cpuClock = cpuClock
        
        // ノイズジェネレータの初期化
        noiseGen.shiftRegister = 0x8000
        
        print("🔊 SSGエンジン初期化: channels.count = \(channels.count)")
    }
    
    // ノイズ値の更新 - PMD88のノイズ生成に合わせて改善
    func updateNoise(_ timeStep: Float) -> Float {
        if noiseGen.frequency <= 0 {
            return noiseGen.value
        }
        
        // ノイズ周波数に基づいて位相を更新
        noiseGen.phase += timeStep * noiseGen.frequency
        
        // 1サイクル完了ごとにノイズ値を更新
        let phaseChanged = noiseGen.phase >= 1.0
        while noiseGen.phase >= 1.0 {
            noiseGen.phase -= 1.0
            
            // YM2608/OPNA仕様に基づくノイズ生成
            // 17ビットシフトレジスタを使用
            // フィードバックはビット0とビット3のXOR
            let bit0 = noiseGen.shiftRegister & 0x0001
            let bit3 = (noiseGen.shiftRegister & 0x0008) >> 3
            let feedback = (bit0 ^ bit3) & 0x0001
            
            // レジスタを右にシフトし、フィードバックを最上位に設定
            noiseGen.shiftRegister = (noiseGen.shiftRegister >> 1) | (feedback << 16)
            
            // ノイズ値を更新 (ビット0に基づく)
            noiseGen.value = (noiseGen.shiftRegister & 0x0001) != 0 ? 0.8 : -0.8
        }
        
        // ノイズ値が変化した場合のみデバッグ出力 (ログが多すぎるのを防ぐため)
        if phaseChanged && Int.random(in: 0..<100) < 1 {
            print("🔊 SSGノイズ更新: 周波数=\(String(format: "%.2f", noiseGen.frequency))Hz, 値=\(noiseGen.value)")
        }
        
        return noiseGen.value
    }
    
    // エンベロープ値の更新（YM2608/OPNAのSSGエンベロープ仕様に準拠）
    func updateEnvelope(_ timeStep: Float) -> Float {
        // エンベロープ周期が設定されていない場合は最大音量を返す
        if envelopeGen.period <= 0 {
            return 15.0  // 最大音量 (0-15のスケール)
        }
        
        // エンベロープカウンタを更新
        // let oldLevel = envelopeGen.level  // 未使用変数をコメントアウト
        envelopeGen.counter += timeStep * envelopeGen.period
        
        // カウンタが1を超えたらエンベロープ値を更新
        // let levelChanged = envelopeGen.counter >= 1.0  // 未使用変数をコメントアウト
        while envelopeGen.counter >= 1.0 {
            envelopeGen.counter -= 1.0
            
            // エンベロープカウンタの更新
            envelopeGen.phase += 1.0
            if envelopeGen.phase >= 32.0 {
                envelopeGen.phase = 0.0
                envelopeGen.cycle += 1
                
                // サイクル完了時のデバッグ出力
                print("🎵 SSGエンベロープサイクル完了: 形状=0x\(String(format: "%02X", envelopeGen.shape))")
            }
            
            // エンベロープの形状に基づいてレベルを決定
            let position = Int(envelopeGen.phase)
            let shape = envelopeGen.shape & 0x0F
            
            // YM2608/OPNAのエンベロープ形状仕様に忠実に実装
            // 形状ビット: CONT|ATT|ALT|HOLD
            let cont = (shape & 0x08) != 0  // Continue flag
            let att = (shape & 0x04) != 0   // Attack flag
            let alt = (shape & 0x02) != 0   // Alternate flag
            let hold = (shape & 0x01) != 0  // Hold flag
            
            // エンベロープサイクルの計算
            var level: Float = 0.0
            
            if !cont { // Continue=0: ワンショットモード
                if position < 16 {
                    level = att ? Float(position) : 15.0 - Float(position)
                } else {
                    level = 0.0 // ワンショットの後は0
                }
            } else { // Continue=1: 継続モード
                let phase16 = position % 16
                let direction = att ? true : false // 初期方向（Attack=1なら増加）
                
                // Alternate=1なら方向が交互に変わる
                var currentDirection = direction
                if alt {
                    let cycleCount = position / 16
                    if cycleCount % 2 == 1 {
                        currentDirection = !currentDirection
                    }
                }
                
                // Hold=1なら最初のサイクル後は値を保持
                if hold && position >= 16 {
                    level = direction ? 15.0 : 0.0
                } else {
                    // 現在の方向に基づいてレベルを計算
                    level = currentDirection ? Float(phase16) : 15.0 - Float(phase16)
                }
            }
            
            envelopeGen.level = level
        }
        
        return envelopeGen.level
    }
    
    // SSGサンプルを生成 - PMD88の音源出力に最適化
    func generateSample(_ timeStep: Float) -> Float {
        channelsLock.lock()
        defer { channelsLock.unlock() }
        
        // ノイズ値を更新
        let noiseValue = updateNoise(timeStep)
        
        // エンベロープ値を更新
        let envelopeValue = updateEnvelope(timeStep) / 15.0  // 0-1の範囲に正規化
        
        var ssgSample: Float = 0
        var activeChannels = 0
        
        // 各チャンネルのサンプルを生成して加算
        for ch in 0..<3 {
            // チャンネルの有効性を確認
            let toneEnabled = channels[ch].enabled
            let noiseEnabled = channels[ch].noiseEnabled
            
            // トーンとノイズの両方が無効ならスキップ
            if !toneEnabled && !noiseEnabled {
                continue
            }
            
            // 矢形波生成 - OPNAのSSG音源仕様に忠実に実装
            var toneValue: Float = channels[ch].lastOutput
            
            // トーン有効時は矢形波を生成
            if toneEnabled && channels[ch].frequency > 0 {
                // カウンターベースの実装
                channels[ch].phase += timeStep * channels[ch].frequency
                
                // 1サイクル完了ごとに出力を反転
                while channels[ch].phase >= 1.0 {
                    channels[ch].phase -= 1.0
                    // 出力を反転
                    channels[ch].lastOutput = -channels[ch].lastOutput
                }
                
                toneValue = channels[ch].lastOutput
            }
            
            // 最終的な波形値の決定
            var outputValue: Float = 0.0
            
            if toneEnabled && !noiseEnabled {
                // トーンのみ有効
                outputValue = toneValue
            } else if !toneEnabled && noiseEnabled {
                // ノイズのみ有効
                outputValue = noiseValue
            } else if toneEnabled && noiseEnabled {
                // トーンとノイズの論理積（両方が正の場合のみ正）
                outputValue = (toneValue > 0 && noiseValue > 0) ? 0.9 : -0.9
            }
            
            // 音量の適用（エンベロープまたは固定音量）
            var amplitude: Float = 0.0
            
            if channels[ch].envelopeEnabled {
                // エンベロープ使用時
                amplitude = envelopeValue
            } else {
                // 固定音量時
                amplitude = channels[ch].volume
            }
            
            // 音量が十分にある場合のみアクティブとみなす
            if amplitude > 0.01 {
                activeChannels += 1
                
                // サンプルに加算
                ssgSample += outputValue * amplitude
                
                // デバッグ出力（ログが多くなりすぎないように適度に間引く）
                if Int.random(in: 0..<10000) < 1 {
                    let waveType = toneEnabled && noiseEnabled ? "トーン+ノイズ" : 
                                  toneEnabled ? "トーン" : "ノイズ"
                    let volType = channels[ch].envelopeEnabled ? "エンベロープ" : 
                                 String(format: "%.2f", amplitude)
                    
                    print("🎵 SSG CH\(ch) 出力: \(waveType), 音量=\(volType), 値=\(String(format: "%.2f", outputValue * amplitude))")
                }
            }
        }
        
        // アクティブなチャンネル数に基づいて出力を調整
        if activeChannels > 1 {
            // 複数チャンネルがアクティブな場合は音量を調整
            ssgSample /= Float(activeChannels) * 0.7
        }
        
        // SSG出力のスケーリング（より正確なミキシング）
        // PMD88のSSG出力レベルに合わせて調整
        // 音量を大きめに設定して聞こえやすくする
        let scaledSample = ssgSample / 3.0 * 2.5
        
        // クリッピング処理
        let clippedSample = max(min(scaledSample, 1.0), -1.0)
        
        // 非常に小さな値はログ出力しない
        if abs(clippedSample) > 0.01 && Int.random(in: 0..<1000) < 1 {
            print("🔊 SSG出力サンプル: \(String(format: "%.3f", clippedSample))")
        }
        
        return clippedSample
    }
    
    // レジスタ値に基づいてSSG状態を更新
    func updateState(registers: [UInt8]) {
        // SSGレジスタの取得（0-15番のレジスタ）
        for i in 0..<16 {
            if i < registers.count {
                ssgRegisters[i] = registers[i]
            } else {
                ssgRegisters[i] = 0
            }
        }
        
        channelsLock.lock()
        defer { channelsLock.unlock() }
        
        // トーン周波数の設定（各チャンネル）
        for ch in 0..<3 {
            let freqLow = UInt16(ssgRegisters[ch * 2])
            let freqHigh = UInt16(ssgRegisters[ch * 2 + 1] & 0x0F)
            let period = (freqHigh << 8) | freqLow
            
            // 周波数計算式（PC-8801のクロックに合わせて）
            // PMD88のSSG周波数計算式に合わせて修正
            // OPNAのSSGクロック = マスタークロック(7.987MHz) / 4 = 約1.996MHz
            let ssgClock: Float = 1996800.0
            
            if period > 0 {
                // 正確な周波数計算: SSGクロック / (32 * period)
                channels[ch].frequency = ssgClock / (32.0 * Float(period))
                // 周期値の設定（カウンターベースの実装用）
                channels[ch].periodValue = Int(period)
            } else {
                channels[ch].frequency = 0
                channels[ch].periodValue = 0
            }
            
            // デバッグログ出力 - 常に出力して確認しやすくする
            if period > 0 {
                print("🎵 SSG CH\(ch) 周波数設定: period=\(period), \(String(format: "%.2f", channels[ch].frequency))Hz")
            }
        }
        
        // ノイズ周波数の設定
        let noisePeriod = UInt16(ssgRegisters[6] & 0x1F)
        let oldNoiseFreq = noiseGen.frequency
        
        // 正確なノイズ周波数計算（OPNA仕様に合わせて）
        // ノイズクロック = SSGクロック / 16 = 約124.8kHz
        let ssgClock: Float = 1996800.0
        let noiseClockDivider: Float = 16.0
        
        if noisePeriod > 0 {
            noiseGen.frequency = ssgClock / (noiseClockDivider * Float(noisePeriod))
        } else {
            noiseGen.frequency = 0
        }
        
        // 周波数が変化した場合のみログ出力
        if oldNoiseFreq != noiseGen.frequency {
            print("🎵 SSG ノイズ周波数設定: period=\(noisePeriod), \(String(format: "%.2f", noiseGen.frequency))Hz")
        }
        
        // ミキサーの設定（トーン/ノイズの有効/無効）
        let mixer = ssgRegisters[7]
        for ch in 0..<3 {
            // PMD88のミキサー設定はビットが反転している（0=有効、1=無効）
            channels[ch].enabled = (mixer & (1 << ch)) == 0  // トーン有効
            channels[ch].noiseEnabled = (mixer & (1 << (ch + 3))) == 0  // ノイズ有効
        }
        
        // 音量とエンベロープの設定
        for ch in 0..<3 {
            let volumeReg = ssgRegisters[8 + ch]
            let oldVolume = channels[ch].volume
            let oldEnvEnabled = channels[ch].envelopeEnabled
            
            // エンベロープ有効フラグ (bit 4 = 1でエンベロープ有効)
            channels[ch].envelopeEnabled = (volumeReg & 0x10) != 0
            
            // 通常の音量設定 (0-15の16段階)
            if !channels[ch].envelopeEnabled {
                channels[ch].volume = Float(volumeReg & 0x0F) / 15.0
            }
            
            // 音量変化があった場合のみログ出力
            if oldVolume != channels[ch].volume || oldEnvEnabled != channels[ch].envelopeEnabled {
                if channels[ch].envelopeEnabled {
                    print("🎵 SSG CH\(ch) 音量: エンベロープ使用")
                } else {
                    print("🎵 SSG CH\(ch) 音量: \(volumeReg & 0x0F)/15 (\(String(format: "%.2f", channels[ch].volume)))")
                }
            }
        }
        
        // エンベロープ周期の設定
        let envLow = UInt16(ssgRegisters[11])
        let envHigh = UInt16(ssgRegisters[12])
        let envPeriod = (envHigh << 8) | envLow
        envelopeGen.period = envPeriod > 0 ? cpuClock / (256.0 * Float(envPeriod)) : 0
        
        // エンベロープ形状の設定
        envelopeGen.shape = ssgRegisters[13]
        
        // アクティブなチャンネルの状態をデバッグ表示
        // var hasActiveChannel = false  // 未使用変数をコメントアウト
        for ch in 0..<3 {
            if channels[ch].enabled && (channels[ch].volume > 0.01 || channels[ch].envelopeEnabled) {
                // hasActiveChannel = true  // 未使用変数をコメントアウト
                
                let waveType = channels[ch].noiseEnabled ? "ノイズ" : "トーン"
                let volType = channels[ch].envelopeEnabled ? "エンベロープ" : String(format: "%.2f", channels[ch].volume)
                
                if channels[ch].frequency > 20 { // 可聴域以上の場合のみログ出力
                    print("🎵 SSG CH\(ch) アクティブ: \(waveType) 周波数=\(channels[ch].frequency)Hz, 音量=\(volType)")
                }
            }
        }
    }
}
