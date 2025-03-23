//
//  FMTypes.swift
//  PMD88iOS
//
//  Created by 越川将人 on 2025/03/22.
//

import Foundation

// FM合成に関する定数
enum FMConstants {
    // YM2608の基本クロック周波数
    static let baseClock: Float = 8000000.0
    
    // チャンネル数
    static let channelCount = 6
    
    // オペレータ数（チャンネルあたり）
    static let operatorsPerChannel = 4
    
    // 波形テーブルサイズ
    static let waveTableSize = 1024
    
    // 最大減衰値
    static let maxAttenuation: Float = 127.0
}

// アルゴリズム定義
enum FMAlgorithmType: Int {
    case alg0 = 0  // OP1->OP2->OP3->OP4
    case alg1 = 1  // (OP1+OP2)->OP3->OP4
    case alg2 = 2  // OP1->(OP2+OP3)->OP4
    case alg3 = 3  // OP1->OP2, OP3->OP4
    case alg4 = 4  // OP1->OP2, OP3, OP4
    case alg5 = 5  // OP1, OP2->OP3, OP4
    case alg6 = 6  // OP1, OP2, OP3, OP4
    case alg7 = 7  // OP1, OP2, OP3, OP4（別実装）
}

// レジスタアドレスのオフセット
struct FMRegisterOffsets {
    // 基本レジスタアドレス
    static let detune_multiple = 0x30
    static let totalLevel = 0x40
    static let keyScale_attackRate = 0x50
    static let decayRate = 0x60
    static let sustainRate = 0x70
    static let sustainLevel_releaseRate = 0x80
    static let ssgEg = 0x90
    
    // チャンネルレジスタアドレス
    static let fnum_low = 0xA0
    static let fnum_high_block = 0xA4
    static let feedback_algorithm = 0xB0
    static let panningLR = 0xB4
    
    // キーオンレジスタ
    static let keyOn = 0x28
}