import Foundation

// Z80 I/O handling extension
extension Z80 {
    // ポート出力処理
    func outPort(port: UInt8, value: UInt8) {
        // ポートマッピングを確認
        let mappedPort = portMap[port] ?? port
        
        // ポート値を保存
        ports[port] = value
        
        // ポート書き込み順序を記録
        portWriteOrder.append((port: port, value: value))
        if portWriteOrder.count > 100 {
            portWriteOrder.removeFirst()
        }
        
        // デバッグカウンター
        outPortCounter += 1
        
        // ポート44h-47h（FM音源関連）の処理
        if port >= 0x44 && port <= 0x47 {
            handleFMPorts(port: port, value: value, mappedPort: mappedPort)
        }
        
        // その他のポート出力をデバッグログに記録
        if debugMode && !(port >= 0x44 && port <= 0x47) {
            addDebugLog("OUT (\(String(format: "0x%02X", port))→\(String(format: "0x%02X", mappedPort))), \(String(format: "0x%02X", value)) at PC=\(String(format: "0x%04X", pc))")
        }
    }
    
    // FM音源関連ポート（44h-47h）の処理
    private func handleFMPorts(port: UInt8, value: UInt8, mappedPort: UInt8) {
        switch port {
        case 0x44:  // 表FM音源アドレスレジスタ
            regAddrPort44 = value
            addrWritten[0x44] = true
            currentRegAddr[0x44] = value
            
            if debugMode {
                addDebugLog("OUT (44h→\(String(format: "0x%02X", mappedPort))), アドレス \(String(format: "0x%02X", value)) at PC=\(String(format: "0x%04X", pc))")
            }
            
            // sel44ルーチンの検出（PMD特有の処理）
            if sel44Address == -1 && pc > 0 {
                sel44Address = pc
                addDebugLog("sel44ルーチン検出: \(String(format: "0x%04X", pc))")
            }
            
            // ポート44/45への書き込みを記録
            ports44_45[0x44] = value
            
            // 現在のポートベースを設定
            currentPortBase = 0x44
            
        case 0x45:  // 表FM音源データレジスタ
            if addrWritten[0x44] == true {
                let regAddr = regAddrPort44
                
                // OPNAレジスタに値を設定
                let regIndex = Int(regAddr)
                if regIndex < opnaRegisters.count {
                    opnaRegisters[regIndex] = value
                }
                
                // レジスタ効果を処理
                handleOPNARegisterEffect(isMainChip: true, regAddr: Int(regAddr), value: value)
                
                if debugMode {
                    addDebugLog("OUT (45h→\(String(format: "0x%02X", mappedPort))), データ \(String(format: "0x%02X", value)) to レジスタ \(String(format: "0x%02X", regAddr)) at PC=\(String(format: "0x%04X", pc))")
                }
                
                // ポート44/45への書き込みを記録
                ports44_45[0x45] = value
                
                // OPNA更新フラグをセット
                needsOPNAUpdate = true
            } else {
                if debugMode {
                    addDebugLog("警告: ポート45hへの書き込みがアドレス設定なしで行われました at PC=\(String(format: "0x%04X", pc))")
                }
            }
            
        case 0x46:  // 裏FM音源アドレスレジスタ
            regAddrPort46 = value
            addrWritten[0x46] = true
            currentRegAddr[0x46] = value
            
            if debugMode {
                addDebugLog("OUT (46h→\(String(format: "0x%02X", mappedPort))), アドレス \(String(format: "0x%02X", value)) at PC=\(String(format: "0x%04X", pc))")
            }
            
            // sel46ルーチンの検出（PMD特有の処理）
            if sel46Address == -1 && pc > 0 {
                sel46Address = pc
                addDebugLog("sel46ルーチン検出: \(String(format: "0x%04X", pc))")
            }
            
            // ポート46/47への書き込みを記録
            ports46_47[0x46] = value
            
            // 現在のポートベースを設定
            currentPortBase = 0x46
            
            // opnset46ルーチン検出
            if !inOpnset46 && value == 0x27 {
                inOpnset46 = true
                opnset46State = 1
                addDebugLog("opnset46ルーチン開始検出: \(String(format: "0x%04X", pc))")
            }
            
        case 0x47:  // 裏FM音源データレジスタ
            if addrWritten[0x46] == true {
                let regAddr = regAddrPort46
                
                // OPNAレジスタに値を設定（裏FM音源用のオフセット0x100を追加）
                let regIndex = 0x100 + Int(regAddr)
                if regIndex < opnaRegisters.count {
                    opnaRegisters[regIndex] = value
                }
                
                // レジスタ効果を処理
                handleOPNARegisterEffect(isMainChip: false, regAddr: Int(regAddr), value: value)
                
                if debugMode {
                    addDebugLog("OUT (47h→\(String(format: "0x%02X", mappedPort))), データ \(String(format: "0x%02X", value)) to レジスタ \(String(format: "0x%02X", regAddr)) at PC=\(String(format: "0x%04X", pc))")
                }
                
                // ポート46/47への書き込みを記録
                ports46_47[0x47] = value
                
                // opnset46ルーチン状態追跡
                if inOpnset46 {
                    opnset46State += 1
                    if opnset46State >= 3 {
                        inOpnset46 = false
                        opnset46State = 0
                        addDebugLog("opnset46ルーチン完了検出: \(String(format: "0x%04X", pc))")
                    }
                }
                
                // OPNA更新フラグをセット
                needsOPNAUpdate = true
            } else {
                if debugMode {
                    addDebugLog("警告: ポート47hへの書き込みがアドレス設定なしで行われました at PC=\(String(format: "0x%04X", pc))")
                }
            }
            
        default:
            break
        }
    }
    
    // ポート入力処理
    func inPort(port: UInt8) -> UInt8 {
        // ポートマッピングを確認
        let mappedPort = portMap[port] ?? port
        
        // 特殊なポート処理
        var value: UInt8 = 0
        
        switch port {
        case 0x44:  // 表FM音源ステータスレジスタ
            // ビジーフラグをシミュレート
            if port44Busy {
                port44BusyCounter -= 1
                if port44BusyCounter <= 0 {
                    port44Busy = false
                }
                value = 0x80  // ビジー状態
            } else {
                value = 0x00  // レディ状態
            }
            
        case 0x46:  // 裏FM音源ステータスレジスタ
            // ビジーフラグをシミュレート
            if port46Busy {
                port46BusyCounter -= 1
                if port46BusyCounter <= 0 {
                    port46Busy = false
                }
                value = 0x80  // ビジー状態
            } else {
                value = 0x00  // レディ状態
            }
            
        default:
            // 通常のポート値を返す
            value = ports[port] ?? 0
        }
        
        if debugMode {
            addDebugLog("IN (\(String(format: "0x%02X", port))→\(String(format: "0x%02X", mappedPort))), 結果: \(String(format: "0x%02X", value)) at PC=\(String(format: "0x%04X", pc))")
        }
        
        return value
    }
    
    // OPNAビジーフラグをセット
    func setOPNABusy(port: UInt8, duration: Int = 10) {
        switch port {
        case 0x44:
            port44Busy = true
            port44BusyCounter = duration
        case 0x46:
            port46Busy = true
            port46BusyCounter = duration
        default:
            break
        }
    }
}
