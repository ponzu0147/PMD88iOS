//
//  FMGenerator.swift
//  PMD88iOS
//
//  Created by 越川将人 on 2025/03/22.
//

import Foundation
import AVFoundation

/// YM2608（OPNA）チップのFM合成部分をエミュレートするクラス
class FMGenerator {
    // 基本パラメータ
    private let sampleRate: Float
    private let fmClock: Float
    
    // チャンネル数とオペレータ数
    private let channelCount = FMConstants.channelCount
    private let operatorsPerChannel = FMConstants.operatorsPerChannel
    
    // オペレータとアルゴリズム
    private var operators: [[FMOperator]]
    private var algorithms: [FMAlgorithm]
    
    // チャンネルパラメータ
    private var fnums: [Int]
    private var blocks: [Int]
    private var keyOnStates: [Bool]
    
    // レジスタバッファ
    private var registers: [UInt8]
    
    // デバッグ用
    private var debugMode: Bool = true
    private var sampleCounter: Int = 0
    
    // 初期化
    init(sampleRate: Float, fmClock: Float = FMConstants.baseClock) {
        self.sampleRate = sampleRate
        self.fmClock = fmClock
        
        // レジスタ初期化
        registers = Array(repeating: 0, count: 512)
        
        // チャンネルパラメータ初期化
        fnums = Array(repeating: 0, count: channelCount)
        blocks = Array(repeating: 0, count: channelCount)
        keyOnStates = Array(repeating: false, count: channelCount)
        
        // オペレータ初期化
        operators = Array(repeating: [], count: channelCount)
        for ch in 0..<channelCount {
            operators[ch] = Array(repeating: FMOperator(), count: operatorsPerChannel)
        }
        
        // アルゴリズム初期化
        algorithms = Array(repeating: FMAlgorithm(), count: channelCount)
        
        print("🎹 FMGenerator初期化: sampleRate=\(sampleRate), fmClock=\(fmClock)")
    }
    
    // レジスタ更新
    func updateRegisters(_ newRegisters: [UInt8]) {
        // 前回のキーオン状態を保存
        let oldKeyOnReg = registers[FMRegisterOffsets.keyOn]
        let newKeyOnReg = newRegisters[FMRegisterOffsets.keyOn]
        
        // レジスタを更新
        registers = newRegisters
        
        // キーオン状態の変化を検出
        if oldKeyOnReg != newKeyOnReg {
            handleKeyOnChange(newKeyOnReg)
        }
        
        // 各チャンネルのパラメータを更新
        updateChannelParameters()
        
        // 各オペレータのパラメータを更新
        updateOperatorParameters()
    }
    
    // キーオン状態の変化を処理
    private func handleKeyOnChange(_ keyOnReg: UInt8) {
        // スロットマスク（どのオペレータがONか）
        let slotMask = (keyOnReg >> 4) & 0x0F
        
        // チャンネル番号とグループを取得
        let chNum = keyOnReg & 0x03
        let isSecondGroup = (keyOnReg & 0x04) != 0
        let actualChannel = isSecondGroup ? Int(chNum) + 3 : Int(chNum)
        
        // このチャンネルがキーオンされているか確認
        let isKeyOn = slotMask != 0
        
        // 前の状態と異なる場合のみ処理
        if keyOnStates[actualChannel] != isKeyOn {
            keyOnStates[actualChannel] = isKeyOn
            
            print("🔑 CH\(actualChannel) キーオン状態変化: \(isKeyOn ? "オン" : "オフ"), スロットマスク: 0x\(String(format: "%02X", slotMask))")
            
            // 各オペレータのキーオン/オフを設定
            for op in 0..<operatorsPerChannel {
                let opMask = 1 << op
                let isOpOn = (slotMask & UInt8(opMask)) != 0
                
                if isKeyOn && isOpOn {
                    operators[actualChannel][op].keyOn()
                } else {
                    operators[actualChannel][op].keyOff()
                }
            }
        }
    }
    
    // チャンネルパラメータの更新
    private func updateChannelParameters() {
        for ch in 0..<channelCount {
            // チャンネルのグループとオフセットを計算
            let group = ch >= 3 ? 1 : 0
            let offset = ch % 3
            
            // FNUMとBLOCKを取得
            let fnumLowAddr = (group == 0) ? FMRegisterOffsets.fnum_low + offset : FMRegisterOffsets.fnum_low + offset + 0x100
            let fnumHighAddr = (group == 0) ? FMRegisterOffsets.fnum_high_block + offset : FMRegisterOffsets.fnum_high_block + offset + 0x100
            
            let fnumLow = registers[fnumLowAddr]
            let fnumHighBlock = registers[fnumHighAddr]
            
            fnums[ch] = Int(fnumLow) | (Int(fnumHighBlock & 0x07) << 8)
            blocks[ch] = Int((fnumHighBlock >> 3) & 0x07)
            
            // アルゴリズムとフィードバックを設定
            let fbAlgAddr = (group == 0) ? FMRegisterOffsets.feedback_algorithm + offset : FMRegisterOffsets.feedback_algorithm + offset + 0x100
            let fbAlg = registers[fbAlgAddr]
            
            algorithms[ch].setRegister(value: fbAlg)
        }
    }
    
    // オペレータパラメータの更新
    private func updateOperatorParameters() {
        for ch in 0..<channelCount {
            let group = ch >= 3 ? 1 : 0
            let offset = ch % 3
            
            for op in 0..<operatorsPerChannel {
                // オペレータのレジスタアドレスを計算
                let baseOffset = op * 4 + offset
                let groupOffset = group == 0 ? 0 : 0x100
                
                // 各パラメータのレジスタアドレス
                let dtMlAddr = FMRegisterOffsets.detune_multiple + baseOffset + groupOffset
                let tlAddr = FMRegisterOffsets.totalLevel + baseOffset + groupOffset
                let ksArAddr = FMRegisterOffsets.keyScale_attackRate + baseOffset + groupOffset
                let drAddr = FMRegisterOffsets.decayRate + baseOffset + groupOffset
                let srAddr = FMRegisterOffsets.sustainRate + baseOffset + groupOffset
                let slRrAddr = FMRegisterOffsets.sustainLevel_releaseRate + baseOffset + groupOffset
                
                // レジスタ値を取得してオペレータに設定
                operators[ch][op].setRegister(address: dtMlAddr, value: registers[dtMlAddr])
                operators[ch][op].setRegister(address: tlAddr, value: registers[tlAddr])
                operators[ch][op].setRegister(address: ksArAddr, value: registers[ksArAddr])
                operators[ch][op].setRegister(address: drAddr, value: registers[drAddr])
                operators[ch][op].setRegister(address: srAddr, value: registers[srAddr])
                operators[ch][op].setRegister(address: slRrAddr, value: registers[slRrAddr])
            }
        }
    }
    
    // サンプル生成
    func generateSample() -> Float {
        var output: Float = 0.0
        
        // アクティブなチャンネルを確認
        var activeChannels = [Int]()
        for ch in 0..<channelCount {
            if isChannelActive(ch) {
                activeChannels.append(ch)
            }
        }
        
        // デバッグ出力（低頻度）
        if debugMode && sampleCounter % 10000 == 0 {
            print("🎹 アクティブチャンネル: \(activeChannels)")
        }
        
        // 各アクティブチャンネルのサンプルを生成
        for ch in activeChannels {
            let channelOutput = generateChannelSample(ch)
            output += channelOutput
            
            // デバッグ出力（非常に低頻度）
            if debugMode && sampleCounter % 100000 == 0 {
                print("🎵 CH\(ch) 出力: \(channelOutput)")
            }
        }
        
        // 出力を正規化（-1.0〜1.0の範囲に収める）
        output = max(-1.0, min(1.0, output))
        
        // サンプルカウンタを更新
        sampleCounter += 1
        
        return output
    }
    
    // チャンネルのサンプル生成
    private func generateChannelSample(_ ch: Int) -> Float {
        // 位相増分を計算（FNUM、BLOCK、サンプルレートに基づく）
        let phaseIncrement = calculatePhaseIncrement(ch)
        
        // アルゴリズムに基づいてオペレータの出力を計算
        let algorithmType = algorithms[ch].getAlgorithmType()
        let feedback = algorithms[ch].calculateFeedback(op1Output: operators[ch][0].getOutputLevel())
        
        var opOutputs: [Float] = Array(repeating: 0.0, count: operatorsPerChannel)
        
        // アルゴリズムに基づいて各オペレータの出力を計算
        switch algorithmType {
        case .alg0:
            // OP1->OP2->OP3->OP4
            opOutputs[0] = operators[ch][0].generate(phaseIncrement: phaseIncrement, modulation: feedback)
            opOutputs[1] = operators[ch][1].generate(phaseIncrement: phaseIncrement, modulation: opOutputs[0])
            opOutputs[2] = operators[ch][2].generate(phaseIncrement: phaseIncrement, modulation: opOutputs[1])
            opOutputs[3] = operators[ch][3].generate(phaseIncrement: phaseIncrement, modulation: opOutputs[2])
            return opOutputs[3]
            
        case .alg1:
            // (OP1+OP2)->OP3->OP4
            opOutputs[0] = operators[ch][0].generate(phaseIncrement: phaseIncrement, modulation: feedback)
            opOutputs[1] = operators[ch][1].generate(phaseIncrement: phaseIncrement)
            opOutputs[2] = operators[ch][2].generate(phaseIncrement: phaseIncrement, modulation: opOutputs[0] + opOutputs[1])
            opOutputs[3] = operators[ch][3].generate(phaseIncrement: phaseIncrement, modulation: opOutputs[2])
            return opOutputs[3]
            
        case .alg2:
            // OP1->(OP2+OP3)->OP4
            opOutputs[0] = operators[ch][0].generate(phaseIncrement: phaseIncrement, modulation: feedback)
            opOutputs[1] = operators[ch][1].generate(phaseIncrement: phaseIncrement, modulation: opOutputs[0])
            opOutputs[2] = operators[ch][2].generate(phaseIncrement: phaseIncrement, modulation: opOutputs[0])
            opOutputs[3] = operators[ch][3].generate(phaseIncrement: phaseIncrement, modulation: opOutputs[1] + opOutputs[2])
            return opOutputs[3]
            
        case .alg3:
            // OP1->OP2, OP3->OP4
            opOutputs[0] = operators[ch][0].generate(phaseIncrement: phaseIncrement, modulation: feedback)
            opOutputs[1] = operators[ch][1].generate(phaseIncrement: phaseIncrement, modulation: opOutputs[0])
            opOutputs[2] = operators[ch][2].generate(phaseIncrement: phaseIncrement)
            opOutputs[3] = operators[ch][3].generate(phaseIncrement: phaseIncrement, modulation: opOutputs[2])
            return opOutputs[1] + opOutputs[3]
            
        case .alg4:
            // OP1->OP2, OP3, OP4
            opOutputs[0] = operators[ch][0].generate(phaseIncrement: phaseIncrement, modulation: feedback)
            opOutputs[1] = operators[ch][1].generate(phaseIncrement: phaseIncrement, modulation: opOutputs[0])
            opOutputs[2] = operators[ch][2].generate(phaseIncrement: phaseIncrement)
            opOutputs[3] = operators[ch][3].generate(phaseIncrement: phaseIncrement)
            return opOutputs[1] + opOutputs[2] + opOutputs[3]
            
        case .alg5:
            // OP1, OP2->OP3, OP4
            opOutputs[0] = operators[ch][0].generate(phaseIncrement: phaseIncrement, modulation: feedback)
            opOutputs[1] = operators[ch][1].generate(phaseIncrement: phaseIncrement)
            opOutputs[2] = operators[ch][2].generate(phaseIncrement: phaseIncrement, modulation: opOutputs[1])
            opOutputs[3] = operators[ch][3].generate(phaseIncrement: phaseIncrement)
            return opOutputs[0] + opOutputs[2] + opOutputs[3]
            
        case .alg6, .alg7:
            // OP1, OP2, OP3, OP4（すべて並列）
            opOutputs[0] = operators[ch][0].generate(phaseIncrement: phaseIncrement, modulation: feedback)
            opOutputs[1] = operators[ch][1].generate(phaseIncrement: phaseIncrement)
            opOutputs[2] = operators[ch][2].generate(phaseIncrement: phaseIncrement)
            opOutputs[3] = operators[ch][3].generate(phaseIncrement: phaseIncrement)
            return opOutputs[0] + opOutputs[1] + opOutputs[2] + opOutputs[3]
        }
    }
    
    // 位相増分の計算
    private func calculatePhaseIncrement(_ ch: Int) -> Float {
        let fnum = Float(fnums[ch])
        let block = Float(blocks[ch])
        
        // YM2608の周波数計算式
        // F = (FNUM * 2^BLOCK * fmClock) / (2^20)
        let freq = fnum * pow(2.0, block) * fmClock / pow(2.0, 20.0)
        
        // 位相増分 = 周波数 / サンプルレート
        return freq / sampleRate
    }
    
    // チャンネルがアクティブかどうか判定
    private func isChannelActive(_ ch: Int) -> Bool {
        // キーオン状態を確認
        if !keyOnStates[ch] {
            return false
        }
        
        // FNUMが0でないことを確認
        return fnums[ch] > 0
    }
    
    // チャンネルの状態情報を取得
    func getChannelInfo(_ ch: Int) -> [String: Any] {
        guard ch >= 0 && ch < channelCount else {
            return [:]
        }
        
        var info: [String: Any] = [:]
        info["keyOn"] = keyOnStates[ch]
        info["fnum"] = fnums[ch]
        info["block"] = blocks[ch]
        info["algorithm"] = algorithms[ch].getAlgorithmType().rawValue
        info["feedback"] = algorithms[ch].getFeedback()
        
        var opInfo: [[String: Any]] = []
        for op in 0..<operatorsPerChannel {
            let opState = operators[ch][op].getEnvelopeState()
            let opLevel = operators[ch][op].getOutputLevel()
            
            opInfo.append([
                "state": String(describing: opState),
                "level": opLevel
            ])
        }
        info["operators"] = opInfo
        
        return info
    }
    
    // テスト音を設定
    func setupTestTone(channel: Int = 0, note: Int = 60) {
        // C4 (ミドルC) = MIDI Note 60
        // A4 (440Hz) = MIDI Note 69
        
        // MIDIノートから周波数を計算
        let freq = 440.0 * pow(2.0, Float(note - 69) / 12.0)
        
        // 周波数からFNUMとBLOCKを計算
        let fNumValue = Int(freq * pow(2.0, 20.0) / fmClock)
        let blockValue = 4  // 一般的な値
        
        // レジスタ設定
        let chOffset = channel % 3
        let group = channel >= 3 ? 1 : 0
        let groupOffset = group == 0 ? 0 : 0x100
        
        // FNUM設定
        let fnumLowAddr = FMRegisterOffsets.fnum_low + chOffset + groupOffset
        let fnumHighAddr = FMRegisterOffsets.fnum_high_block + chOffset + groupOffset
        
        registers[fnumLowAddr] = UInt8(fNumValue & 0xFF)
        registers[fnumHighAddr] = UInt8((fNumValue >> 8) & 0x07) | UInt8(blockValue << 3)
        
        // アルゴリズムとフィードバック設定
        let fbAlgAddr = FMRegisterOffsets.feedback_algorithm + chOffset + groupOffset
        registers[fbAlgAddr] = 0x07  // アルゴリズム7、フィードバック0
        
        // オペレータ設定
        for op in 0..<operatorsPerChannel {
            let baseOffset = op * 4 + chOffset
            
            // TL（音量）設定
            let tlAddr = FMRegisterOffsets.totalLevel + baseOffset + groupOffset
            registers[tlAddr] = op == 3 ? 0 : 32  // OP4のみ最大音量、他は中程度
            
            // AR（アタックレート）設定
            let ksArAddr = FMRegisterOffsets.keyScale_attackRate + baseOffset + groupOffset
            registers[ksArAddr] = 31  // 最速アタック
            
            // DR、SR、RR設定
            let drAddr = FMRegisterOffsets.decayRate + baseOffset + groupOffset
            let srAddr = FMRegisterOffsets.sustainRate + baseOffset + groupOffset
            let slRrAddr = FMRegisterOffsets.sustainLevel_releaseRate + baseOffset + groupOffset
            
            registers[drAddr] = 0  // ディケイなし
            registers[srAddr] = 0  // サスティンなし
            registers[slRrAddr] = 0  // サスティンレベル0、リリースレート0
        }
        
        // パラメータ更新
        updateChannelParameters()
        updateOperatorParameters()
        
        // キーオン
        let keyOnValue: UInt8 = 0xF0 | UInt8(channel)  // 全オペレータON
        registers[FMRegisterOffsets.keyOn] = keyOnValue
        handleKeyOnChange(keyOnValue)
        
        print("🎵 テスト音設定完了: CH\(channel) ALG=7 FB=0, MIDI Note \(note)")
    }
}
