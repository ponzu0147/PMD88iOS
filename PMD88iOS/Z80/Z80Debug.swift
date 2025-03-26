import Foundation

// Z80 debugging features
extension Z80 {
    // デバッグ情報の出力
    func printDebugInfo() -> String {
        var info = "Z80 CPU State:\n"
        info += "PC=\(String(format: "0x%04X", pc)) SP=\(String(format: "0x%04X", sp))\n"
        info += "A=\(String(format: "0x%02X", a)) F=\(String(format: "0x%02X", f)) BC=\(String(format: "0x%04X", bc())) DE=\(String(format: "0x%04X", de())) HL=\(String(format: "0x%04X", hl()))\n"
        info += "IX=\(String(format: "0x%04X", ix())) IY=\(String(format: "0x%04X", iy())) I=\(String(format: "0x%02X", i)) R=\(String(format: "0x%02X", r))\n"
        
        // フラグの状態
        let flagsStr = [
            (f & S_FLAG) != 0 ? "S" : "-",
            (f & Z_FLAG) != 0 ? "Z" : "-",
            "-",
            (f & H_FLAG) != 0 ? "H" : "-",
            "-",
            (f & P_FLAG) != 0 ? "P/V" : "-",
            (f & N_FLAG) != 0 ? "N" : "-",
            (f & C_FLAG) != 0 ? "C" : "-"
        ].joined()
        info += "Flags: \(flagsStr)\n"
        
        // 現在の命令
        if pc < memory.count {
            let opcode = memory[pc]
            info += "Current opcode: \(String(format: "0x%02X", opcode))\n"
        }
        
        return info
    }
    
    // レジスタダンプ
    func dumpRegisters() -> String {
        return printDebugInfo()
    }
    
    // デバッグログの取得
    func getDebugLog() -> [String] {
        return debugLog
    }
    
    // デバッグログのクリア
    func clearDebugLog() {
        debugLog = []
    }
    
    // ブレークポイントの設定
    func setBreakPoint(at address: Int) {
        breakPoint = address
        addDebugLog("ブレークポイント設定: \(String(format: "0x%04X", address))")
    }
    
    // ブレークポイントのクリア
    func clearBreakPoint() {
        breakPoint = -1
        addDebugLog("ブレークポイントクリア")
    }
    
    // OPNAレジスタダンプ
    func dumpOPNARegisters() -> String {
        var dump = "OPNA Registers:\n"
        
        // 表FM音源レジスタ
        dump += "Main FM Registers:\n"
        for i in 0..<0x100 {
            if i % 16 == 0 {
                dump += String(format: "%02X:", i)
            }
            dump += String(format: " %02X", opnaRegisters[i])
            if (i + 1) % 16 == 0 {
                dump += "\n"
            }
        }
        
        // 裏FM音源レジスタ
        dump += "\nSub FM Registers:\n"
        for i in 0x100..<0x200 {
            if i % 16 == 0 {
                dump += String(format: "%02X:", i - 0x100)
            }
            dump += String(format: " %02X", opnaRegisters[i])
            if (i + 1) % 16 == 0 {
                dump += "\n"
            }
        }
        
        return dump
    }
    
    // SSGレジスタダンプ
    func dumpSSGRegisters() -> String {
        var dump = "SSG Registers:\n"
        
        // 表SSGレジスタ (0x00-0x0F)
        dump += "Main SSG:\n"
        for i in 0...0x0F {
            dump += String(format: "%02X: %02X", i, opnaRegisters[i])
            
            switch i {
            case 0x00, 0x02, 0x04:
                let chIndex = i / 2
                let ch = ["A", "B", "C"][chIndex]
                let lsbValue = opnaRegisters[i]
                let msbValue = opnaRegisters[i + 1]
                let toneValue = (Int(msbValue) << 8) | Int(lsbValue)
                let noteName = estimateSSGNoteSSG(toneValue: toneValue)
                dump += String(format: " - CH%@ Tone LSB, Value=%d (%@)", ch, toneValue, noteName)
                
            case 0x01, 0x03, 0x05:
                let chIndex = (i - 1) / 2
                let ch = ["A", "B", "C"][chIndex]
                dump += String(format: " - CH%@ Tone MSB", ch)
                
            case 0x06:
                dump += String(format: " - Noise Period: %d", opnaRegisters[i] & 0x1F)
                
            case 0x07:
                let toneA = (opnaRegisters[i] & 0x01) == 0
                let toneB = (opnaRegisters[i] & 0x02) == 0
                let toneC = (opnaRegisters[i] & 0x04) == 0
                let noiseA = (opnaRegisters[i] & 0x08) == 0
                let noiseB = (opnaRegisters[i] & 0x10) == 0
                let noiseC = (opnaRegisters[i] & 0x20) == 0
                dump += " - Mixer: "
                dump += "Tone(A:\(toneA ? "ON" : "OFF"),B:\(toneB ? "ON" : "OFF"),C:\(toneC ? "ON" : "OFF")) "
                dump += "Noise(A:\(noiseA ? "ON" : "OFF"),B:\(noiseB ? "ON" : "OFF"),C:\(noiseC ? "ON" : "OFF"))"
                
            case 0x08, 0x09, 0x0A:
                let chIndex = i - 0x08
                let ch = ["A", "B", "C"][chIndex]
                let volume = opnaRegisters[i] & 0x0F
                let useEnvelope = (opnaRegisters[i] & 0x10) != 0
                dump += String(format: " - CH%@ Volume: %d, Envelope: %@", ch, volume, useEnvelope ? "ON" : "OFF")
                
            case 0x0B, 0x0C:
                let regName = i == 0x0B ? "Envelope Period LSB" : "Envelope Period MSB"
                dump += " - \(regName)"
                
            case 0x0D:
                let shapeName: String
                switch opnaRegisters[i] & 0x0F {
                case 0x00, 0x04, 0x08, 0x0C: shapeName = "\\___"
                case 0x01, 0x05, 0x09, 0x0D: shapeName = "/__/"
                case 0x02, 0x06, 0x0A, 0x0E: shapeName = "\\\\\\\\"
                case 0x03, 0x07, 0x0B, 0x0F: shapeName = "////"
                default: shapeName = "???"
                }
                dump += " - Envelope Shape: \(shapeName)"
                
            default:
                dump += " - Other"
            }
            
            dump += "\n"
        }
        
        // 裏SSGレジスタ (0x100-0x10F)
        dump += "\nSub SSG:\n"
        for i in 0x100...0x10F {
            let subAddr = i - 0x100
            dump += String(format: "%02X: %02X", subAddr, opnaRegisters[i])
            
            switch subAddr {
            case 0x00, 0x02, 0x04:
                let chIndex = subAddr / 2
                let ch = ["A", "B", "C"][chIndex]
                let lsbValue = opnaRegisters[i]
                let msbValue = opnaRegisters[i + 1]
                let toneValue = (Int(msbValue) << 8) | Int(lsbValue)
                let noteName = estimateSSGNoteSSG(toneValue: toneValue)
                dump += String(format: " - CH%@ Tone LSB, Value=%d (%@)", ch, toneValue, noteName)
                
            case 0x01, 0x03, 0x05:
                let chIndex = (subAddr - 1) / 2
                let ch = ["A", "B", "C"][chIndex]
                dump += String(format: " - CH%@ Tone MSB", ch)
                
            case 0x06:
                dump += String(format: " - Noise Period: %d", opnaRegisters[i] & 0x1F)
                
            case 0x07:
                let toneA = (opnaRegisters[i] & 0x01) == 0
                let toneB = (opnaRegisters[i] & 0x02) == 0
                let toneC = (opnaRegisters[i] & 0x04) == 0
                let noiseA = (opnaRegisters[i] & 0x08) == 0
                let noiseB = (opnaRegisters[i] & 0x10) == 0
                let noiseC = (opnaRegisters[i] & 0x20) == 0
                dump += " - Mixer: "
                dump += "Tone(A:\(toneA ? "ON" : "OFF"),B:\(toneB ? "ON" : "OFF"),C:\(toneC ? "ON" : "OFF")) "
                dump += "Noise(A:\(noiseA ? "ON" : "OFF"),B:\(noiseB ? "ON" : "OFF"),C:\(noiseC ? "ON" : "OFF"))"
                
            case 0x08, 0x09, 0x0A:
                let chIndex = subAddr - 0x08
                let ch = ["A", "B", "C"][chIndex]
                let volume = opnaRegisters[i] & 0x0F
                let useEnvelope = (opnaRegisters[i] & 0x10) != 0
                dump += String(format: " - CH%@ Volume: %d, Envelope: %@", ch, volume, useEnvelope ? "ON" : "OFF")
                
            default:
                dump += " - Other"
            }
            
            dump += "\n"
        }
        
        return dump
    }
    
    // FMレジスタダンプ
    func dumpFMRegisters() -> String {
        var dump = "FM Registers:\n"
        
        // 表FM音源の各チャンネル
        for ch in 0..<3 {
            dump += "Main FM Channel \(ch):\n"
            
            // 周波数情報
            let fNumberLSB = opnaRegisters[0xA0 + ch]
            let fNumberMSB = opnaRegisters[0xA4 + ch] & 0x07
            let block = (opnaRegisters[0xA4 + ch] >> 3) & 0x07
            let fNumber = (Int(fNumberMSB) << 8) | Int(fNumberLSB)
            let noteName = calculateFMNote(fNumber: fNumber, block: Int(block))
            
            dump += String(format: "  Frequency: F-Number=%d, Block=%d, Note=%@\n", fNumber, block, noteName)
            
            // アルゴリズムとフィードバック
            let algorithm = opnaRegisters[0xB0 + ch] & 0x07
            let feedback = (opnaRegisters[0xB0 + ch] >> 3) & 0x07
            
            dump += String(format: "  Algorithm=%d, Feedback=%d\n", algorithm, feedback)
            
            // 出力設定
            let leftOutput = (opnaRegisters[0xB4 + ch] & 0x80) != 0
            let rightOutput = (opnaRegisters[0xB4 + ch] & 0x40) != 0
            let ams = (opnaRegisters[0xB4 + ch] >> 4) & 0x03
            let pms = opnaRegisters[0xB4 + ch] & 0x07
            
            dump += String(format: "  Output: Left=%@, Right=%@, AMS=%d, PMS=%d\n", leftOutput ? "ON" : "OFF", rightOutput ? "ON" : "OFF", ams, pms)
            
            // 各スロットの情報
            for slot in 0..<4 {
                dump += "  Slot \(slot):\n"
                
                // デチューン/マルチプル
                let detuneMultiple = opnaRegisters[0x30 + (ch * 4) + slot]
                let detune = (detuneMultiple >> 4) & 0x07
                let multiple = detuneMultiple & 0x0F
                
                dump += String(format: "    Detune=%d, Multiple=%d\n", detune, multiple)
                
                // トータルレベル
                let totalLevel = opnaRegisters[0x40 + (ch * 4) + slot] & 0x7F
                
                dump += String(format: "    Total Level=%d\n", totalLevel)
                
                // キーレベルスケーリング/アタックレート
                let ksAr = opnaRegisters[0x50 + (ch * 4) + slot]
                let keyScaling = (ksAr >> 6) & 0x03
                let attackRate = ksAr & 0x1F
                
                dump += String(format: "    Key Scaling=%d, Attack Rate=%d\n", keyScaling, attackRate)
                
                // 第1ディケイレート
                let decay1Rate = opnaRegisters[0x60 + (ch * 4) + slot] & 0x1F
                
                dump += String(format: "    Decay1 Rate=%d\n", decay1Rate)
                
                // 第2ディケイレート
                let decay2Rate = opnaRegisters[0x70 + (ch * 4) + slot] & 0x1F
                
                dump += String(format: "    Decay2 Rate=%d\n", decay2Rate)
                
                // レートスケーリング/リリースレート
                let rsRr = opnaRegisters[0x80 + (ch * 4) + slot]
                let rateScaling = (rsRr >> 6) & 0x03
                let releaseRate = rsRr & 0x0F
                
                dump += String(format: "    Rate Scaling=%d, Release Rate=%d\n", rateScaling, releaseRate)
                
                // SSG-EG
                let ssgEg = opnaRegisters[0x90 + (ch * 4) + slot] & 0x0F
                
                dump += String(format: "    SSG-EG=%d\n", ssgEg)
            }
            
            dump += "\n"
        }
        
        // キーオン状態
        dump += "Key On Status:\n"
        for ch in 0..<6 {
            let isExtended = ch >= 3
            let chValue = ch % 3
            let keyOnValue = opnaRegisters[0x28]
            let isKeyOn = (keyOnValue & (1 << (chValue + (isExtended ? 4 : 0)))) != 0
            
            dump += String(format: "  Channel %d: %@\n", ch, isKeyOn ? "ON" : "OFF")
        }
        
        return dump
    }
    
    // PMD88ワークエリア解析
    func printPMD88WorkingAreaStatus() -> String {
        var status = "PMD88 Working Area Status:\n"
        
        // PMD88ワークエリアのベースアドレス（仮の値、実際のアドレスに置き換える）
        let pmdWorkArea = 0xC200
        
        // 各チャンネルの状態を表示
        for ch in 0..<3 {
            // SSGチャンネル
            let ssgBaseAddr = pmdWorkArea + (ch * 0x20)
            
            if ssgBaseAddr < memory.count - 0x20 {
                let toneAddr = ssgBaseAddr + 0x10
                let volumeAddr = ssgBaseAddr + 0x18
                
                let toneValue = readMemory16(at: toneAddr)
                let volume = memory[volumeAddr]
                
                let noteName = estimateSSGNoteSSG(toneValue: toneValue)
                
                status += String(format: "SSG Channel %d: Tone=%d (%@), Volume=%d\n", ch, toneValue, noteName, volume)
            }
        }
        
        // FMチャンネルの状態
        for ch in 0..<6 {
            let fmBaseAddr = pmdWorkArea + 0x100 + (ch * 0x20)
            
            if fmBaseAddr < memory.count - 0x20 {
                let fNumAddr = fmBaseAddr + 0x10
                let volumeAddr = fmBaseAddr + 0x18
                
                let fNumber = readMemory16(at: fNumAddr)
                let volume = memory[volumeAddr]
                
                // ブロック値はワークエリアの別の場所に格納されている可能性がある
                let blockAddr = fmBaseAddr + 0x12  // 仮の値
                let block = memory[blockAddr] & 0x07
                
                let noteName = calculateFMNote(fNumber: fNumber, block: Int(block))
                
                status += String(format: "FM Channel %d: F-Number=%d, Block=%d, Note=%@, Volume=%d\n", ch, fNumber, block, noteName, volume)
            }
        }
        
        // リズム音源の状態
        let rhythmAddr = pmdWorkArea + 0x200
        if rhythmAddr < memory.count - 0x10 {
            let rhythmOn = memory[rhythmAddr]
            let bdVolume = memory[rhythmAddr + 1]
            let sdVolume = memory[rhythmAddr + 2]
            let cyVolume = memory[rhythmAddr + 3]
            let hhVolume = memory[rhythmAddr + 4]
            let tomVolume = memory[rhythmAddr + 5]
            let rimVolume = memory[rhythmAddr + 6]
            
            status += "Rhythm Status:\n"
            status += String(format: "  Rhythm On: 0x%02X\n", rhythmOn)
            status += String(format: "  Bass Drum Volume: %d\n", bdVolume)
            status += String(format: "  Snare Drum Volume: %d\n", sdVolume)
            status += String(format: "  Cymbal Volume: %d\n", cyVolume)
            status += String(format: "  Hi-Hat Volume: %d\n", hhVolume)
            status += String(format: "  Tom Volume: %d\n", tomVolume)
            status += String(format: "  Rim Shot Volume: %d\n", rimVolume)
        }
        
        return status
    }
    
    // メモリとロードされたファイルの比較
    func verifyMemoryWithFile(data: Data, offset: Int) -> (isMatch: Bool, mismatchCount: Int, details: String) {
        var details = ""
        var mismatchCount = 0
        
        for (i, byte) in data.enumerated() {
            let address = offset + i
            
            if address < memory.count {
                if memory[address] != byte {
                    if mismatchCount < 10 {  // 最初の10個のミスマッチだけ詳細を表示
                        details += String(format: "Mismatch at 0x%04X: Memory=0x%02X, File=0x%02X\n", address, memory[address], byte)
                    }
                    mismatchCount += 1
                }
            } else {
                details += "Error: Memory address out of range at offset \(i)\n"
                mismatchCount += 1
            }
        }
        
        let isMatch = mismatchCount == 0
        
        if isMatch {
            details = "Memory contents match file data perfectly.\n"
        } else {
            details = "Found \(mismatchCount) mismatches between memory and file.\n" + details
        }
        
        return (isMatch, mismatchCount, details)
    }
    
    // 実行トレース
    func enableTracing() {
        debugMode = true
        addDebugLog("トレース開始")
    }
    
    func disableTracing() {
        debugMode = false
        addDebugLog("トレース終了")
    }
    
    // 命令の逆アセンブル
    func disassemble(at address: Int, count: Int = 10) -> String {
        var result = ""
        var currentAddress = address
        
        for _ in 0..<count {
            if currentAddress >= memory.count {
                break
            }
            
            let opcode = memory[currentAddress]
            var instruction = ""
            var length = 1
            
            switch opcode {
            case 0x00:
                instruction = "NOP"
            case 0x01:
                if currentAddress + 2 < memory.count {
                    let lowByte = memory[currentAddress + 1]
                    let highByte = memory[currentAddress + 2]
                    instruction = String(format: "LD BC, 0x%04X", (Int(highByte) << 8) | Int(lowByte))
                    length = 3
                }
            case 0x3E:
                if currentAddress + 1 < memory.count {
                    instruction = String(format: "LD A, 0x%02X", memory[currentAddress + 1])
                    length = 2
                }
            case 0xC3:
                if currentAddress + 2 < memory.count {
                    let lowByte = memory[currentAddress + 1]
                    let highByte = memory[currentAddress + 2]
                    instruction = String(format: "JP 0x%04X", (Int(highByte) << 8) | Int(lowByte))
                    length = 3
                }
            case 0xCD:
                if currentAddress + 2 < memory.count {
                    let lowByte = memory[currentAddress + 1]
                    let highByte = memory[currentAddress + 2]
                    instruction = String(format: "CALL 0x%04X", (Int(highByte) << 8) | Int(lowByte))
                    length = 3
                }
            case 0xC9:
                instruction = "RET"
            case 0xD3:
                if currentAddress + 1 < memory.count {
                    instruction = String(format: "OUT (0x%02X), A", memory[currentAddress + 1])
                    length = 2
                }
            case 0xDB:
                if currentAddress + 1 < memory.count {
                    instruction = String(format: "IN A, (0x%02X)", memory[currentAddress + 1])
                    length = 2
                }
            default:
                instruction = String(format: "DB 0x%02X", opcode)
            }
            
            result += String(format: "0x%04X: %@\n", currentAddress, instruction)
            currentAddress += length
        }
        
        return result
    }
}
