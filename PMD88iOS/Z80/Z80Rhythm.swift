import Foundation

// Z80 Rhythm sound register handling
extension Z80 {
    // リズム音源関連のレジスタ処理
    func handleRhythmRegister(isMainChip: Bool, subAddr: UInt8, value: UInt8) {
        let baseAddr = isMainChip ? 0 : 0x100
        let regAddr = baseAddr + Int(subAddr)
        
        // レジスタに値を設定
        opnaRegisters[regAddr] = value
        
        // リズム音源レジスタの処理
        switch subAddr {
        case 0x10:  // リズム音源制御レジスタ
            let rhythmEnable = (value & 0x01) != 0
            let bass = (value & 0x02) != 0
            let snare = (value & 0x04) != 0
            let tom = (value & 0x08) != 0
            let cymbal = (value & 0x10) != 0
            let hihat = (value & 0x20) != 0
            let rimShot = (value & 0x40) != 0  // リムショット（PC-8801では使用されない場合がある）
            
            let chipName = isMainChip ? "Main" : "Sub"
            var logMessage = "\(chipName) Rhythm Control: "
            logMessage += rhythmEnable ? "ON " : "OFF "
            logMessage += bass ? "BD " : ""
            logMessage += snare ? "SD " : ""
            logMessage += tom ? "TOM " : ""
            logMessage += cymbal ? "CYM " : ""
            logMessage += hihat ? "HH " : ""
            logMessage += rimShot ? "RIM " : ""
            
            addDebugLog(logMessage)
            
            // PMD88のリズム音源フック処理（RHYSET）の監視
            if isMainChip && rhythmEnable {
                monitorRhythmHook()
            }
            
        case 0x11:  // リズム音源総合ボリューム
            let volume = value & 0x3F
            let chipName = isMainChip ? "Main" : "Sub"
            addDebugLog("\(chipName) Rhythm Total Volume: \(volume)")
            
        case 0x18:  // バスドラムボリューム
            let volume = value & 0x1F
            let pan = (value >> 6) & 0x03
            let panStr = getPanString(pan)
            
            let chipName = isMainChip ? "Main" : "Sub"
            addDebugLog("\(chipName) Bass Drum Volume: \(volume), Pan: \(panStr)")
            
        case 0x19:  // スネアドラムボリューム
            let volume = value & 0x1F
            let pan = (value >> 6) & 0x03
            let panStr = getPanString(pan)
            
            let chipName = isMainChip ? "Main" : "Sub"
            addDebugLog("\(chipName) Snare Drum Volume: \(volume), Pan: \(panStr)")
            
        case 0x1A:  // トムボリューム
            let volume = value & 0x1F
            let pan = (value >> 6) & 0x03
            let panStr = getPanString(pan)
            
            let chipName = isMainChip ? "Main" : "Sub"
            addDebugLog("\(chipName) Tom Volume: \(volume), Pan: \(panStr)")
            
        case 0x1B:  // シンバルボリューム
            let volume = value & 0x1F
            let pan = (value >> 6) & 0x03
            let panStr = getPanString(pan)
            
            let chipName = isMainChip ? "Main" : "Sub"
            addDebugLog("\(chipName) Cymbal Volume: \(volume), Pan: \(panStr)")
            
        case 0x1C:  // ハイハットボリューム
            let volume = value & 0x1F
            let pan = (value >> 6) & 0x03
            let panStr = getPanString(pan)
            
            let chipName = isMainChip ? "Main" : "Sub"
            addDebugLog("\(chipName) Hi-Hat Volume: \(volume), Pan: \(panStr)")
            
        case 0x1D:  // リムショットボリューム（PC-8801では使用されない場合がある）
            let volume = value & 0x1F
            let pan = (value >> 6) & 0x03
            let panStr = getPanString(pan)
            
            let chipName = isMainChip ? "Main" : "Sub"
            addDebugLog("\(chipName) Rim Shot Volume: \(volume), Pan: \(panStr)")
            
        default:
            if subAddr >= 0x20 && subAddr <= 0x2F {
                // 0x20-0x2Fはリズム音源の音色設定
                handleRhythmToneRegister(isMainChip: isMainChip, subAddr: subAddr, value: value)
            }
        }
    }
    
    // リズム音源の音色レジスタ処理
    private func handleRhythmToneRegister(isMainChip: Bool, subAddr: UInt8, value: UInt8) {
        let baseAddr = isMainChip ? 0 : 0x100
        let regAddr = baseAddr + Int(subAddr)
        
        // レジスタに値を設定
        opnaRegisters[regAddr] = value
        
        let chipName = isMainChip ? "Main" : "Sub"
        let instrumentIndex = subAddr - 0x20
        var instrumentName = "Unknown"
        
        switch instrumentIndex {
        case 0, 1:
            instrumentName = "Bass Drum"
        case 2, 3:
            instrumentName = "Snare Drum"
        case 4, 5:
            instrumentName = "Tom"
        case 6, 7:
            instrumentName = "Cymbal"
        case 8, 9:
            instrumentName = "Hi-Hat"
        case 10, 11:
            instrumentName = "Rim Shot"
        default:
            instrumentName = "Unknown Rhythm Instrument"
        }
        
        addDebugLog("\(chipName) Rhythm Tone Register: \(instrumentName) [\(String(format: "0x%02X", subAddr))] = \(String(format: "0x%02X", value))")
    }
    
    // パン設定の文字列取得
    private func getPanString(_ pan: UInt8) -> String {
        switch pan {
        case 0:
            return "None"
        case 1:
            return "Right"
        case 2:
            return "Left"
        case 3:
            return "Center"
        default:
            return "Unknown"
        }
    }
    
    // リズム音源の状態取得
    func getRhythmStatus(isMainChip: Bool) -> String {
        let baseAddr = isMainChip ? 0 : 0x100
        let control = opnaRegisters[baseAddr + 0x10]
        let totalVolume = opnaRegisters[baseAddr + 0x11]
        
        let rhythmEnable = (control & 0x01) != 0
        let bass = (control & 0x02) != 0
        let snare = (control & 0x04) != 0
        let tom = (control & 0x08) != 0
        let cymbal = (control & 0x10) != 0
        let hihat = (control & 0x20) != 0
        let rimShot = (control & 0x40) != 0
        
        let chipName = isMainChip ? "Main" : "Sub"
        var status = "\(chipName) Rhythm Status:\n"
        status += "Rhythm Enable: \(rhythmEnable ? "ON" : "OFF")\n"
        status += "Total Volume: \(totalVolume & 0x3F)\n"
        status += "Active Instruments: "
        status += bass ? "Bass Drum " : ""
        status += snare ? "Snare Drum " : ""
        status += tom ? "Tom " : ""
        status += cymbal ? "Cymbal " : ""
        status += hihat ? "Hi-Hat " : ""
        status += rimShot ? "Rim Shot " : ""
        status += "\n\n"
        
        // 各楽器のボリュームとパン設定
        let instruments = [
            ("Bass Drum", opnaRegisters[baseAddr + 0x18]),
            ("Snare Drum", opnaRegisters[baseAddr + 0x19]),
            ("Tom", opnaRegisters[baseAddr + 0x1A]),
            ("Cymbal", opnaRegisters[baseAddr + 0x1B]),
            ("Hi-Hat", opnaRegisters[baseAddr + 0x1C]),
            ("Rim Shot", opnaRegisters[baseAddr + 0x1D])
        ]
        
        status += "Instrument Settings:\n"
        for (name, value) in instruments {
            let volume = value & 0x1F
            let pan = (value >> 6) & 0x03
            let panStr = getPanString(pan)
            
            status += "\(name): Volume=\(volume), Pan=\(panStr)\n"
        }
        
        return status
    }
    
    // PMD88のリズム音源フック処理（RHYSET）の監視
    private func monitorRhythmHook() {
        // PMD88のRHYSETフックアドレス（0B70EH）
        let rhysetHookAddr = 0x0B70E
        
        // 現在のPCがRHYSETフックアドレス付近かチェック
        if pc >= rhysetHookAddr && pc <= rhysetHookAddr + 10 {
            // リズム音源の状態を詳細に記録
            let rhythmStatus = getRhythmStatus(isMainChip: true)
            addDebugLog("PMD88 RHYSET Hook detected at PC=\(String(format: "0x%04X", pc))")
            addDebugLog(rhythmStatus)
            
            // PMD88のワークエリアからリズム情報を取得
            let pmdRhythmStatus = getPMD88RhythmStatus()
            addDebugLog(pmdRhythmStatus)
        }
    }
    
    // PMD88のリズム音源ワークエリア情報取得
    func getPMD88RhythmStatus() -> String {
        // PMD88のリズムワークエリアのベースアドレス（仮の値、実際のアドレスに置き換える）
        let rhythmWorkArea = 0xC600
        
        var status = "PMD88 Rhythm Work Area:\n"
        
        // リズム音源の有効状態
        if rhythmWorkArea < memory.count {
            let rhythmEnable = memory[rhythmWorkArea]
            status += "Rhythm Enable: \(rhythmEnable != 0 ? "ON" : "OFF")\n"
            
            // 各楽器の状態
            if rhythmWorkArea + 6 < memory.count {
                let bdVolume = memory[rhythmWorkArea + 1]
                let sdVolume = memory[rhythmWorkArea + 2]
                let cyVolume = memory[rhythmWorkArea + 3]
                let hhVolume = memory[rhythmWorkArea + 4]
                let tomVolume = memory[rhythmWorkArea + 5]
                let rimVolume = memory[rhythmWorkArea + 6]
                
                status += "Bass Drum Volume: \(bdVolume)\n"
                status += "Snare Drum Volume: \(sdVolume)\n"
                status += "Cymbal Volume: \(cyVolume)\n"
                status += "Hi-Hat Volume: \(hhVolume)\n"
                status += "Tom Volume: \(tomVolume)\n"
                status += "Rim Shot Volume: \(rimVolume)\n"
            }
            
            // リズムパターン情報
            if rhythmWorkArea + 16 < memory.count {
                let rhythmPattern = memory[rhythmWorkArea + 16]
                status += "Rhythm Pattern: \(String(format: "0x%02X", rhythmPattern))\n"
                
                // パターンの解析
                var patternDesc = "Pattern: "
                if (rhythmPattern & 0x01) != 0 { patternDesc += "BD " }
                if (rhythmPattern & 0x02) != 0 { patternDesc += "SD " }
                if (rhythmPattern & 0x04) != 0 { patternDesc += "TOP " }
                if (rhythmPattern & 0x08) != 0 { patternDesc += "HH " }
                if (rhythmPattern & 0x10) != 0 { patternDesc += "TOM " }
                if (rhythmPattern & 0x20) != 0 { patternDesc += "RIM " }
                
                status += patternDesc + "\n"
            }
        }
        
        return status
    }
    
    // リズム音源のキーオン状態を取得
    func getRhythmKeyOnStatus(isMainChip: Bool) -> [String: Bool] {
        let baseAddr = isMainChip ? 0 : 0x100
        let control = opnaRegisters[baseAddr + 0x10]
        
        return [
            "BassDrum": (control & 0x02) != 0,
            "SnareDrum": (control & 0x04) != 0,
            "Tom": (control & 0x08) != 0,
            "Cymbal": (control & 0x10) != 0,
            "HiHat": (control & 0x20) != 0,
            "RimShot": (control & 0x40) != 0
        ]
    }
    
    // リズム音源の音量設定を取得
    func getRhythmVolumes(isMainChip: Bool) -> [String: Int] {
        let baseAddr = isMainChip ? 0 : 0x100
        
        return [
            "TotalVolume": Int(opnaRegisters[baseAddr + 0x11] & 0x3F),
            "BassDrum": Int(opnaRegisters[baseAddr + 0x18] & 0x1F),
            "SnareDrum": Int(opnaRegisters[baseAddr + 0x19] & 0x1F),
            "Tom": Int(opnaRegisters[baseAddr + 0x1A] & 0x1F),
            "Cymbal": Int(opnaRegisters[baseAddr + 0x1B] & 0x1F),
            "HiHat": Int(opnaRegisters[baseAddr + 0x1C] & 0x1F),
            "RimShot": Int(opnaRegisters[baseAddr + 0x1D] & 0x1F)
        ]
    }
    
    // PMD88のリズムフック（PMDHK3）の監視
    func monitorPMDRhythmHook() {
        // PMD88のPMDHK3フックアドレス（0B70EH）
        let pmdhk3Addr = 0x0B70E
        
        // 現在のPCがPMDHK3フックアドレス付近かチェック
        if pc >= pmdhk3Addr && pc <= pmdhk3Addr + 10 {
            // リズム音源の状態を詳細に記録
            let rhythmStatus = getRhythmStatus(isMainChip: true)
            addDebugLog("PMD88 PMDHK3 (RHYSET) Hook detected at PC=\(String(format: "0x%04X", pc))")
            addDebugLog(rhythmStatus)
            
            // PMD88のワークエリアからリズム情報を取得
            let pmdRhythmStatus = getPMD88RhythmStatus()
            addDebugLog(pmdRhythmStatus)
            
            // 現在のリズム音源のキーオン状態
            let keyOnStatus = getRhythmKeyOnStatus(isMainChip: true)
            var keyOnStr = "Rhythm Key On: "
            for (instrument, isOn) in keyOnStatus {
                if isOn {
                    keyOnStr += "\(instrument) "
                }
            }
            addDebugLog(keyOnStr)
        }
    }
}
