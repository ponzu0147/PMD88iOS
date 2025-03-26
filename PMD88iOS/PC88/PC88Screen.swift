//
//  PC88Screen.swift
//  PMD88iOS
//
//  Created by 越川将人 on 2025/03/26.
//

import Foundation
import SwiftUI
import Combine

/// PC-88の画面表示を管理するクラス
class PC88Screen: ObservableObject {
    // MARK: - 公開プロパティ
    @Published var screenBuffer: Data
    @Published var screenMode: ScreenMode = .text80x25
    @Published var screenRefreshNeeded: Bool = false
    
    // MARK: - プライベートプロパティ
    private var vramTextBuffer: [UInt8] = Array(repeating: 0, count: 0x1000) // テキストVRAM領域 (4KB)
    private var vramGraphicsBuffer: [UInt8] = Array(repeating: 0, count: 0x10000) // グラフィックVRAM (64KB)
    private var currentPalette: [UInt8] = Array(repeating: 0, count: 8) // カラーパレット
    private weak var pc88Core: PC88Core?
    
    // MARK: - 定数
    /// テキストモードの高さ
    static let textHeight = 25
    
    /// グラフィックVRAMのアドレス
    static let graphicsVRAMAddr = 0xC000
    
    /// テキストVRAMのアドレス
    static let textVRAMAddr = 0xF000
    
    /// デフォルトのカラーパレット (RGBA形式)
    static let defaultPalette: [UInt32] = [
        0x000000FF, // 黒
        0x0000FFFF, // 青
        0xFF0000FF, // 赤
        0xFF00FFFF, // マゼンタ
        0x00FF00FF, // 緑
        0x00FFFFFF, // シアン
        0xFFFF00FF, // 黄
        0xFFFFFFFF  // 白
    ]
    
    // MARK: - 初期化
    init(pc88Core: PC88Core) {
        self.pc88Core = pc88Core
        
        // 画面バッファの初期化
        let screenSize = ScreenMode.text80x25.resolution
        let bufferSize = screenSize.width * screenSize.height * 4 // RGBA各バイト
        screenBuffer = Data(count: bufferSize)
        
        // カラーパレットの初期化
        for i in 0..<currentPalette.count {
            currentPalette[i] = UInt8(i)
        }
        
        // テストパターンを表示するためのVRAM初期化
        initializeTestPattern()
        
        // 初期画面バッファの更新
        updateScreenBuffer()
    }
    
    // MARK: - 公開メソッド
    
    /// 画面バッファを更新する
    func updateScreenBuffer() {
        // 現在の画面モードに応じて適切な更新メソッドを呼び出す
        switch screenMode {
        case .text40x25, .text80x25:
            updateTextModeBuffer()
        case .graphics:
            updateGraphicsModeBuffer()
        }
        
        // 画面更新フラグをリセット
        screenRefreshNeeded = false
    }
    
    /// 画面バッファを取得する
    func getScreenBuffer() -> Data {
        // 画面バッファが更新されていない場合は更新する
        if screenRefreshNeeded {
            updateScreenBuffer()
        }
        
        // デバッグ用にログを出力
        pc88Core?.debug.appendLog("Screen buffer size: \(screenBuffer.count) bytes, Mode: \(screenMode.description)")
        
        return screenBuffer
    }
    
    /// VRAMへの書き込みを処理する
    func writeToVRAM(address: UInt16, value: UInt8) {
        if address >= UInt16(PC88ScreenConstants.textVRAMAddr) && address < UInt16(PC88ScreenConstants.textVRAMAddr + 0x1000) {
            // テキストVRAMへの書き込み
            let offset = Int(address - UInt16(PC88ScreenConstants.textVRAMAddr))
            vramTextBuffer[offset] = value
            screenRefreshNeeded = true
        } else if address >= UInt16(PC88ScreenConstants.graphicsVRAMAddr) && address < UInt16(PC88ScreenConstants.graphicsVRAMAddr + 0x10000) {
            // グラフィックVRAMへの書き込み
            let offset = Int(address - UInt16(PC88ScreenConstants.graphicsVRAMAddr))
            if offset < vramGraphicsBuffer.count {
                vramGraphicsBuffer[offset] = value
                screenRefreshNeeded = true
            }
        }
    }
    
    /// 画面モード変更を処理する
    func handleScreenModeChange(port: UInt16, value: UInt8) {
        // ポート0x30: CRTCコントロールポート
        if port == 0x30 {
            // ビット0: 40/80列モード切り替え
            if value & 0x01 != 0 {
                screenMode = .text40x25
            } else {
                screenMode = .text80x25
            }
            
            // ビット1: グラフィックモード切り替え
            if value & 0x02 != 0 {
                screenMode = .graphics
            }
            
            pc88Core?.debug.appendLog("画面モード変更: \(screenMode.description)")
            updateScreenBuffer()
        }
    }
    
    /// パレット変更を処理する
    func handlePaletteChange(port: UInt16, value: UInt8) {
        // ポート0x32: パレットレジスタ選択
        if port == 0x32 {
            let paletteIndex = value & 0x07 // 下位3ビットがパレットインデックス
            if paletteIndex < currentPalette.count {
                // ポート0x33: パレット値設定
                currentPalette[Int(paletteIndex)] = value
                updateScreenBuffer()
            }
        }
    }
    
    // MARK: - プライベートメソッド
    
    /// テキストモードの画面バッファを更新する
    private func updateTextModeBuffer() {
        let width = screenMode == .text40x25 ? 40 : 80
        let height = PC88ScreenConstants.textHeight
        let screenWidth = screenMode.resolution.width
        let screenHeight = screenMode.resolution.height
        
        // 画面バッファのサイズを確認し、必要に応じて再割り当て
        let requiredSize = screenWidth * screenHeight * 4
        if screenBuffer.count != requiredSize {
            screenBuffer = Data(count: requiredSize)
            pc88Core?.debug.appendLog("Text buffer resized to \(requiredSize) bytes")
        }
        
        // 画面バッファにアクセスするためのポインタを取得
        screenBuffer.withUnsafeMutableBytes { bufferPtr in
            guard let baseAddress = bufferPtr.baseAddress else { return }
            let buffer = baseAddress.assumingMemoryBound(to: UInt32.self)
            
            // 文字サイズを計算
            let charWidth = screenWidth / width
            let charHeight = screenHeight / height
            
            // テキストVRAMから文字を描画
            for y in 0..<height {
                for x in 0..<width {
                    let vramOffset = y * width + x
                    if vramOffset < vramTextBuffer.count {
                        let charCode = vramTextBuffer[vramOffset]
                        let attrCode = vramTextBuffer[vramOffset + 0x800] // 属性は0x800オフセット
                        
                        // 文字の色と背景色を決定
                        let fgColor = Int(attrCode & 0x07) // 下位3ビットが文字色
                        let bgColor = Int((attrCode >> 3) & 0x07) // 次の3ビットが背景色
                        
                        // 文字のピクセルを描画
                        drawCharacter(charCode: charCode, x: x, y: y, fgColor: fgColor, bgColor: bgColor,
                                      charWidth: charWidth, charHeight: charHeight, buffer: buffer, bufferWidth: screenWidth)
                    }
                }
            }
        }
    }
    
    /// グラフィックモードの画面バッファを更新する
    private func updateGraphicsModeBuffer() {
        let screenWidth = screenMode.resolution.width
        let screenHeight = screenMode.resolution.height
        
        // 画面バッファのサイズを確認し、必要に応じて再割り当て
        let requiredSize = screenWidth * screenHeight * 4
        if screenBuffer.count != requiredSize {
            screenBuffer = Data(count: requiredSize)
            pc88Core?.debug.appendLog("Graphics buffer resized to \(requiredSize) bytes")
        }
        
        // 画面バッファにアクセスするためのポインタを取得
        screenBuffer.withUnsafeMutableBytes { bufferPtr in
            guard let baseAddress = bufferPtr.baseAddress else { return }
            let buffer = baseAddress.assumingMemoryBound(to: UInt32.self)
            
            // グラフィックVRAMからピクセルを描画
            for y in 0..<screenHeight {
                for x in 0..<screenWidth {
                    // PC-88のグラフィックメモリマッピングに基づいてVRAMオフセットを計算
                    let vramPlane = x / 8
                    let bitPos = 7 - (x % 8)
                    let vramOffset = (y * (screenWidth / 8)) + vramPlane
                    
                    if vramOffset < vramGraphicsBuffer.count {
                        // 各プレーンからビットを取得
                        let r = (vramGraphicsBuffer[vramOffset] >> bitPos) & 0x01
                        let g = (vramGraphicsBuffer[vramOffset + 0x2000] >> bitPos) & 0x01
                        let b = (vramGraphicsBuffer[vramOffset + 0x4000] >> bitPos) & 0x01
                        
                        // RGB値からカラーインデックスを計算
                        let colorIndex = (r << 2) | (g << 1) | b
                        
                        // パレットからRGBA値を取得
                        let color = PC88ScreenConstants.defaultPalette[Int(colorIndex)]
                        
                        // ピクセルを描画
                        buffer[y * screenWidth + x] = color
                    }
                }
            }
        }
    }
    
    /// 文字を描画する
    private func drawCharacter(charCode: UInt8, x: Int, y: Int, fgColor: Int, bgColor: Int,
                              charWidth: Int, charHeight: Int, buffer: UnsafeMutablePointer<UInt32>, bufferWidth: Int) {
        // フォントデータ（仮のフォントデータ - 実際には適切なフォントデータを使用する必要があります）
        let fontData = getFontData(for: charCode)
        
        // 文字の各ピクセルを描画
        for cy in 0..<8 {
            let fontLine = fontData[cy]
            for cx in 0..<8 {
                let bit = (fontLine >> (7 - cx)) & 0x01
                let color = bit == 1 ? PC88ScreenConstants.defaultPalette[fgColor] : PC88ScreenConstants.defaultPalette[bgColor]
                
                // 文字の拡大描画
                for sy in 0..<charHeight/8 {
                    for sx in 0..<charWidth/8 {
                        let pixelX = x * charWidth + cx * (charWidth/8) + sx
                        let pixelY = y * charHeight + cy * (charHeight/8) + sy
                        let bufferOffset = pixelY * bufferWidth + pixelX
                        
                        if bufferOffset < bufferWidth * (charHeight * PC88ScreenConstants.textHeight) {
                            buffer[bufferOffset] = color
                        }
                    }
                }
            }
        }
    }
    
    /// 文字コードに対応するフォントデータを取得する
    private func getFontData(for charCode: UInt8) -> [UInt8] {
        // 仮のフォントデータ（8x8ピクセル）
        // 実際の実装では、PC-88のフォントROMデータを使用する必要があります
        var fontData: [UInt8] = Array(repeating: 0, count: 8)
        
        // 簡易的なフォントデータを生成（デバッグ用）
        switch charCode {
        case 0x20: // スペース
            fontData = [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        case 0x41: // 'A'
            fontData = [0x18, 0x24, 0x42, 0x7E, 0x42, 0x42, 0x42, 0x00]
        case 0x42: // 'B'
            fontData = [0x7C, 0x22, 0x22, 0x3C, 0x22, 0x22, 0x7C, 0x00]
        case 0x43: // 'C'
            fontData = [0x3C, 0x42, 0x40, 0x40, 0x40, 0x42, 0x3C, 0x00]
        case 0x44: // 'D'
            fontData = [0x78, 0x24, 0x22, 0x22, 0x22, 0x24, 0x78, 0x00]
        case 0x45: // 'E'
            fontData = [0x7E, 0x40, 0x40, 0x7C, 0x40, 0x40, 0x7E, 0x00]
        case 0x46: // 'F'
            fontData = [0x7E, 0x40, 0x40, 0x7C, 0x40, 0x40, 0x40, 0x00]
        default: // その他の文字
            // 文字コードに基づいて簡易的なパターンを生成
            fontData[0] = charCode & 0x01 != 0 ? 0xFF : 0x81
            fontData[1] = charCode & 0x02 != 0 ? 0xFF : 0x81
            fontData[2] = charCode & 0x04 != 0 ? 0xFF : 0x81
            fontData[3] = charCode & 0x08 != 0 ? 0xFF : 0x81
            fontData[4] = charCode & 0x10 != 0 ? 0xFF : 0x81
            fontData[5] = charCode & 0x20 != 0 ? 0xFF : 0x81
            fontData[6] = charCode & 0x40 != 0 ? 0xFF : 0x81
            fontData[7] = charCode & 0x80 != 0 ? 0xFF : 0x81
        }
        
        return fontData
    }
    
    /// テストパターンを初期化する
    private func initializeTestPattern() {
        // テキストVRAMにテストパターンを書き込む
        let message = "PC-88 Emulator Test Pattern"
        
        // メッセージを画面中央に表示
        let startX = (80 - message.count) / 2
        let startY = 12
        
        for (i, char) in message.enumerated() {
            let asciiValue = UInt8(char.asciiValue ?? 0x20)
            let offset = startY * 80 + startX + i
            if offset < vramTextBuffer.count {
                vramTextBuffer[offset] = asciiValue
                // 属性を設定（白文字に青背景）
                vramTextBuffer[offset + 0x800] = 0x07 | 0x10  // 白文字(7)、青背景(1<<4)
            }
        }
        
        // グラフィックVRAMにテストパターンを書き込む
        // 大きな格子パターンを描画
        for y in 0..<400 {
            for x in 0..<640 {
                // 40ピクセルごとの格子パターン
                let gridX = x / 40
                let gridY = y / 40
                
                // 格子の色を交互に変更
                let colorIndex = (gridX + gridY) % 8
                
                // 色に応じてRGBプレーンにセット
                let r = (colorIndex & 0x04) >> 2
                let g = (colorIndex & 0x02) >> 1
                let b = colorIndex & 0x01
                
                // バイト位置とビット位置を計算
                let bytePos = (y * (640 / 8)) + (x / 8)
                let bitPos = 7 - (x % 8)
                
                if bytePos < vramGraphicsBuffer.count {
                    // Rプレーン
                    if r == 1 {
                        vramGraphicsBuffer[bytePos] |= (1 << bitPos)
                    }
                    
                    // Gプレーン
                    if g == 1 && (bytePos + 0x2000) < vramGraphicsBuffer.count {
                        vramGraphicsBuffer[bytePos + 0x2000] |= (1 << bitPos)
                    }
                    
                    // Bプレーン
                    if b == 1 && (bytePos + 0x4000) < vramGraphicsBuffer.count {
                        vramGraphicsBuffer[bytePos + 0x4000] |= (1 << bitPos)
                    }
                }
            }
        }
        
        // 画面更新フラグをセット
        screenRefreshNeeded = true
        pc88Core?.debug.appendLog("Test pattern initialized")
    }
}
