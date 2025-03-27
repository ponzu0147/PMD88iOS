import Foundation

// Z80 Memory management extension
extension Z80 {
    // メモリアクセス用の安全なラッパー関数
    func safeReadMemory(at address: Int) -> UInt8 {
        if address >= 0 && address < memory.count {
            return memory[address]
        } else {
            if debugMode {
                addDebugLog("警告: 安全なメモリ読み込み失敗 address=0x\(String(format: "%04X", address))")
            }
            return 0  // 無効なアドレスの場合は0を返す
        }
    }
    
    func safeWriteMemory(at address: Int, value: UInt8) -> Bool {
        if address >= 0 && address < memory.count {
            memory[address] = value
            return true
        } else {
            if debugMode {
                addDebugLog("警告: 安全なメモリ書き込み失敗 address=0x\(String(format: "%04X", address)), value=0x\(String(format: "%02X", value))")
            }
            return false
        }
    }
    
    // メモリ読み込み
    func readMemory(at address: Int) -> UInt8 {
        return safeReadMemory(at: address)
    }
    
    // メモリ書き込み
    func writeMemory(at address: Int, value: UInt8) {
        _ = safeWriteMemory(at: address, value: value)
    }
    
    // 16ビットメモリ読み込み（リトルエンディアン）
    func readMemory16(at address: Int) -> Int {
        let low = Int(safeReadMemory(at: address))
        let high = Int(safeReadMemory(at: address + 1))
        return (high << 8) | low
    }
    
    // 16ビットメモリ書き込み（リトルエンディアン）
    func writeMemory16(at address: Int, value: Int) {
        _ = safeWriteMemory(at: address, value: UInt8(value & 0xFF))
        _ = safeWriteMemory(at: address + 1, value: UInt8((value >> 8) & 0xFF))
    }
    
    // スタックプッシュ
    func push(_ value: Int) {
        sp -= 2
        if sp >= 0 {
            writeMemory16(at: sp, value: value)
        } else {
            addDebugLog("警告: スタックオーバーフロー sp=\(String(format: "0x%04X", sp))")
            sp = 0
        }
    }
    
    // スタックポップ
    func pop() -> Int {
        let value = readMemory16(at: sp)
        sp += 2
        if sp >= memory.count {
            addDebugLog("警告: スタックアンダーフロー sp=\(String(format: "0x%04X", sp))")
            sp = memory.count - 2
        }
        return value
    }
    
    // メモリダンプ
    func dumpMemory(start: Int, length: Int) -> String {
        var result = ""
        let end = min(start + length, memory.count)
        
        for i in stride(from: start, to: end, by: 16) {
            result += String(format: "%04X: ", i)
            for j in 0..<16 {
                if i + j < end {
                    result += String(format: "%02X ", memory[i + j])
                } else {
                    result += "   "
                }
            }
            
            result += " "
            
            for j in 0..<16 {
                if i + j < end {
                    let byte = memory[i + j]
                    if byte >= 32 && byte < 127 {
                        result += String(UnicodeScalar(byte))
                    } else {
                        result += "."
                    }
                }
            }
            
            result += "\n"
        }
        
        return result
    }
    
    // メモリ比較
    func compareMemory(data: Data, offset: Int) -> Bool {
        for (i, byte) in data.enumerated() {
            if offset + i < memory.count {
                if memory[offset + i] != byte {
                    return false
                }
            } else {
                return false
            }
        }
        return true
    }
    
    // メモリ検索
    func findInMemory(pattern: [UInt8], start: Int = 0, end: Int? = nil) -> Int? {
        let searchEnd = end ?? memory.count - pattern.count + 1
        
        for i in start..<searchEnd {
            var found = true
            for (j, byte) in pattern.enumerated() {
                if memory[i + j] != byte {
                    found = false
                    break
                }
            }
            if found {
                return i
            }
        }
        
        return nil
    }
}
