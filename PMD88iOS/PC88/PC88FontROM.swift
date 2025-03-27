import Foundation

/// PC-8801のフォントROMを管理するクラス
class PC88FontROM {
    /// フォントデータ
    private var fontData: [UInt8] = []
    
    /// 初期化
    init() {
        loadDefaultFont()
    }
    
    /// デフォルトフォントを読み込む
    private func loadDefaultFont() {
        // 基本的なASCII文字のフォントデータを定義
        // 実際のフォントROMが読み込めない場合のフォールバック
        fontData = Array(repeating: 0, count: 8 * 256)
        
        // スペース (0x20)
        let spaceFont: [UInt8] = [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        setFontData(for: 0x20, data: spaceFont)
        
        // A (0x41)
        let aFont: [UInt8] = [0x18, 0x24, 0x42, 0x7E, 0x42, 0x42, 0x42, 0x00]
        setFontData(for: 0x41, data: aFont)
        
        // 他の基本文字も同様に定義
    }
    
    /// 指定した文字コードのフォントデータを設定
    private func setFontData(for charCode: UInt8, data: [UInt8]) {
        let offset = Int(charCode) * 8
        for i in 0..<min(8, data.count) {
            if offset + i < fontData.count {
                fontData[offset + i] = data[i]
            }
        }
    }
    
    /// フォントROMファイルからデータを読み込む
    func loadFontROMFile(from url: URL) -> Bool {
        do {
            let data = try Data(contentsOf: url)
            fontData = [UInt8](data)
            return true
        } catch {
            print("フォントROMの読み込みに失敗: \(error)")
            return false
        }
    }
    
    /// バンドルからフォントROMファイルを読み込む
    func loadFontROMFromBundle() -> Bool {
        if let fontROMURL = Bundle.main.url(forResource: "font", withExtension: "rom") {
            return loadFontROMFile(from: fontROMURL)
        }
        return false
    }
    
    /// 文字コードに対応するフォントデータを取得
    func getFontData(for charCode: UInt8) -> [UInt8] {
        var result: [UInt8] = Array(repeating: 0, count: 8)
        
        // フォントROMのデータ構造に基づいてフォントデータを抽出
        let offset = Int(charCode) * 8
        if offset + 8 <= fontData.count {
            for i in 0..<8 {
                result[i] = fontData[offset + i]
            }
        }
        
        return result
    }
}
