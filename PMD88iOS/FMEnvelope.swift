//
//  FMEnvelope.swift
//  PMD88iOS
//
//  Created by 越川将人 on 2025/03/22.
//

import Foundation

// エンベロープの状態
enum EnvelopeState {
    case off
    case attack
    case decay
    case sustain
    case release
}

class FMEnvelope {
    // エンベロープの状態
    private var state: EnvelopeState = .off
    private var level: Float = 0.0
    
    // エンベロープのパラメータ
    private var attackRate: Float = 0.0
    private var decayRate: Float = 0.0
    private var sustainRate: Float = 0.0
    private var releaseRate: Float = 0.0
    private var sustainLevel: Float = 0.0
    
    // キースケール関連
    private var keyScaleFactor: Float = 1.0
    
    // SSG-EG関連
    private var ssgEgEnabled: Bool = false
    private var ssgEgMode: Int = 0
    private var ssgEgInverted: Bool = false
    private var ssgEgHold: Bool = false
    private var ssgEgAlternate: Bool = false
    
    // 初期化
    init() {
        resetEnvelope()
    }
    
    // エンベロープのリセット
    func resetEnvelope() {
        state = .off
        level = 0.0
    }
    
    // エンベロープパラメータの設定
    func setParameters(attackRate: Float, decayRate: Float, sustainRate: Float, 
                      releaseRate: Float, sustainLevel: Float, keyScaleFactor: Float) {
        self.attackRate = attackRate
        self.decayRate = decayRate
        self.sustainRate = sustainRate
        self.releaseRate = releaseRate
        self.sustainLevel = sustainLevel
        self.keyScaleFactor = keyScaleFactor
    }
    
    // SSG-EGパラメータの設定
    func setSSGEG(enabled: Bool, mode: Int) {
        ssgEgEnabled = enabled
        ssgEgMode = mode
        
        // SSG-EGモードの解析
        ssgEgInverted = (mode & 0x08) != 0
        ssgEgHold = (mode & 0x04) != 0
        ssgEgAlternate = (mode & 0x02) != 0
    }
    
    // キーオン処理
    func keyOn() {
        if state == .off {
            state = .attack
            
            // SSG-EGが有効な場合、初期レベルを設定
            if ssgEgEnabled && ssgEgInverted {
                level = 1.0
            } else {
                level = 0.0
            }
        }
    }
    
    // キーオフ処理
    func keyOff() {
        if state != .off {
            state = .release
        }
    }
    
    // エンベロープの更新
    func update() -> Float {
        // キースケールファクターを適用したレート
        let scaledAttackRate = attackRate * keyScaleFactor
        let scaledDecayRate = decayRate * keyScaleFactor
        let scaledSustainRate = sustainRate * keyScaleFactor
        let scaledReleaseRate = releaseRate * keyScaleFactor
        
        // 現在の状態に応じた処理
        switch state {
        case .attack:
            // アタックフェーズ（0→最大値へ指数関数的に増加）
            if ssgEgEnabled && ssgEgInverted {
                // 反転モードの場合は減少
                level -= scaledAttackRate * level
                if level <= 0.01 {
                    level = 0.0
                    handleSSGEGTransition()
                }
            } else {
                // 通常モードの場合は増加
                level += scaledAttackRate * (1.0 - level)
                if level >= 0.99 {
                    level = 1.0
                    state = .decay
                }
            }
            
        case .decay:
            // ディケイフェーズ（最大値→サスティンレベルへ指数関数的に減少）
            level -= scaledDecayRate * (level - sustainLevel)
            if abs(level - sustainLevel) < 0.01 {
                level = sustainLevel
                state = .sustain
            }
            
        case .sustain:
            // サスティンフェーズ（サスティンレベルから徐々に減少）
            level -= scaledSustainRate
            if level <= 0.0 {
                level = 0.0
                handleSSGEGTransition()
            }
            
        case .release:
            // リリースフェーズ（現在のレベルから0へ指数関数的に減少）
            level -= scaledReleaseRate
            if level <= 0.01 {
                level = 0.0
                state = .off
            }
            
        case .off:
            // オフ状態
            level = 0.0
        }
        
        // SSG-EGが有効な場合、出力を反転
        if ssgEgEnabled && ssgEgInverted {
            return 1.0 - level
        } else {
            return level
        }
    }
    
    // SSG-EGの状態遷移処理
    private func handleSSGEGTransition() {
        if !ssgEgEnabled {
            state = .off
            return
        }
        
        if ssgEgHold {
            // ホールドモード：現在のレベルを維持
            if ssgEgInverted {
                level = 0.0
            } else {
                level = 1.0
            }
            state = .sustain
        } else if ssgEgAlternate {
            // 交互モード：反転状態を切り替え
            ssgEgInverted = !ssgEgInverted
            state = .attack
        } else {
            // リピートモード：同じパターンを繰り返す
            state = .attack
        }
    }
    
    // 現在のエンベロープレベルを取得
    func getLevel() -> Float {
        return level
    }
    
    // 現在のエンベロープ状態を取得
    func getState() -> EnvelopeState {
        return state
    }
    
    // エンベロープがアクティブかどうかを確認
    func isActive() -> Bool {
        return state != .off
    }
}
