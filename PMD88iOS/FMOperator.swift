//
//  FMOperator.swift
//  PMD88iOS
//
//  Created by 越川将人 on 2025/03/22.
//

import Foundation

class FMOperator {
    // 基本パラメータ
    private var detune: Int = 0
    private var multiple: Int = 1
    private var totalLevel: Float = 0
    private var keyScale: Int = 0
    private var attackRate: Int = 0
    private var decayRate: Int = 0
    private var sustainRate: Int = 0
    private var sustainLevel: Int = 0
    private var releaseRate: Int = 0
    
    // 状態変数
    private var phase: Float = 0.0
    private var output: Float = 0.0
    private var envelopeLevel: Float = FMConstants.maxAttenuation
    private var envelopeState: EnvelopeState = .off
    
    // 波形テーブル
    private var sineTable: [Float] = []
    
    // 初期化
    init() {
        // サイン波テーブルの初期化
        sineTable = Array(repeating: 0.0, count: FMConstants.waveTableSize)
        for i in 0..<FMConstants.waveTableSize {
            let angle = 2.0 * Float.pi * Float(i) / Float(FMConstants.waveTableSize)
            sineTable[i] = sin(angle)
        }
    }
    
    // レジスタ値からパラメータを設定
    func setRegister(address: Int, value: UInt8) {
        let offset = address & 0xF0
        _ = address & 0x03
        
        switch offset {
        case FMRegisterOffsets.detune_multiple:
            detune = Int((value >> 4) & 0x07)
            multiple = Int(value & 0x0F)
            print("🎹 OP設定: DT=\(detune), ML=\(multiple)")
            
        case FMRegisterOffsets.totalLevel:
            totalLevel = Float(value & 0x7F)
            print("🎹 OP設定: TL=\(totalLevel)")
            
        case FMRegisterOffsets.keyScale_attackRate:
            keyScale = Int((value >> 6) & 0x03)
            attackRate = Int(value & 0x1F)
            print("🎹 OP設定: KS=\(keyScale), AR=\(attackRate)")
            
        case FMRegisterOffsets.decayRate:
            decayRate = Int(value & 0x1F)
            print("🎹 OP設定: DR=\(decayRate)")
            
        case FMRegisterOffsets.sustainRate:
            sustainRate = Int(value & 0x1F)
            print("🎹 OP設定: SR=\(sustainRate)")
            
        case FMRegisterOffsets.sustainLevel_releaseRate:
            sustainLevel = Int(Float((value >> 4) & 0x0F))
            releaseRate = Int(value & 0x0F)
            print("🎹 OP設定: SL=\(sustainLevel), RR=\(releaseRate)")
            
        default:
            break
        }
    }
    
    // キーオン処理
    func keyOn() {
        if envelopeState == .off {
            envelopeState = .attack
            envelopeLevel = FMConstants.maxAttenuation
            print("🔑 オペレータキーオン: AR=\(attackRate)")
        }
    }
    
    // キーオフ処理
    func keyOff() {
        if envelopeState != .off {
            envelopeState = .release
            print("🔑 オペレータキーオフ: RR=\(releaseRate)")
        }
    }
    
    // サンプル生成
    func generate(phaseIncrement: Float, modulation: Float = 0.0) -> Float {
        // 位相更新（デチューンとマルチプルを適用）
        let actualIncrement = phaseIncrement * Float(multiple) * (1.0 + Float(detune - 3) * 0.01)
        phase += actualIncrement
        while phase >= 1.0 {
            phase -= 1.0
        }
        
        // エンベロープ更新
        updateEnvelope()
        
        // 波形生成（モジュレーション適用）
        let modulatedPhase = phase + modulation
        let phaseIndex = Int((modulatedPhase.truncatingRemainder(dividingBy: 1.0)) * Float(FMConstants.waveTableSize)) % FMConstants.waveTableSize

        // 出力計算（エンベロープ適用）
        let envelopeGain = (FMConstants.maxAttenuation - envelopeLevel) / FMConstants.maxAttenuation
        output = sineTable[phaseIndex] * envelopeGain
        
        return output
    }
    
    // エンベロープ更新
    private func updateEnvelope() {
        switch envelopeState {
        case .attack:
            if attackRate > 0 {
                // アタックレート適用
                let attackCoef = Float(attackRate) / 31.0
                envelopeLevel -= (FMConstants.maxAttenuation * attackCoef * 0.1)
                if envelopeLevel <= 0 {
                    envelopeLevel = 0
                    envelopeState = .decay
                }
            } else {
                envelopeState = .decay
            }
            
        case .decay:
            if decayRate > 0 {
                // ディケイレート適用
                let decayCoef = Float(decayRate) / 31.0
                envelopeLevel += (FMConstants.maxAttenuation * decayCoef * 0.01)
                if envelopeLevel >= Float(sustainLevel) * (FMConstants.maxAttenuation / 15.0) {
                    envelopeState = .sustain
                }
            } else {
                envelopeState = .sustain
            }
            
        case .sustain:
            if sustainRate > 0 {
                // サスティンレート適用
                let sustainCoef = Float(sustainRate) / 31.0
                envelopeLevel += (FMConstants.maxAttenuation * sustainCoef * 0.005)
                if envelopeLevel >= FMConstants.maxAttenuation {
                    envelopeLevel = FMConstants.maxAttenuation
                    envelopeState = .off
                }
            }
            
        case .release:
            if releaseRate > 0 {
                // リリースレート適用
                let releaseCoef = Float(releaseRate) / 15.0
                envelopeLevel += (FMConstants.maxAttenuation * releaseCoef * 0.02)
                if envelopeLevel >= FMConstants.maxAttenuation {
                    envelopeLevel = FMConstants.maxAttenuation
                    envelopeState = .off
                }
            } else {
                // リリースレート0の場合は即時オフ
                envelopeLevel = FMConstants.maxAttenuation
                envelopeState = .off
            }
            
        case .off:
            envelopeLevel = FMConstants.maxAttenuation
        }
    }
    
    // 現在の出力レベルを取得
    func getOutputLevel() -> Float {
        return output
    }
    
    // エンベロープの状態を取得
    func getEnvelopeState() -> EnvelopeState {
        return envelopeState
    }
}
