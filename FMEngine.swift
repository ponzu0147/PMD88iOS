class FMEngine {
    // 既存のプロパティ
    private var registers: [UInt8]
    private let sampleRate: Float
    private let fmClock: Float
    
    // 追加が必要なプロパティ
    private var phases: [Float] = Array(repeating: 0.0, count: 6)  // 各チャンネルの位相
    private var envelopes: [Float] = Array(repeating: 1.0, count: 6)  // エンベロープ状態
    private var channelKeyOnState: [Bool] = Array(repeating: false, count: 6) // 各チャンネルのキーオン状態
    
    // 初期化
    init(registers: [UInt8], sampleRate: Float, fmClock: Float = 3993600.0) {
        self.registers = registers
        self.sampleRate = sampleRate
        self.fmClock = fmClock
        
        // デバッグ出力
        print("🎹 FMエンジン初期化: registers.count = \(registers.count), sampleRate = \(sampleRate)")
    }
    
    // レジスタ更新
    func updateRegisters(_ newRegisters: [UInt8]) {
        // キーオン状態の変化を検出
        let oldKeyOnReg = registers[0x28]
        let newKeyOnReg = newRegisters[0x28]
        
        if oldKeyOnReg != newKeyOnReg {
            // キーオン状態が変化した場合、チャンネル状態を更新
            updateKeyOnState(newKeyOnReg)
        }
        
        // レジスタを更新
        self.registers = newRegisters
    }
    
    // キーオン状態の更新
    private func updateKeyOnState(_ keyOnReg: UInt8) {
        // スロットマスク（どのオペレータがONか）
        let slotMask = (keyOnReg >> 4) & 0x0F
        
        // チャンネル番号とグループを取得
        let chNum = keyOnReg & 0x03
        let isSecondGroup = (keyOnReg & 0x04) != 0
        let actualChannel = isSecondGroup ? chNum + 3 : chNum
        
        // このチャンネルがキーオンされているか確認
        let isKeyOn = slotMask != 0
        
        // 状態変化をログ出力
        let oldState = channelKeyOnState[Int(actualChannel)]
        if oldState != isKeyOn {
            print("🔑 CH\(actualChannel) キーオン状態変化: \(oldState ? "オン" : "オフ") -> \(isKeyOn ? "オン" : "オフ"), スロットマスク: 0x\(String(format: "%02X", slotMask))")
        }
        
        // 状態を更新
        channelKeyOnState[Int(actualChannel)] = isKeyOn
    }
    
    // generateSampleメソッドの改善
    func generateSample(_ timeStep: Float) -> Float {
        // アクティブなチャンネルを確認
        var hasActiveChannel = false
        var activeChannels = [Int]()
        
        for ch in 0..<6 {
            if isChannelActive(ch) {
                hasActiveChannel = true
                activeChannels.append(ch)
            }
        }
        
        // デバッグ出力（サンプル生成前）
        if Int.random(in: 0..<1000) < 5 {
            let keyOnReg = registers[0x28]
            print("🎹 キーオン: 0x\(String(format: "%02X", keyOnReg)), アクティブチャンネル: \(activeChannels)")
        }
        
        // アクティブなチャンネルがない場合は0を返す
        if !hasActiveChannel {
            return 0.0
        }
        
        // 各チャンネルの出力を合成
        var output: Float = 0.0
        
        for ch in activeChannels {
            // チャンネルごとの位相を更新
            phases[ch] += getFrequency(ch) * timeStep
            if phases[ch] >= 1.0 {
                phases[ch] -= 1.0
            }
            
            // エンベロープ計算
            envelopes[ch] = calculateEnvelope(ch)
            
            // アルゴリズムに基づいて波形を生成
            let waveform = generateWaveform(ch, phases[ch])
            
            // 音量適用
            let channelOutput = waveform * envelopes[ch] * getChannelVolume(ch)
            output += channelOutput
            
            // サンプル生成のデバッグ（非常に低頻度）
            if Int.random(in: 0..<10000) < 5 {
                print("🎵 CH\(ch) 波形生成: 位相=\(phases[ch]), 波形=\(waveform), エンベロープ=\(envelopes[ch]), 出力=\(channelOutput)")
            }
        }
        
        // 非ゼロ出力の場合はデバッグログ
        if abs(output) > 0.01 && Int.random(in: 0..<1000) < 10 {
            print("🔊 FM出力: \(output), アクティブチャンネル: \(activeChannels.count)個")
        }
        
        return output
    }
    
    // チャンネルがアクティブかどうか判定
    private func isChannelActive(_ ch: Int) -> Bool {
        // 保存されたキーオン状態を使用
        if !channelKeyOnState[ch] {
            return false
        }
        
        // チャンネルパラメータも確認
        let fnum = getChannelFnum(ch)
        let block = getChannelBlock(ch)
        
        // 追加のデバッグ情報（低頻度）
        if Int.random(in: 0..<10000) < 1 {
            print("🔍 CH\(ch) 状態: キーオン=\(channelKeyOnState[ch]), FNUM=\(fnum), BLOCK=\(block)")
        }
        
        // FNUMが0でなければアクティブと判断
        return fnum > 0
    }
    
    // チャンネルのFNUM値を取得
    private func getChannelFnum(_ ch: Int) -> Int {
        let chOffset = ch % 3
        let baseAddr = ch < 3 ? 0xA0 : 0x1A0
        
        let fnumL = registers[baseAddr + chOffset]
        let fnumH = registers[baseAddr + 4 + chOffset]
        
        return (Int(fnumH & 0x07) << 8) | Int(fnumL)
    }
    
    // チャンネルのBLOCK値を取得
    private func getChannelBlock(_ ch: Int) -> Int {
        let chOffset = ch % 3
        let baseAddr = ch < 3 ? 0xA4 : 0x1A4
        
        return Int((registers[baseAddr + chOffset] >> 3) & 0x07)
    }
    
    // 周波数計算
    private func getFrequency(_ ch: Int) -> Float {
        let fnum = getChannelFnum(ch)
        let block = getChannelBlock(ch)
        
        // OPNA FM周波数計算式
        let freq = Float(fnum) * pow(2, Float(block)) * (fmClock / (144.0 * 2048.0))
        return freq / sampleRate
    }
    
    // 波形生成
    private func generateWaveform(_ ch: Int, _ phase: Float) -> Float {
        let chOffset = ch % 3
        let baseAddr = ch < 3 ? 0xB0 : 0x1B0
        
        let algFB = registers[baseAddr + chOffset]
        let algorithm = algFB & 0x07
        let feedback = (algFB >> 3) & 0x07
        
        // アルゴリズムに基づいて波形を生成（簡略化）
        // 実際のFM合成はもっと複雑ですが、簡略化のため単純な正弦波で実装
        let waveform = sin(2.0 * Float.pi * phase)
        
        // フィードバック量に応じて波形を歪ませる（簡略化）
        let feedbackAmount = Float(feedback) / 7.0
        if feedbackAmount > 0 {
            return waveform * (1.0 + feedbackAmount * 0.2 * sin(4.0 * Float.pi * phase))
        } else {
            return waveform
        }
    }
    
    // エンベロープ計算
    private func calculateEnvelope(_ ch: Int) -> Float {
        // TL (Total Level) を取得
        let chOffset = ch % 3
        let baseAddr = ch < 3 ? 0x40 : 0x140
        
        // 4つのオペレータのTL値を取得して逆変換（0が最大音量、127が最小音量）
        let op1TL = Float(registers[baseAddr + chOffset])
        let op2TL = Float(registers[baseAddr + 8 + chOffset])
        let op3TL = Float(registers[baseAddr + 4 + chOffset])
        let op4TL = Float(registers[baseAddr + 12 + chOffset])
        
        // TLは減衰値のため、127から引いて0-127の範囲にし、それを127で割って0-1に正規化
        let env1 = (127.0 - op1TL) / 127.0
        let env2 = (127.0 - op2TL) / 127.0
        let env3 = (127.0 - op3TL) / 127.0
        let env4 = (127.0 - op4TL) / 127.0
        
        // アルゴリズムに基づいて適切なエンベロープを返す
        // 簡略化のため、ここではアルゴリズム7（全オペレータ並列）を想定
        return (env1 + env2 + env3 + env4) * 0.25
    }
    
    // チャンネル音量の取得
    private func getChannelVolume(_ ch: Int) -> Float {
        // 音量を上げる（テスト用）
        return 0.8
    }
}