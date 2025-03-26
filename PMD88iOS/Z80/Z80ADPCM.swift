import Foundation

// Z80 ADPCM register handling
extension Z80 {
    // ADPCM関連のレジスタ処理
    func handleADPCMRegister(isMainChip: Bool, subAddr: UInt8, value: UInt8) {
        let baseAddr = isMainChip ? 0 : 0x100
        let regAddr = baseAddr + Int(subAddr)
        
        // レジスタに値を設定
        opnaRegisters[regAddr] = value
        
        // ADPCMレジスタの処理
        switch subAddr {
        case 0x00:  // Control 1
            let reset = (value & 0x01) != 0
            let record = (value & 0x02) != 0
            let playback = (value & 0x04) != 0
            let memoryLoad = (value & 0x08) != 0
            let memoryDa = (value & 0x10) != 0
            let repeatMode = (value & 0x20) != 0
            let spoff = (value & 0x40) != 0
            let resetBit = (value & 0x80) != 0
            
            let chipName = isMainChip ? "Main" : "Sub"
            var logMessage = "\(chipName) ADPCM Control 1: "
            logMessage += reset ? "RESET " : ""
            logMessage += record ? "RECORD " : ""
            logMessage += playback ? "PLAY " : ""
            logMessage += memoryLoad ? "MEMLOAD " : ""
            logMessage += memoryDa ? "MEMDA " : ""
            logMessage += repeatMode ? "REPEAT " : ""
            logMessage += spoff ? "SPOFF " : ""
            logMessage += resetBit ? "RESETBIT " : ""
            
            addDebugLog(logMessage)
            
        case 0x01:  // Control 2
            let startPlayback = (value & 0x01) != 0
            let startRecord = (value & 0x02) != 0
            let memoryDataPlay = (value & 0x04) != 0
            let memoryDataRec = (value & 0x08) != 0
            
            let chipName = isMainChip ? "Main" : "Sub"
            var logMessage = "\(chipName) ADPCM Control 2: "
            logMessage += startPlayback ? "START " : ""
            logMessage += startRecord ? "REC " : ""
            logMessage += memoryDataPlay ? "MEMPLAY " : ""
            logMessage += memoryDataRec ? "MEMREC " : ""
            
            addDebugLog(logMessage)
            
        case 0x02, 0x03:  // Start Address L/H
            updateADPCMStartAddress(isMainChip: isMainChip)
            
        case 0x04, 0x05:  // Stop Address L/H
            updateADPCMStopAddress(isMainChip: isMainChip)
            
        case 0x06, 0x07:  // Prescale L/H
            updateADPCMPrescale(isMainChip: isMainChip)
            
        case 0x08:  // Data
            let chipName = isMainChip ? "Main" : "Sub"
            addDebugLog("\(chipName) ADPCM Data Write: \(String(format: "0x%02X", value))")
            
        case 0x09:  // Delta-N L
            updateADPCMDeltaN(isMainChip: isMainChip)
            
        case 0x0A:  // Delta-N H
            updateADPCMDeltaN(isMainChip: isMainChip)
            
        case 0x0B:  // Level Control
            let chipName = isMainChip ? "Main" : "Sub"
            addDebugLog("\(chipName) ADPCM Level Control: \(String(format: "0x%02X", value))")
            
        case 0x0C:  // Limit Address L
            updateADPCMLimitAddress(isMainChip: isMainChip)
            
        case 0x0D:  // Limit Address H
            updateADPCMLimitAddress(isMainChip: isMainChip)
            
        case 0x0E:  // DAC Data
            let chipName = isMainChip ? "Main" : "Sub"
            addDebugLog("\(chipName) ADPCM DAC Data: \(String(format: "0x%02X", value))")
            
        case 0x0F:  // PCM Data
            let chipName = isMainChip ? "Main" : "Sub"
            addDebugLog("\(chipName) ADPCM PCM Data: \(String(format: "0x%02X", value))")
            
        case 0x10:  // Flag Control
            let chipName = isMainChip ? "Main" : "Sub"
            addDebugLog("\(chipName) ADPCM Flag Control: \(String(format: "0x%02X", value))")
            
        default:
            if subAddr >= 0x20 {
                // 0x20以降はADPCM-Bの領域
                handleADPCMBRegister(isMainChip: isMainChip, subAddr: subAddr, value: value)
            }
        }
    }
    
    // ADPCM-B関連のレジスタ処理
    private func handleADPCMBRegister(isMainChip: Bool, subAddr: UInt8, value: UInt8) {
        let chipName = isMainChip ? "Main" : "Sub"
        
        switch subAddr {
        case 0x20:  // Control 1
            let reset = (value & 0x01) != 0
            let start = (value & 0x02) != 0
            let repeatMode = (value & 0x10) != 0
            
            var logMessage = "\(chipName) ADPCM-B Control 1: "
            logMessage += reset ? "RESET " : ""
            logMessage += start ? "START " : ""
            logMessage += repeatMode ? "REPEAT " : ""
            
            addDebugLog(logMessage)
            
        case 0x21:  // Control 2
            addDebugLog("\(chipName) ADPCM-B Control 2: \(String(format: "0x%02X", value))")
            
        case 0x22, 0x23:  // Start Address L/H
            updateADPCMBStartAddress(isMainChip: isMainChip)
            
        case 0x24, 0x25:  // Stop Address L/H
            updateADPCMBStopAddress(isMainChip: isMainChip)
            
        case 0x26:  // Prescale L
            updateADPCMBPrescale(isMainChip: isMainChip)
            
        case 0x27:  // Prescale H
            updateADPCMBPrescale(isMainChip: isMainChip)
            
        case 0x28:  // ADPCM-B Data
            addDebugLog("\(chipName) ADPCM-B Data Write: \(String(format: "0x%02X", value))")
            
        case 0x29:  // Delta-N L
            updateADPCMBDeltaN(isMainChip: isMainChip)
            
        case 0x2A:  // Delta-N H
            updateADPCMBDeltaN(isMainChip: isMainChip)
            
        case 0x2B:  // Level Control
            addDebugLog("\(chipName) ADPCM-B Level Control: \(String(format: "0x%02X", value))")
            
        case 0x2C:  // Limit Address L
            updateADPCMBLimitAddress(isMainChip: isMainChip)
            
        case 0x2D:  // Limit Address H
            updateADPCMBLimitAddress(isMainChip: isMainChip)
            
        default:
            addDebugLog("\(chipName) Unknown ADPCM-B Register: \(String(format: "0x%02X", subAddr)) = \(String(format: "0x%02X", value))")
        }
    }
    
    // ADPCM開始アドレス更新
    private func updateADPCMStartAddress(isMainChip: Bool) {
        let baseAddr = isMainChip ? 0 : 0x100
        let lowByte = opnaRegisters[baseAddr + 0x02]
        let highByte = opnaRegisters[baseAddr + 0x03]
        let startAddress = (Int(highByte) << 8) | Int(lowByte)
        
        let chipName = isMainChip ? "Main" : "Sub"
        addDebugLog("\(chipName) ADPCM Start Address: \(String(format: "0x%04X", startAddress))")
    }
    
    // ADPCM停止アドレス更新
    private func updateADPCMStopAddress(isMainChip: Bool) {
        let baseAddr = isMainChip ? 0 : 0x100
        let lowByte = opnaRegisters[baseAddr + 0x04]
        let highByte = opnaRegisters[baseAddr + 0x05]
        let stopAddress = (Int(highByte) << 8) | Int(lowByte)
        
        let chipName = isMainChip ? "Main" : "Sub"
        addDebugLog("\(chipName) ADPCM Stop Address: \(String(format: "0x%04X", stopAddress))")
    }
    
    // ADPCMプリスケール更新
    private func updateADPCMPrescale(isMainChip: Bool) {
        let baseAddr = isMainChip ? 0 : 0x100
        let lowByte = opnaRegisters[baseAddr + 0x06]
        let highByte = opnaRegisters[baseAddr + 0x07]
        let prescale = (Int(highByte) << 8) | Int(lowByte)
        
        let chipName = isMainChip ? "Main" : "Sub"
        addDebugLog("\(chipName) ADPCM Prescale: \(String(format: "0x%04X", prescale))")
    }
    
    // ADPCMデルタN更新
    private func updateADPCMDeltaN(isMainChip: Bool) {
        let baseAddr = isMainChip ? 0 : 0x100
        let lowByte = opnaRegisters[baseAddr + 0x09]
        let highByte = opnaRegisters[baseAddr + 0x0A]
        let deltaN = (Int(highByte) << 8) | Int(lowByte)
        
        // デルタNから周波数を計算（近似値）
        // ADPCM周波数 = 3579545 * deltaN / (72 * 256)
        let frequency = Int(Double(3579545) * Double(deltaN) / (72.0 * 256.0))
        
        let chipName = isMainChip ? "Main" : "Sub"
        addDebugLog("\(chipName) ADPCM Delta-N: \(String(format: "0x%04X", deltaN)) (約\(frequency)Hz)")
    }
    
    // ADPCM制限アドレス更新
    private func updateADPCMLimitAddress(isMainChip: Bool) {
        let baseAddr = isMainChip ? 0 : 0x100
        let lowByte = opnaRegisters[baseAddr + 0x0C]
        let highByte = opnaRegisters[baseAddr + 0x0D]
        let limitAddress = (Int(highByte) << 8) | Int(lowByte)
        
        let chipName = isMainChip ? "Main" : "Sub"
        addDebugLog("\(chipName) ADPCM Limit Address: \(String(format: "0x%04X", limitAddress))")
    }
    
    // ADPCM-B開始アドレス更新
    private func updateADPCMBStartAddress(isMainChip: Bool) {
        let baseAddr = isMainChip ? 0 : 0x100
        let lowByte = opnaRegisters[baseAddr + 0x22]
        let highByte = opnaRegisters[baseAddr + 0x23]
        let startAddress = (Int(highByte) << 8) | Int(lowByte)
        
        let chipName = isMainChip ? "Main" : "Sub"
        addDebugLog("\(chipName) ADPCM-B Start Address: \(String(format: "0x%04X", startAddress))")
    }
    
    // ADPCM-B停止アドレス更新
    private func updateADPCMBStopAddress(isMainChip: Bool) {
        let baseAddr = isMainChip ? 0 : 0x100
        let lowByte = opnaRegisters[baseAddr + 0x24]
        let highByte = opnaRegisters[baseAddr + 0x25]
        let stopAddress = (Int(highByte) << 8) | Int(lowByte)
        
        let chipName = isMainChip ? "Main" : "Sub"
        addDebugLog("\(chipName) ADPCM-B Stop Address: \(String(format: "0x%04X", stopAddress))")
    }
    
    // ADPCM-Bプリスケール更新
    private func updateADPCMBPrescale(isMainChip: Bool) {
        let baseAddr = isMainChip ? 0 : 0x100
        let lowByte = opnaRegisters[baseAddr + 0x26]
        let highByte = opnaRegisters[baseAddr + 0x27]
        let prescale = (Int(highByte) << 8) | Int(lowByte)
        
        let chipName = isMainChip ? "Main" : "Sub"
        addDebugLog("\(chipName) ADPCM-B Prescale: \(String(format: "0x%04X", prescale))")
    }
    
    // ADPCM-BデルタN更新
    private func updateADPCMBDeltaN(isMainChip: Bool) {
        let baseAddr = isMainChip ? 0 : 0x100
        let lowByte = opnaRegisters[baseAddr + 0x29]
        let highByte = opnaRegisters[baseAddr + 0x2A]
        let deltaN = (Int(highByte) << 8) | Int(lowByte)
        
        // デルタNから周波数を計算（近似値）
        // ADPCM-B周波数 = 3579545 * deltaN / (72 * 256)
        let frequency = Int(Double(3579545) * Double(deltaN) / (72.0 * 256.0))
        
        let chipName = isMainChip ? "Main" : "Sub"
        addDebugLog("\(chipName) ADPCM-B Delta-N: \(String(format: "0x%04X", deltaN)) (約\(frequency)Hz)")
    }
    
    // ADPCM-B制限アドレス更新
    private func updateADPCMBLimitAddress(isMainChip: Bool) {
        let baseAddr = isMainChip ? 0 : 0x100
        let lowByte = opnaRegisters[baseAddr + 0x2C]
        let highByte = opnaRegisters[baseAddr + 0x2D]
        let limitAddress = (Int(highByte) << 8) | Int(lowByte)
        
        let chipName = isMainChip ? "Main" : "Sub"
        addDebugLog("\(chipName) ADPCM-B Limit Address: \(String(format: "0x%04X", limitAddress))")
    }
    
    // ADPCM再生状態の取得
    func getADPCMStatus(isMainChip: Bool) -> String {
        let baseAddr = isMainChip ? 0 : 0x100
        let control1 = opnaRegisters[baseAddr + 0x00]
        let control2 = opnaRegisters[baseAddr + 0x01]
        
        let reset = (control1 & 0x01) != 0
        let record = (control1 & 0x02) != 0
        let playback = (control1 & 0x04) != 0
        let memoryLoad = (control1 & 0x08) != 0
        let memoryDa = (control1 & 0x10) != 0
        let repeatMode = (control1 & 0x20) != 0
        let spoff = (control1 & 0x40) != 0
        let resetBit = (control1 & 0x80) != 0
        
        let startPlayback = (control2 & 0x01) != 0
        let startRecord = (control2 & 0x02) != 0
        let memoryDataPlay = (control2 & 0x04) != 0
        let memoryDataRec = (control2 & 0x08) != 0
        
        let lowByte = opnaRegisters[baseAddr + 0x09]
        let highByte = opnaRegisters[baseAddr + 0x0A]
        let deltaN = (Int(highByte) << 8) | Int(lowByte)
        
        // デルタNから周波数を計算（近似値）
        let frequency = Int(Double(3579545) * Double(deltaN) / (72.0 * 256.0))
        
        let chipName = isMainChip ? "Main" : "Sub"
        var status = "\(chipName) ADPCM Status:\n"
        status += "Control: "
        status += reset ? "RESET " : ""
        status += record ? "RECORD " : ""
        status += playback ? "PLAY " : ""
        status += memoryLoad ? "MEMLOAD " : ""
        status += memoryDa ? "MEMDA " : ""
        status += repeatMode ? "REPEAT " : ""
        status += spoff ? "SPOFF " : ""
        status += resetBit ? "RESETBIT " : ""
        status += "\n"
        
        status += "Control2: "
        status += startPlayback ? "START " : ""
        status += startRecord ? "REC " : ""
        status += memoryDataPlay ? "MEMPLAY " : ""
        status += memoryDataRec ? "MEMREC " : ""
        status += "\n"
        
        status += "Frequency: \(frequency)Hz (Delta-N: \(String(format: "0x%04X", deltaN)))\n"
        
        // アドレス情報
        let startAddrL = opnaRegisters[baseAddr + 0x02]
        let startAddrH = opnaRegisters[baseAddr + 0x03]
        let startAddr = (Int(startAddrH) << 8) | Int(startAddrL)
        
        let stopAddrL = opnaRegisters[baseAddr + 0x04]
        let stopAddrH = opnaRegisters[baseAddr + 0x05]
        let stopAddr = (Int(stopAddrH) << 8) | Int(stopAddrL)
        
        let limitAddrL = opnaRegisters[baseAddr + 0x0C]
        let limitAddrH = opnaRegisters[baseAddr + 0x0D]
        let limitAddr = (Int(limitAddrH) << 8) | Int(limitAddrL)
        
        status += "Start Address: \(String(format: "0x%04X", startAddr))\n"
        status += "Stop Address: \(String(format: "0x%04X", stopAddr))\n"
        status += "Limit Address: \(String(format: "0x%04X", limitAddr))\n"
        
        // レベル情報
        let level = opnaRegisters[baseAddr + 0x0B]
        status += "Level: \(String(format: "0x%02X", level))\n"
        
        return status
    }
    
    // ADPCM-B再生状態の取得
    func getADPCMBStatus(isMainChip: Bool) -> String {
        let baseAddr = isMainChip ? 0 : 0x100
        let control1 = opnaRegisters[baseAddr + 0x20]
        
        let reset = (control1 & 0x01) != 0
        let start = (control1 & 0x02) != 0
        let repeatMode = (control1 & 0x10) != 0
        
        let lowByte = opnaRegisters[baseAddr + 0x29]
        let highByte = opnaRegisters[baseAddr + 0x2A]
        let deltaN = (Int(highByte) << 8) | Int(lowByte)
        
        // デルタNから周波数を計算（近似値）
        let frequency = Int(Double(3579545) * Double(deltaN) / (72.0 * 256.0))
        
        let chipName = isMainChip ? "Main" : "Sub"
        var status = "\(chipName) ADPCM-B Status:\n"
        status += "Control: "
        status += reset ? "RESET " : ""
        status += start ? "START " : ""
        status += repeatMode ? "REPEAT " : ""
        status += "\n"
        
        status += "Frequency: \(frequency)Hz (Delta-N: \(String(format: "0x%04X", deltaN)))\n"
        
        // アドレス情報
        let startAddrL = opnaRegisters[baseAddr + 0x22]
        let startAddrH = opnaRegisters[baseAddr + 0x23]
        let startAddr = (Int(startAddrH) << 8) | Int(startAddrL)
        
        let stopAddrL = opnaRegisters[baseAddr + 0x24]
        let stopAddrH = opnaRegisters[baseAddr + 0x25]
        let stopAddr = (Int(stopAddrH) << 8) | Int(stopAddrL)
        
        let limitAddrL = opnaRegisters[baseAddr + 0x2C]
        let limitAddrH = opnaRegisters[baseAddr + 0x2D]
        let limitAddr = (Int(limitAddrH) << 8) | Int(limitAddrL)
        
        status += "Start Address: \(String(format: "0x%04X", startAddr))\n"
        status += "Stop Address: \(String(format: "0x%04X", stopAddr))\n"
        status += "Limit Address: \(String(format: "0x%04X", limitAddr))\n"
        
        // レベル情報
        let level = opnaRegisters[baseAddr + 0x2B]
        status += "Level: \(String(format: "0x%02X", level))\n"
        
        return status
    }
}
