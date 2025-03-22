import Foundation
import AVFoundation

/// リズム音源エンジン
/// YM2608/OPNAのリズム音源部分を担当
class RhythmEngine {
    // リズム音源のチャンネル
    enum RhythmChannel: Int, CaseIterable {
        case bass = 0      // バスドラム
        case snare = 1     // スネアドラム
        case cymbal = 2    // シンバル
        case hihat = 3     // ハイハット
        case tom = 4       // タム
        case rim = 5       // リムショット
        
        var name: String {
            switch self {
            case .bass: return "バスドラム"
            case .snare: return "スネアドラム"
            case .cymbal: return "シンバル"
            case .hihat: return "ハイハット"
            case .tom: return "タム"
            case .rim: return "リムショット"
            }
        }
    }
    
    // リズム音源の状態
    struct RhythmState {
        var enabled: Bool = false     // リズム音源全体の有効/無効
        var volume: Float = 0.0       // 全体音量 (0-1)
        var channelMask: UInt8 = 0    // 各チャンネルの有効/無効マスク
        var channelVolumes: [Float] = Array(repeating: 0.0, count: 6) // 各チャンネルの音量
        var channelPans: [Int] = Array(repeating: 3, count: 6)        // 各チャンネルのパン (0=右, 1=左, 2=無し, 3=両方)
    }
    
    // リズム音源のサンプル
    struct RhythmSample {
        var data: [Float] = []        // サンプルデータ
        var length: Int = 0           // サンプル長
        var position: Int = 0         // 現在の再生位置
        var playing: Bool = false     // 再生中フラグ
        var volume: Float = 0.0       // 音量 (0-1)
        var pan: Int = 3              // パン設定
    }
    
    private var state = RhythmState()
    private var samples: [RhythmSample] = Array(repeating: RhythmSample(), count: 6)
    private let rhythmLock = NSLock() // スレッドセーフのためのロック
    
    private let sampleRate: Float
    
    init(sampleRate: Float) {
        self.sampleRate = sampleRate
        
        // 初期化
        initRhythmSamples()
        
        print("🥁 リズム音源初期化完了")
    }
    
    // リズムサンプルの初期化（実際のサンプルデータは後で読み込む）
    private func initRhythmSamples() {
        // 各リズム音源の初期化
        for ch in RhythmChannel.allCases {
            let index = ch.rawValue
            samples[index] = RhythmSample()
            samples[index].playing = false
            samples[index].volume = 0.0
            samples[index].pan = 3 // デフォルトは両方
            
            // 音量初期化
            state.channelVolumes[index] = 0.0
            state.channelPans[index] = 3
        }
        
        // リズム音源全体の初期化
        state.enabled = false
        state.volume = 0.0
        state.channelMask = 0
        
        // サンプルデータの読み込み（実際のアプリではここでファイルから読み込む）
        loadDummySamples()
    }
    
    // ダミーのサンプルデータを生成（実際のアプリでは実際のサンプルを読み込む）
    private func loadDummySamples() {
        // バスドラム - 低い周波数の短いサイン波
        generateDummySample(for: .bass, frequency: 60, length: 0.1)
        
        // スネアドラム - ノイズベースの短いサンプル
        generateNoiseBasedSample(for: .snare, length: 0.08)
        
        // シンバル - 高周波ノイズの長めのサンプル
        generateNoiseBasedSample(for: .cymbal, length: 0.3, highPass: true)
        
        // ハイハット - 高周波ノイズの短いサンプル
        generateNoiseBasedSample(for: .hihat, length: 0.05, highPass: true)
        
        // タム - 中周波数のサイン波
        generateDummySample(for: .tom, frequency: 100, length: 0.15)
        
        // リムショット - 短い高周波パルス
        generateDummySample(for: .rim, frequency: 800, length: 0.01)
    }
    
    // ダミーのサイン波ベースのサンプルを生成
    private func generateDummySample(for channel: RhythmChannel, frequency: Float, length: Float) {
        let sampleCount = Int(sampleRate * length)
        var sampleData = [Float](repeating: 0.0, count: sampleCount)
        
        for i in 0..<sampleCount {
            let t = Float(i) / sampleRate
            let amplitude = exp(-t * 10.0) // 指数関数的減衰
            sampleData[i] = sin(2.0 * Float.pi * frequency * t) * amplitude
        }
        
        let index = channel.rawValue
        samples[index].data = sampleData
        samples[index].length = sampleCount
        samples[index].position = 0
    }
    
    // ノイズベースのサンプルを生成
    private func generateNoiseBasedSample(for channel: RhythmChannel, length: Float, highPass: Bool = false) {
        let sampleCount = Int(sampleRate * length)
        var sampleData = [Float](repeating: 0.0, count: sampleCount)
        
        // ノイズ生成
        for i in 0..<sampleCount {
            let t = Float(i) / sampleRate
            let amplitude = exp(-t * 15.0) // 指数関数的減衰
            let noise = Float.random(in: -1.0...1.0)
            
            if highPass {
                // 高周波ノイズ（ハイハット、シンバル用）
                sampleData[i] = noise * amplitude * (sin(2.0 * Float.pi * 800.0 * t) + 1.0) / 2.0
            } else {
                // 通常ノイズ（スネア用）
                sampleData[i] = noise * amplitude
            }
        }
        
        let index = channel.rawValue
        samples[index].data = sampleData
        samples[index].length = sampleCount
        samples[index].position = 0
    }
    
    // リズム音源のサンプル生成
    func generateSample() -> Float {
        rhythmLock.lock()
        defer { rhythmLock.unlock() }
        
        if !state.enabled {
            return 0.0 // リズム音源が無効なら無音
        }
        
        var mixedOutput: Float = 0.0
        
        // 各リズムチャンネルの処理
        for ch in RhythmChannel.allCases {
            let index = ch.rawValue
            let channelBit = UInt8(1 << index)
            
            if (state.channelMask & channelBit) != 0 && samples[index].playing {
                // サンプルが再生中なら出力に加算
                if samples[index].position < samples[index].length {
                    let sampleValue = samples[index].data[samples[index].position]
                    
                    // 音量とパンを適用
                    let volume = samples[index].volume * state.channelVolumes[index] * state.volume
                    mixedOutput += sampleValue * volume
                    
                    // 再生位置を進める
                    samples[index].position += 1
                } else {
                    // 再生終了
                    samples[index].playing = false
                    samples[index].position = 0
                }
            }
        }
        
        return mixedOutput
    }
    
    // リズム音を再生
    func triggerRhythm(_ channel: RhythmChannel, volume: Float = 1.0) {
        rhythmLock.lock()
        defer { rhythmLock.unlock() }
        
        if !state.enabled {
            return // リズム音源が無効なら何もしない
        }
        
        let index = channel.rawValue
        let channelBit = UInt8(1 << index)
        
        if (state.channelMask & channelBit) != 0 {
            // サンプルを再生開始
            samples[index].position = 0
            samples[index].playing = true
            samples[index].volume = volume
            
            print("🥁 リズム音源再生: \(channel.name)")
        }
    }
    
    // レジスタ値に基づいてリズム音源状態を更新
    func updateState(registers: [UInt8]) {
        rhythmLock.lock()
        defer { rhythmLock.unlock() }
        
        // リズム音源の有効/無効 (0x10)
        if registers.count > 0x10 {
            state.enabled = (registers[0x10] & 0x80) != 0
            print("🥁 リズム音源: \(state.enabled ? "有効" : "無効")")
        }
        
        // リズムチャンネルのマスク (0x10)
        if registers.count > 0x10 {
            state.channelMask = registers[0x10] & 0x3F
        }
        
        // 全体音量 (0x11)
        if registers.count > 0x11 {
            state.volume = Float(registers[0x11] & 0x3F) / 63.0
        }
        
        // 各チャンネルの音量とパン (0x18-0x1D)
        for ch in RhythmChannel.allCases {
            let index = ch.rawValue
            let regIndex = 0x18 + index
            
            if registers.count > regIndex {
                let volPan = registers[regIndex]
                state.channelVolumes[index] = Float(volPan & 0x1F) / 31.0
                state.channelPans[index] = Int((volPan >> 6) & 0x03)
                
                // サンプルにも設定を反映
                samples[index].volume = state.channelVolumes[index]
                samples[index].pan = state.channelPans[index]
            }
        }
    }
    
    // キーオンデータに基づいてリズム音を再生
    func processKeyOn(keyData: UInt8) {
        // キーオンビットをチェック
        for ch in RhythmChannel.allCases {
            let index = ch.rawValue
            let channelBit = UInt8(1 << index)
            
            if (keyData & channelBit) != 0 {
                // 対応するリズム音を再生
                triggerRhythm(ch)
            }
        }
    }
}
