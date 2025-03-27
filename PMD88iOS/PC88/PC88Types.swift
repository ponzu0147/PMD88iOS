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

// MARK: - PC88の画面モード
enum ScreenMode: Int, Equatable, CaseIterable {
    case text40x25 = 0     // 40列テキストモード
    case text80x25 = 1     // 80列テキストモード
    case graphics = 2      // グラフィックモード
    
    // 画面解像度を取得
    var resolution: (width: Int, height: Int) {
        switch self {
        case .text40x25:
            return (320, 400)  // インターレース表示を考慮して400ライン
        case .text80x25:
            return (640, 400)  // インターレース表示を考慮して400ライン
        case .graphics:
            return (640, 400)
        }
    }
    
    // 画面モードの説明文字列を取得
    var description: String {
        switch self {
        case .text40x25:
            return "40列テキストモード"
        case .text80x25:
            return "80列テキストモード"
        case .graphics:
            return "グラフィックモード"
        }
    }
}

// MARK: - PC88の画面表示関連の定数
enum PC88ScreenConstants {
    // VRAMアドレス
    static let textVRAMAddr = 0xF000       // テキストVRAMの開始アドレス
    static let graphicsVRAMAddr = 0xC000    // グラフィックVRAMの開始アドレス
    
    // 画面サイズ
    static let textWidth = 80              // テキスト画面の幅
    static let textHeight = 25             // テキスト画面の高さ
    static let graphicsWidth = 640          // グラフィック画面の幅
    static let graphicsHeight = 400         // グラフィック画面の高さ
    
    // カラーパレット
    static let defaultPalette: [UInt32] = [
        0xFF000000,  // 0: 黒
        0xFF0000FF,  // 1: 青
        0xFFFF0000,  // 2: 赤
        0xFFFF00FF,  // 3: マゼンタ
        0xFF00FF00,  // 4: 緑
        0xFF00FFFF,  // 5: シアン
        0xFFFFFF00,  // 6: 黄
        0xFFFFFFFF   // 7: 白
    ]
}
