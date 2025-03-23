//
//  PC88Types.swift
//  PMD88iOS
//
//  Created by 越川将人 on 2025/03/23.
//

import Foundation

// MARK: - チャンネル情報の構造体
struct ChannelInfo {
    var isActive: Bool = false
    var playingAddress: Int = 0
    var toneNumber: Int = 0
    var volume: Int = 0
    
    // 表示用の追加情報
    var type: String = ""
    var number: Int = 0
    var address: Int = 0
    var note: String = "---"
    var instrument: Int = 0
    var isPlaying: Bool = false
}

// MARK: - PMD88ワークエリアのアドレス定義
enum PMDWorkArea {
    // FM音源関連
    static let fmChannelBase = 0xBD61       // FM音源チャンネル情報の開始アドレス
    static let fmChannelSize = 0x30         // 1チャンネルあたりのサイズ
    static let fmStatusBase = 0xBD71        // FMチャンネルのステータスフラグの開始アドレス
    
    // SSG音源関連
    static let ssgChannelBase = 0xBE11      // SSG音源チャンネル情報の開始アドレス
    static let ssgChannelSize = 0x30        // 1チャンネルあたりのサイズ
    static let ssgStatusBase = 0xBE21      // SSGチャンネルのステータスフラグの開始アドレス
    
    // リズム音源関連
    static let rhythmStatusAddr = 0xBF11    // リズム音源のステータス
    
    // ADPCM関連
    static let adpcmStatusAddr = 0xBF21     // ADPCM音源のステータス
    
    // 曲データ関連
    static let songDataAddr = 0x1000        // 曲データアドレスの格納位置
    static let toneDataAddr = 0x1002        // 音色データアドレスの格納位置
    static let effectDataAddr = 0x1004      // 効果音データアドレスの格納位置
    static let stepCountAddr = 0x1006       // 処理ステップカウンタの格納位置
}

// MARK: - OPNAレジスタアドレス定義
enum OPNARegister {
    // FM音源関連
    static let keyOnOff = 0x28              // キーオン/オフレジスタ
    static let keyOn = 0x28                 // キーオンレジスタ（keyOnOffと同じ値）
    
    // SSG音源関連
    static let ssgVolumeBase = 0x08         // SSG音量レジスタの開始アドレス
    
    // リズム音源関連
    static let rhythmKeyOnOff = 0x10        // リズム音源キーオン/オフレジスタ
    
    // ADPCM関連
    static let adpcmControl = 0x00          // ADPCM制御レジスタ
}
