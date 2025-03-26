import Foundation

/// PC-8801のBIOS ROMを管理するクラス
class PC88BIOS {
    /// BIOSデータ（名前をキーとする）
    private var biosData: [String: [UInt8]] = [:]
    
    /// 初期化
    init() {
        loadBIOSFromBundle()
    }
    
    /// BIOSファイルを読み込む
    func loadBIOSFile(name: String, from url: URL) -> Bool {
        do {
            let data = try Data(contentsOf: url)
            biosData[name] = [UInt8](data)
            print("BIOSファイルを読み込みました: \(name), サイズ: \(data.count)バイト")
            return true
        } catch {
            print("BIOSファイルの読み込みに失敗: \(name), エラー: \(error)")
            return false
        }
    }
    
    /// バンドルからBIOSファイルを読み込む
    func loadBIOSFromBundle() -> Bool {
        var success = true
        let biosFiles = ["N88", "N88N", "N88_0", "N88_1", "N88_2", "N88_3", "DISK"]
        
        for biosName in biosFiles {
            if let biosURL = Bundle.main.url(forResource: biosName, withExtension: "ROM") {
                if !loadBIOSFile(name: biosName, from: biosURL) {
                    success = false
                }
            } else {
                print("BIOSファイルが見つかりません: \(biosName).ROM")
                success = false
            }
        }
        
        return success
    }
    
    /// 指定したBIOSデータを取得
    func getBIOSData(name: String) -> [UInt8]? {
        return biosData[name]
    }
    
    /// BIOSデータをメモリにマッピング
    func mapBIOSToMemory(memory: inout [UInt8], biosName: String, startAddress: Int) -> Bool {
        guard let data = biosData[biosName] else {
            print("マッピングするBIOSデータが見つかりません: \(biosName)")
            return false
        }
        
        for i in 0..<data.count {
            if startAddress + i < memory.count {
                memory[startAddress + i] = data[i]
            }
        }
        
        print("BIOSをメモリにマッピングしました: \(biosName), アドレス: 0x\(String(format: "%04X", startAddress))")
        return true
    }
}
