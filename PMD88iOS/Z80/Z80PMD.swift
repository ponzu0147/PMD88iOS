import Foundation

// Z80 PMD88-specific functionality
extension Z80 {
    // PMD88ワークエリアの定数
    private struct PMDWorkArea {
        // ベースアドレス
        static let base = 0xC200
        
        // 各チャンネルのオフセット
        static let ssgChannelSize = 0x20
        static let fmChannelSize = 0x20
        
        // SSGチャンネルのベースアドレス (3チャンネル)
        static let ssgBase = base
        
        // FMチャンネルのベースアドレス (6チャンネル)
        static let fmBase = base + 0x100
        
        // リズムチャンネルのベースアドレス
        static let rhythmBase = base + 0x200
        
        // ADPCMチャンネルのベースアドレス
        static let adpcmBase = base + 0x300
        
        // PMD88フックアドレス
        static let pmdhk1 = 0xAA5F  // 音楽再生メインルーチン
        static let pmdhk2 = 0xB9CA  // ボリューム制御（VOLPUSH_CALC）
        static let pmdhk3 = 0xB70E  // リズム音源のキーオン処理（RHYSET）
    }
    
    // PMD88の状態を監視
    func monitorPMD88() {
        // PMD88のフックアドレスを監視
        monitorPMDHooks()
        
        // 定期的にPMD88ワークエリアの状態を確認（例：1000ステップごと）
        if stepCount % 1000 == 0 {
            let pmdStatus = getPMD88Status()
            addDebugLog("PMD88 Periodic Status Check:")
            addDebugLog(pmdStatus)
        }
    }
    
    // PMD88のフックを監視
    private func monitorPMDHooks() {
        // PMDHK1（音楽再生メインルーチン）
        if pc >= PMDWorkArea.pmdhk1 && pc <= PMDWorkArea.pmdhk1 + 10 {
            addDebugLog("PMD88 PMDHK1 Hook detected at PC=\(String(format: "0x%04X", pc))")
            // 必要に応じて追加の処理
        }
        
        // PMDHK2（ボリューム制御）
        if pc >= PMDWorkArea.pmdhk2 && pc <= PMDWorkArea.pmdhk2 + 10 {
            addDebugLog("PMD88 PMDHK2 Hook detected at PC=\(String(format: "0x%04X", pc))")
            // 必要に応じて追加の処理
        }
        
        // PMDHK3（リズム音源のキーオン処理）
        if pc >= PMDWorkArea.pmdhk3 && pc <= PMDWorkArea.pmdhk3 + 10 {
            addDebugLog("PMD88 PMDHK3 Hook detected at PC=\(String(format: "0x%04X", pc))")
            
            // リズム音源の状態を詳細に記録
            let rhythmStatus = getRhythmStatus(isMainChip: true)
            addDebugLog(rhythmStatus)
            
            // PMD88のワークエリアからリズム情報を取得
            let pmdRhythmStatus = getPMD88RhythmStatusPMD()
            addDebugLog(pmdRhythmStatus)
        }
    }
    
    // PMD88の全体状態を取得
    func getPMD88Status() -> String {
        var status = "PMD88 Status:\n"
        
        // SSGチャンネルの状態
        status += "SSG Channels:\n"
        for ch in 0..<3 {
            status += getSSGChannelStatus(channel: ch)
        }
        
        // FMチャンネルの状態
        status += "\nFM Channels:\n"
        for ch in 0..<6 {
            status += getFMChannelStatus(channel: ch)
        }
        
        // リズム音源の状態
        status += "\n" + getPMD88RhythmStatusPMD()
        
        // ADPCM状態
        status += "\n" + getPMD88ADPCMStatus()
        
        return status
    }
    
    // SSGチャンネルの状態を取得
    private func getSSGChannelStatus(channel: Int) -> String {
        let baseAddr = PMDWorkArea.ssgBase + (channel * PMDWorkArea.ssgChannelSize)
        
        if baseAddr >= memory.count {
            return "Channel \(channel): Memory out of range\n"
        }
        
        // 各種パラメータの取得
        let toneAddr = baseAddr + 0x10
        let volumeAddr = baseAddr + 0x18
        let panAddr = baseAddr + 0x19
        let keyOnAddr = baseAddr + 0x1A
        
        let toneValue = readMemory16PMD(at: toneAddr)
        let volume = Int(memory[volumeAddr])
        let pan = memory[panAddr]
        let keyOn = memory[keyOnAddr] != 0
        
        let noteName = estimateSSGNoteSSG(toneValue: toneValue)
        
        var status = "Channel \(channel): "
        status += "Tone=\(toneValue) (\(noteName)), "
        status += "Volume=\(volume), "
        status += "Pan=\(String(format: "0x%02X", pan)), "
        status += "KeyOn=\(keyOn ? "ON" : "OFF")\n"
        
        return status
    }
    
    // FMチャンネルの状態を取得
    private func getFMChannelStatus(channel: Int) -> String {
        let baseAddr = PMDWorkArea.fmBase + (channel * PMDWorkArea.fmChannelSize)
        
        if baseAddr >= memory.count {
            return "Channel \(channel): Memory out of range\n"
        }
        
        // 各種パラメータの取得
        let fNumAddr = baseAddr + 0x10
        let blockAddr = baseAddr + 0x12
        let volumeAddr = baseAddr + 0x18
        let panAddr = baseAddr + 0x19
        let keyOnAddr = baseAddr + 0x1A
        
        let fNumber = readMemory16PMD(at: fNumAddr)
        let block = Int(memory[blockAddr] & 0x07)
        let volume = Int(memory[volumeAddr])
        let pan = memory[panAddr]
        let keyOn = memory[keyOnAddr] != 0
        
        let noteName = calculateFMNote(fNumber: fNumber, block: block)
        
        var status = "Channel \(channel): "
        status += "F-Number=\(fNumber), Block=\(block), Note=\(noteName), "
        status += "Volume=\(volume), "
        status += "Pan=\(String(format: "0x%02X", pan)), "
        status += "KeyOn=\(keyOn ? "ON" : "OFF")\n"
        
        return status
    }
    
    // PMD88のリズム音源状態を取得
    func getPMD88RhythmStatusPMD() -> String {
        let baseAddr = PMDWorkArea.rhythmBase
        
        if baseAddr >= memory.count {
            return "Rhythm: Memory out of range\n"
        }
        
        var status = "Rhythm Status:\n"
        
        // リズム音源の有効状態
        let rhythmEnable = memory[baseAddr] != 0
        status += "  Rhythm Enable: \(rhythmEnable ? "ON" : "OFF")\n"
        
        // 各楽器の状態
        if baseAddr + 6 < memory.count {
            let bdVolume = memory[baseAddr + 1]
            let sdVolume = memory[baseAddr + 2]
            let cyVolume = memory[baseAddr + 3]
            let hhVolume = memory[baseAddr + 4]
            let tomVolume = memory[baseAddr + 5]
            let rimVolume = memory[baseAddr + 6]
            
            status += "  Bass Drum Volume: \(bdVolume)\n"
            status += "  Snare Drum Volume: \(sdVolume)\n"
            status += "  Cymbal Volume: \(cyVolume)\n"
            status += "  Hi-Hat Volume: \(hhVolume)\n"
            status += "  Tom Volume: \(tomVolume)\n"
            status += "  Rim Shot Volume: \(rimVolume)\n"
        }
        
        // リズムパターン情報
        if baseAddr + 16 < memory.count {
            let rhythmPattern = memory[baseAddr + 16]
            status += "  Rhythm Pattern: \(String(format: "0x%02X", rhythmPattern))\n"
            
            // パターンの解析
            var patternDesc = "  Pattern: "
            if (rhythmPattern & 0x01) != 0 { patternDesc += "BD " }
            if (rhythmPattern & 0x02) != 0 { patternDesc += "SD " }
            if (rhythmPattern & 0x04) != 0 { patternDesc += "TOP " }
            if (rhythmPattern & 0x08) != 0 { patternDesc += "HH " }
            if (rhythmPattern & 0x10) != 0 { patternDesc += "TOM " }
            if (rhythmPattern & 0x20) != 0 { patternDesc += "RIM " }
            
            status += patternDesc + "\n"
        }
        
        return status
    }
    
    // PMD88のADPCM状態を取得
    func getPMD88ADPCMStatus() -> String {
        let baseAddr = PMDWorkArea.adpcmBase
        
        if baseAddr >= memory.count {
            return "ADPCM: Memory out of range\n"
        }
        
        var status = "ADPCM Status:\n"
        
        // ADPCM有効状態
        let adpcmEnable = memory[baseAddr] != 0
        status += "  ADPCM Enable: \(adpcmEnable ? "ON" : "OFF")\n"
        
        // 各種パラメータ
        if baseAddr + 16 < memory.count {
            let volume = memory[baseAddr + 1]
            let pan = memory[baseAddr + 2]
            let startAddr = readMemory16PMD(at: baseAddr + 4)
            let stopAddr = readMemory16PMD(at: baseAddr + 6)
            let deltaAddr = readMemory16PMD(at: baseAddr + 8)
            
            status += "  Volume: \(volume)\n"
            status += "  Pan: \(String(format: "0x%02X", pan))\n"
            status += "  Start Address: \(String(format: "0x%04X", startAddr))\n"
            status += "  Stop Address: \(String(format: "0x%04X", stopAddr))\n"
            status += "  Delta-N: \(String(format: "0x%04X", deltaAddr))\n"
        }
        
        return status
    }
    
    // PMD88のFMキーオン状態を監視
    func monitorFMKeyOn() {
        // OPNAレジスタ0x28（キーオン/オフレジスタ）の書き込みを監視
        let keyOnValue = opnaRegisters[0x28]
        
        // キーオン状態の解析
        for ch in 0..<6 {
            let isExtended = ch >= 3
            let chValue = ch % 3
            let keyOnBit = 1 << (chValue + (isExtended ? 4 : 0))
            
            let isKeyOn = (keyOnValue & UInt8(keyOnBit)) != 0
            
            // キーオン状態が変化した場合のみログ出力
            let lastKeyOnState = fmKeyOnState[ch]
            if isKeyOn != lastKeyOnState {
                fmKeyOnState[ch] = isKeyOn
                
                // FMチャンネルのパラメータを取得
                let fmStatus = getFMChannelStatus(channel: ch)
                
                // FMキーオン状態の変化をログに記録
                addDebugLog("FM Channel \(ch) Key \(isKeyOn ? "ON" : "OFF")")
                addDebugLog(fmStatus)
                
                // OPNAレジスタの状態を詳細に記録
                let fmRegisterStatus = getFMChannelRegisterStatus(channel: ch)
                addDebugLog(fmRegisterStatus)
            }
        }
    }
    
    // FMチャンネルのレジスタ状態を取得
    private func getFMChannelRegisterStatus(channel: Int) -> String {
        let isExtended = channel >= 3
        let chValue = channel % 3
        let baseAddr = isExtended ? 0x100 : 0
        
        var status = "FM Channel \(channel) Registers:\n"
        
        // 周波数情報
        let fNumberLSB = opnaRegisters[baseAddr + 0xA0 + chValue]
        let fNumberMSB = opnaRegisters[baseAddr + 0xA4 + chValue] & 0x07
        let block = (opnaRegisters[baseAddr + 0xA4 + chValue] >> 3) & 0x07
        let fNumber = (Int(fNumberMSB) << 8) | Int(fNumberLSB)
        let noteName = calculateFMNote(fNumber: fNumber, block: Int(block))
        
        status += String(format: "  Frequency: F-Number=%d, Block=%d, Note=%@\n", fNumber, block, noteName)
        
        // アルゴリズムとフィードバック
        let algorithm = opnaRegisters[baseAddr + 0xB0 + chValue] & 0x07
        let feedback = (opnaRegisters[baseAddr + 0xB0 + chValue] >> 3) & 0x07
        
        status += String(format: "  Algorithm=%d, Feedback=%d\n", algorithm, feedback)
        
        // 出力設定
        let leftOutput = (opnaRegisters[baseAddr + 0xB4 + chValue] & 0x80) != 0
        let rightOutput = (opnaRegisters[baseAddr + 0xB4 + chValue] & 0x40) != 0
        let ams = (opnaRegisters[baseAddr + 0xB4 + chValue] >> 4) & 0x03
        let pms = opnaRegisters[baseAddr + 0xB4 + chValue] & 0x07
        
        status += String(format: "  Output: Left=%@, Right=%@, AMS=%d, PMS=%d\n", leftOutput ? "ON" : "OFF", rightOutput ? "ON" : "OFF", ams, pms)
        
        return status
    }
    
    // PMD88のSSGキーオン状態を監視
    func monitorSSGKeyOn() {
        // OPNAレジスタ0x07（ミキサーレジスタ）の書き込みを監視
        let mixerValue = opnaRegisters[0x07]
        
        // 各SSGチャンネルのトーン有効状態
        let toneA = (mixerValue & 0x01) == 0
        let toneB = (mixerValue & 0x02) == 0
        let toneC = (mixerValue & 0x04) == 0
        
        // 各SSGチャンネルのノイズ有効状態
        let noiseA = (mixerValue & 0x08) == 0
        let noiseB = (mixerValue & 0x10) == 0
        let noiseC = (mixerValue & 0x20) == 0
        
        // 現在のSSG状態
        let currentSSGState = [
            (toneA, noiseA),
            (toneB, noiseB),
            (toneC, noiseC)
        ]
        
        // 状態が変化した場合のみログ出力
        for ch in 0..<3 {
            let (tone, noise) = currentSSGState[ch]
            let (lastTone, lastNoise) = ssgKeyOnState[ch]
            
            if tone != lastTone || noise != lastNoise {
                ssgKeyOnState[ch] = (tone, noise)
                
                // SSGチャンネルのパラメータを取得
                let ssgStatus = getSSGChannelStatus(channel: ch)
                
                // SSG状態の変化をログに記録
                addDebugLog("SSG Channel \(ch) Tone: \(tone ? "ON" : "OFF"), Noise: \(noise ? "ON" : "OFF")")
                addDebugLog(ssgStatus)
                
                // OPNAレジスタの状態を詳細に記録
                let ssgRegisterStatus = getSSGChannelRegisterStatus(channel: ch)
                addDebugLog(ssgRegisterStatus)
            }
        }
    }
    
    // SSGチャンネルのレジスタ状態を取得
    private func getSSGChannelRegisterStatus(channel: Int) -> String {
        var status = "SSG Channel \(channel) Registers:\n"
        
        // トーン値
        let toneAddrLow = 0x00 + (channel * 2)
        let toneAddrHigh = 0x01 + (channel * 2)
        let toneLow = opnaRegisters[toneAddrLow]
        let toneHigh = opnaRegisters[toneAddrHigh]
        let toneValue = (Int(toneHigh) << 8) | Int(toneLow)
        let noteName = estimateSSGNoteSSG(toneValue: toneValue)
        
        status += String(format: "  Tone: %d (%@)\n", toneValue, noteName)
        
        // ボリューム
        let volumeAddr = 0x08 + channel
        let volume = opnaRegisters[volumeAddr] & 0x0F
        let useEnvelope = (opnaRegisters[volumeAddr] & 0x10) != 0
        
        status += String(format: "  Volume: %d, Envelope: %@\n", volume, useEnvelope ? "ON" : "OFF")
        
        // ミキサー設定
        let mixerValue = opnaRegisters[0x07]
        let toneEnabled = (mixerValue & (1 << channel)) == 0
        let noiseEnabled = (mixerValue & (1 << (channel + 3))) == 0
        
        status += String(format: "  Mixer: Tone=%@, Noise=%@\n", toneEnabled ? "ON" : "OFF", noiseEnabled ? "ON" : "OFF")
        
        return status
    }
    
    // PMD88の曲情報を解析
    func analyzePMD88Song() -> String {
        var analysis = "PMD88 Song Analysis:\n"
        
        // PMD88の曲情報ワークエリア（仮の値、実際のアドレスに置き換える）
        let songInfoAddr = 0xC100
        
        if songInfoAddr < memory.count {
            // テンポ情報
            let tempo = memory[songInfoAddr]
            analysis += "Tempo: \(tempo)\n"
            
            // 曲のステータス
            let status = memory[songInfoAddr + 1]
            let isPlaying = (status & 0x01) != 0
            analysis += "Status: \(isPlaying ? "Playing" : "Stopped")\n"
            
            // 各チャンネルの状態
            analysis += "\nChannel Status:\n"
            
            // SSGチャンネル
            for ch in 0..<3 {
                analysis += getSSGChannelStatus(channel: ch)
            }
            
            // FMチャンネル
            for ch in 0..<6 {
                analysis += getFMChannelStatus(channel: ch)
            }
            
            // リズムチャンネル
            analysis += getPMD88RhythmStatusPMD()
            
            // ADPCMチャンネル
            analysis += getPMD88ADPCMStatus()
        } else {
            analysis += "Song info memory out of range\n"
        }
        
        return analysis
    }
    
    // PMD88のフックアドレスを設定
    func setPMD88HookAddresses(pmdhk1: Int, pmdhk2: Int, pmdhk3: Int) {
        // PMD88のフックアドレスを設定
        pmd88HookAddresses = [pmdhk1, pmdhk2, pmdhk3]
        addDebugLog("PMD88 Hook Addresses set: PMDHK1=\(String(format: "0x%04X", pmdhk1)), PMDHK2=\(String(format: "0x%04X", pmdhk2)), PMDHK3=\(String(format: "0x%04X", pmdhk3))")
    }
    
    // PMD88のフックアドレスを監視
    func checkPMD88Hooks() {
        // 現在のPCがPMD88のフックアドレスと一致するか確認
        if pmd88HookAddresses.contains(pc) {
            let hookIndex = pmd88HookAddresses.firstIndex(of: pc) ?? -1
            let hookName = hookIndex >= 0 ? "PMDHK\(hookIndex + 1)" : "Unknown"
            
            addDebugLog("PMD88 \(hookName) Hook executed at PC=\(String(format: "0x%04X", pc))")
            
            // フック種類に応じた処理
            switch hookIndex {
            case 0:  // PMDHK1（音楽再生メインルーチン）
                let pmdStatus = getPMD88Status()
                addDebugLog("PMD88 Main Routine Status:")
                addDebugLog(pmdStatus)
                
            case 1:  // PMDHK2（ボリューム制御）
                // ボリューム関連の状態を記録
                for ch in 0..<3 {
                    addDebugLog(getSSGChannelStatus(channel: ch))
                }
                for ch in 0..<6 {
                    addDebugLog(getFMChannelStatus(channel: ch))
                }
                
            case 2:  // PMDHK3（リズム音源のキーオン処理）
                let rhythmStatus = getRhythmStatus(isMainChip: true)
                addDebugLog(rhythmStatus)
                
                let pmdRhythmStatus = getPMD88RhythmStatusPMD()
                addDebugLog(pmdRhythmStatus)
                
            default:
                break
            }
        }
    }
    
    // 16ビットメモリ読み込み（リトルエンディアン）
    func readMemory16PMD(at address: Int) -> Int {
        if address + 1 < memory.count {
            let lowByte = memory[address]
            let highByte = memory[address + 1]
            return (Int(highByte) << 8) | Int(lowByte)
        }
        return 0
    }
}
