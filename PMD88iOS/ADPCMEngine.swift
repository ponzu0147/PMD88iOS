import Foundation
import AVFoundation

/// ADPCM音源エンジン
/// YM2608/OPNAのADPCM部分を担当
class ADPCMEngine {
    // ADPCM状態
    struct ADPCMState {
        var enabled: Bool = false     // ADPCM有効/無効
        var playing: Bool = false     // 再生中フラグ
        var startAddress: Int = 0     // 開始アドレス
        var stopAddress: Int = 0      // 終了アドレス
        var currentAddress: Int = 0   // 現在のアドレス
        var volume: Float = 0.0       // 音量 (0-1)
        var pan: Int = 3              // パン設定 (0=右, 1=左, 2=無し, 3=両方)
        var sampleData: [Int8] = []   // ADPCMサンプルデータ
        var lastOutput: Int = 0       // 前回の出力値
        var step: Int = 127           // ステップサイズ
        var isRepeating: Bool = false // リピートモード
        var limit: Int = 0            // リミットアドレス
        var prescaler: Int = 0        // プリスケーラ
        var deltaTime: Float = 0      // サンプル間の時間
        var accumulator: Float = 0    // 時間アキュムレータ
    }
    
    private var state = ADPCMState()
    private let adpcmLock = NSLock() // スレッドセーフのためのロック
    
    private let sampleRate: Float
    private let adpcmClock: Float
    
    // ADPCM用の定数テーブル
    private let stepSizeTable: [Int] = [
        16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45,
        50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143,
        157, 173, 190, 209, 230, 253, 279, 307, 337, 371,
        408, 449, 494, 544, 598, 658, 724, 796, 876, 963,
        1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066,
        2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428,
        4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493,
        10442, 11487, 12635, 13899, 15289, 16818, 18500,
        20350, 22385, 24623, 27086, 29794, 32767
    ]
    
    private let indexTable: [Int] = [
        -1, -1, -1, -1, 2, 4, 6, 8,
        -1, -1, -1, -1, 2, 4, 6, 8
    ]
    
    init(sampleRate: Float, adpcmClock: Float) {
        self.sampleRate = sampleRate
        self.adpcmClock = adpcmClock
        
        // 初期化
        initADPCM()
        
        print("🎵 ADPCM音源初期化完了")
    }
    
    // ADPCM初期化
    private func initADPCM() {
        state.enabled = false
        state.playing = false
        state.volume = 0.0
        state.startAddress = 0
        state.stopAddress = 0
        state.currentAddress = 0
        state.lastOutput = 0
        state.step = 127
        state.isRepeating = false
        state.prescaler = 0
        
        // プリスケーラに基づくデルタタイム計算
        updateDeltaTime()
    }
    
    // プリスケーラに基づくデルタタイム更新
    private func updateDeltaTime() {
        // YM2608のADPCMサンプリングレート計算
        // プリスケーラ: 0=8kHz, 1=16kHz, 2=32kHz
        let adpcmRate: Float
        switch state.prescaler {
        case 0: adpcmRate = adpcmClock / 8000.0
        case 1: adpcmRate = adpcmClock / 16000.0
        case 2: adpcmRate = adpcmClock / 32000.0
        default: adpcmRate = adpcmClock / 8000.0
        }
        
        // サンプル間の時間を計算
        state.deltaTime = 1.0 / adpcmRate
    }
    
    // ADPCMデータのデコード
    private func decodeADPCM(nibble: Int) -> Int {
        let step = state.step
        var difference = 0
        
        // 4ビットADPCMデータから差分を計算
        if (nibble & 4) != 0 { difference += step }
        if (nibble & 2) != 0 { difference += step >> 1 }
        if (nibble & 1) != 0 { difference += step >> 2 }
        difference += step >> 3
        
        // 符号ビットに基づいて加算または減算
        if (nibble & 8) != 0 {
            state.lastOutput -= difference
        } else {
            state.lastOutput += difference
        }
        
        // 出力値のクリッピング
        state.lastOutput = max(min(state.lastOutput, 32767), -32768)
        
        // ステップサイズの更新
        let index = state.step + indexTable[nibble & 0x7]
        state.step = max(min(index, 48000), 0)
        
        return state.lastOutput
    }
    
    // ADPCM音源のサンプル生成
    func generateSample(_ timeStep: Float) -> Float {
        adpcmLock.lock()
        defer { adpcmLock.unlock() }
        
        if !state.enabled || !state.playing || state.sampleData.isEmpty {
            return 0.0 // 無効または再生中でない場合は無音
        }
        
        // 時間アキュムレータの更新
        state.accumulator += timeStep
        
        var output: Float = 0.0
        
        // 十分な時間が経過したらサンプルを処理
        while state.accumulator >= state.deltaTime && state.playing {
            state.accumulator -= state.deltaTime
            
            // 現在のアドレスが有効範囲内かチェック
            if state.currentAddress < state.stopAddress {
                // ADPCMデータの取得（1バイトに2サンプル）
                if state.currentAddress / 2 < state.sampleData.count {
                    let dataByte = state.sampleData[state.currentAddress / 2]
                    let nibble: Int
                    
                    if (state.currentAddress & 1) == 0 {
                        // 上位4ビット
                        nibble = Int((dataByte >> 4) & 0x0F)
                    } else {
                        // 下位4ビット
                        nibble = Int(dataByte & 0x0F)
                    }
                    
                    // ADPCMデコード
                    let sample = decodeADPCM(nibble: nibble)
                    output = Float(sample) / 32768.0 // 正規化
                    
                    // アドレスを進める
                    state.currentAddress += 1
                } else {
                    // データ範囲外
                    state.playing = false
                }
            } else {
                // 終了アドレスに達した
                if state.isRepeating {
                    // リピートモードの場合は先頭に戻る
                    state.currentAddress = state.startAddress
                    state.lastOutput = 0
                    state.step = 127
                } else {
                    // リピートしない場合は停止
                    state.playing = false
                }
            }
        }
        
        // 音量適用
        return output * state.volume
    }
    
    // ADPCMデータのロード
    func loadADPCMData(_ data: [Int8], startAddress: Int, stopAddress: Int) {
        adpcmLock.lock()
        defer { adpcmLock.unlock() }
        
        state.sampleData = data
        state.startAddress = startAddress
        state.stopAddress = stopAddress
        state.currentAddress = startAddress
        state.lastOutput = 0
        state.step = 127
        
        print("🎵 ADPCMデータロード: \(data.count)バイト, 開始=\(startAddress), 終了=\(stopAddress)")
    }
    
    // ADPCM再生開始
    func startPlayback() {
        adpcmLock.lock()
        defer { adpcmLock.unlock() }
        
        if state.enabled && !state.sampleData.isEmpty {
            state.playing = true
            state.currentAddress = state.startAddress
            state.lastOutput = 0
            state.step = 127
            state.accumulator = 0
            
            print("🎵 ADPCM再生開始")
        }
    }
    
    // ADPCM再生停止
    func stopPlayback() {
        adpcmLock.lock()
        defer { adpcmLock.unlock() }
        
        state.playing = false
        print("🎵 ADPCM再生停止")
    }
    
    // レジスタ値に基づいてADPCM状態を更新
    func updateState(registers: [UInt8]) {
        adpcmLock.lock()
        defer { adpcmLock.unlock() }
        
        // ADPCMの有効/無効 (0x100)
        if registers.count > 0x100 {
            let control = registers[0x100]
            let newEnabled = (control & 0x80) != 0
            
            // 状態が変わった場合のみ処理
            if state.enabled != newEnabled {
                state.enabled = newEnabled
                print("🎵 ADPCM: \(state.enabled ? "有効" : "無効")")
            }
            
            // リピートモード (0x100 bit 4)
            state.isRepeating = (control & 0x10) != 0
            
            // 再生/停止の制御 (0x100 bit 0)
            let startBit = (control & 0x01) != 0
            if startBit && !state.playing && state.enabled {
                startPlayback()
            } else if !startBit && state.playing {
                stopPlayback()
            }
        }
        
        // 開始アドレス (0x102, 0x103)
        if registers.count > 0x103 {
            let startLow = registers[0x102]
            let startHigh = registers[0x103]
            state.startAddress = (Int(startHigh) << 8) | Int(startLow)
        }
        
        // 終了アドレス (0x104, 0x105)
        if registers.count > 0x105 {
            let stopLow = registers[0x104]
            let stopHigh = registers[0x105]
            state.stopAddress = (Int(stopHigh) << 8) | Int(stopLow)
        }
        
        // プリスケーラ設定 (0x101)
        if registers.count > 0x101 {
            state.prescaler = Int(registers[0x101] & 0x03)
            updateDeltaTime()
        }
        
        // 音量設定 (0x108)
        if registers.count > 0x108 {
            state.volume = Float(registers[0x108] & 0x3F) / 63.0
        }
        
        // リミットアドレス (0x106, 0x107) - リピート時の終了位置
        if registers.count > 0x107 {
            let limitLow = registers[0x106]
            let limitHigh = registers[0x107]
            state.limit = (Int(limitHigh) << 8) | Int(limitLow)
        }
    }
    
    // ADPCMメモリへの書き込み
    func writeMemory(address: Int, data: [Int8]) {
        adpcmLock.lock()
        defer { adpcmLock.unlock() }
        
        // メモリ領域の拡張（必要に応じて）
        let requiredSize = address + data.count
        if state.sampleData.count < requiredSize {
            state.sampleData.append(contentsOf: [Int8](repeating: 0, count: requiredSize - state.sampleData.count))
        }
        
        // データの書き込み
        for i in 0..<data.count {
            if address + i < state.sampleData.count {
                state.sampleData[address + i] = data[i]
            }
        }
    }
    
    // ADPCMメモリからの読み込み
    func readMemory(address: Int, length: Int) -> [Int8] {
        adpcmLock.lock()
        defer { adpcmLock.unlock() }
        
        var result = [Int8]()
        
        for i in 0..<length {
            if address + i < state.sampleData.count {
                result.append(state.sampleData[address + i])
            } else {
                result.append(0)
            }
        }
        
        return result
    }
}
