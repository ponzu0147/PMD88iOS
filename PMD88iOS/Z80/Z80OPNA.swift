import Foundation

// Z80 OPNA register handling extension
extension Z80 {
    // OPNAレジスタ効果処理
    func handleOPNARegisterEffect(isMainChip: Bool, regAddr: Int, value: UInt8) {
        // チップの種類に応じたログ接頭辞
        let chipPrefix = isMainChip ? "表FM" : "裏FM"
        
        switch regAddr {
        case 0x00...0x0F:  // SSG（PSG互換部分）レジスタ
            handleSSGRegister(isMainChip: isMainChip, subAddr: UInt8(regAddr), value: value)
            
        case 0x10...0x1F:  // リズム音源・ADPCMレジスタ
            let regName: String
            switch regAddr {
            case 0x10: regName = "ADPCMデータ"
            case 0x11: regName = "リズムトータルレベル"
            case 0x12: regName = "リズムパンポット"
            case 0x13: regName = "リズムキーオン"
            case 0x14: regName = "リズムトータルレベル"
            case 0x15: regName = "リズムパンポット"
            case 0x16: regName = "リズムキーオン"
            case 0x17: regName = "リズムトータルレベル"
            case 0x18: regName = "リズムパンポット"
            case 0x19: regName = "リズムキーオン"
            case 0x1A: regName = "リズムトータルレベル"
            case 0x1B: regName = "リズムパンポット"
            case 0x1C: regName = "ADPCMリミットアドレス"
            case 0x1D: regName = "ADPCMフラグコントロール"
            default: regName = "未知のリズム/ADPCMレジスタ"
            }
            
            addDebugLog("🥁 \(chipPrefix) \(regName)[\(String(format: "%02X", regAddr))]: \(String(format: "0x%02X", value)) at PC=\(String(format: "0x%04X", pc))")
            
        case 0x24...0x27:  // タイマー関連
            let regName: String
            switch regAddr {
            case 0x24: regName = "タイマーA上位バイト"
            case 0x25: regName = "タイマーA下位バイト"
            case 0x26: regName = "タイマーB"
            case 0x27: regName = "タイマー制御"
                // タイマー制御の詳細
                let ch3Mode = (value >> 6) & 0x03
                let resetB = (value & 0x20) != 0
                let resetA = (value & 0x10) != 0
                let startB = (value & 0x08) != 0
                let startA = (value & 0x04) != 0
                let loadB = (value & 0x02) != 0
                let loadA = (value & 0x01) != 0
                
                addDebugLog("⏱️ \(chipPrefix) タイマー制御: CH3モード=\(ch3Mode), リセットB=\(resetB), リセットA=\(resetA), スタートB=\(startB), スタートA=\(startA), ロードB=\(loadB), ロードA=\(loadA) at PC=\(String(format: "0x%04X", pc))")
                return
            default: regName = "未知のタイマーレジスタ"
            }
            
            addDebugLog("⏱️ \(chipPrefix) \(regName)[\(String(format: "%02X", regAddr))]: \(String(format: "0x%02X", value)) at PC=\(String(format: "0x%04X", pc))")
            
        case 0x28:  // キーオン/オフ
            let channel = value & 0x07
            let isExtended = (value & 0x08) != 0
            let slot1 = ((value >> 4) & 0x01) != 0
            let slot2 = ((value >> 5) & 0x01) != 0
            let slot3 = ((value >> 6) & 0x01) != 0
            let slot4 = ((value >> 7) & 0x01) != 0
            
            let chName = isExtended ? "\(channel + 3)" : "\(channel)"
            let slotStatus = [slot1, slot2, slot3, slot4]
            let slotStr = slotStatus.map { $0 ? "ON" : "OFF" }.joined(separator: "/")
            
            addDebugLog("🎹 \(chipPrefix) キーオン/オフ: CH\(chName) スロット状態=\(slotStr) at PC=\(String(format: "0x%04X", pc))")
            
            // オーディオエンジン更新フラグをセット
            needsOPNAUpdate = true
            
        case 0x2A, 0x2B, 0x2C:  // DAC関連
            let regName: String
            switch regAddr {
            case 0x2A: regName = "DACデータ"
            case 0x2B: regName = "DAC有効化"
            case 0x2C: regName = "DACサンプリングレート"
            default: regName = "未知のDACレジスタ"
            }
            
            addDebugLog("🔊 \(chipPrefix) \(regName)[\(String(format: "%02X", regAddr))]: \(String(format: "0x%02X", value)) at PC=\(String(format: "0x%04X", pc))")
            
        case 0x30...0x3F:  // 各スロットのデチューン/マルチプル
            let slot = (regAddr - 0x30) % 4
            let channel = (regAddr - 0x30) / 4
            let detune = (value >> 4) & 0x07
            let multiple = value & 0x0F
            
            addDebugLog("🎹 \(chipPrefix) CH\(channel) スロット\(slot) デチューン=\(detune), マルチプル=\(multiple) at PC=\(String(format: "0x%04X", pc))")
            
        case 0x40...0x4F:  // 各スロットのトータルレベル
            let slot = (regAddr - 0x40) % 4
            let channel = (regAddr - 0x40) / 4
            let totalLevel = value & 0x7F
            
            addDebugLog("🎹 \(chipPrefix) CH\(channel) スロット\(slot) トータルレベル=\(totalLevel) at PC=\(String(format: "0x%04X", pc))")
            
        case 0x50...0x5F:  // 各スロットのアタックレート/キーレベルスケーリング
            let slot = (regAddr - 0x50) % 4
            let channel = (regAddr - 0x50) / 4
            let keyScaling = (value >> 6) & 0x03
            let attackRate = value & 0x1F
            
            addDebugLog("🎹 \(chipPrefix) CH\(channel) スロット\(slot) キースケーリング=\(keyScaling), アタックレート=\(attackRate) at PC=\(String(format: "0x%04X", pc))")
            
        case 0x60...0x6F:  // 各スロットの第1ディケイレート
            let slot = (regAddr - 0x60) % 4
            let channel = (regAddr - 0x60) / 4
            let decay1Rate = value & 0x1F
            
            addDebugLog("🎹 \(chipPrefix) CH\(channel) スロット\(slot) 第1ディケイレート=\(decay1Rate) at PC=\(String(format: "0x%04X", pc))")
            
        case 0x70...0x7F:  // 各スロットの第2ディケイレート
            let slot = (regAddr - 0x70) % 4
            let channel = (regAddr - 0x70) / 4
            let decay2Rate = value & 0x1F
            
            addDebugLog("🎹 \(chipPrefix) CH\(channel) スロット\(slot) 第2ディケイレート=\(decay2Rate) at PC=\(String(format: "0x%04X", pc))")
            
        case 0x80...0x8F:  // 各スロットのリリースレート/レートスケーリング
            let slot = (regAddr - 0x80) % 4
            let channel = (regAddr - 0x80) / 4
            let rateScaling = (value >> 6) & 0x03
            let releaseRate = value & 0x0F
            
            addDebugLog("🎹 \(chipPrefix) CH\(channel) スロット\(slot) レートスケーリング=\(rateScaling), リリースレート=\(releaseRate) at PC=\(String(format: "0x%04X", pc))")
            
        case 0x90...0x9F:  // 各スロットのSSG-EG
            let slot = (regAddr - 0x90) % 4
            let channel = (regAddr - 0x90) / 4
            let ssgEg = value & 0x0F
            
            addDebugLog("🎹 \(chipPrefix) CH\(channel) スロット\(slot) SSG-EG=\(ssgEg) at PC=\(String(format: "0x%04X", pc))")
            
        case 0xA0...0xA2:  // チャンネル周波数LSB
            let channel = regAddr - 0xA0
            let freqLSB = value
            
            addDebugLog("🎹 \(chipPrefix) CH\(channel) 周波数LSB=\(freqLSB) at PC=\(String(format: "0x%04X", pc))")
            
        case 0xA4...0xA6:  // チャンネル周波数MSB/ブロック
            let channel = regAddr - 0xA4
            let block = (value >> 3) & 0x07
            let freqMSB = value & 0x07
            
            addDebugLog("🎹 \(chipPrefix) CH\(channel) ブロック=\(block), 周波数MSB=\(freqMSB) at PC=\(String(format: "0x%04X", pc))")
            
            // 音名を計算
            let fNumber = (Int(freqMSB) << 8) | Int(opnaRegisters[Int(0xA0 + channel) + (isMainChip ? 0 : 0x100)])
            let noteName = calculateFMNoteOPNA(fNumber: fNumber, block: Int(block))
            addDebugLog("🎵 \(chipPrefix) CH\(channel) 音名=\(noteName) (F-Number=\(fNumber), Block=\(block))")
            
        case 0xA8...0xAA:  // チャンネル3追加周波数LSB
            let subChannel = regAddr - 0xA8
            let freqLSB = value
            
            addDebugLog("🎹 \(chipPrefix) CH3-\(subChannel) 追加周波数LSB=\(freqLSB) at PC=\(String(format: "0x%04X", pc))")
            
        case 0xAC...0xAE:  // チャンネル3追加周波数MSB/ブロック
            let subChannel = regAddr - 0xAC
            let block = (value >> 3) & 0x07
            let freqMSB = value & 0x07
            
            addDebugLog("🎹 \(chipPrefix) CH3-\(subChannel) 追加ブロック=\(block), 追加周波数MSB=\(freqMSB) at PC=\(String(format: "0x%04X", pc))")
            
        case 0xB0...0xB2:  // チャンネルアルゴリズム/フィードバック
            let channel = regAddr - 0xB0
            let algorithm = value & 0x07
            let feedback = (value >> 3) & 0x07
            
            addDebugLog("🎹 \(chipPrefix) CH\(channel) アルゴリズム=\(algorithm), フィードバック=\(feedback) at PC=\(String(format: "0x%04X", pc))")
            
        case 0xB4...0xB6:  // チャンネル出力/パン
            let channel = regAddr - 0xB4
            let leftOutput = (value & 0x80) != 0
            let rightOutput = (value & 0x40) != 0
            let ams = (value >> 4) & 0x03
            let pms = value & 0x07
            
            let panStr = "\(leftOutput ? "L" : "-")\(rightOutput ? "R" : "-")"
            
            addDebugLog("🎹 \(chipPrefix) CH\(channel) 出力=\(panStr), AMS=\(ams), PMS=\(pms) at PC=\(String(format: "0x%04X", pc))")
            
        default:
            // その他の未知のレジスタ
            addDebugLog("❓ \(chipPrefix) 未知のレジスタ[\(String(format: "%02X", regAddr))]: \(String(format: "0x%02X", value)) at PC=\(String(format: "0x%04X", pc))")
        }
    }
    
    // FM音源の音名計算
    func calculateFMNoteOPNA(fNumber: Int, block: Int) -> String {
        // F-Numberから音名を計算
        // F-Numberは0〜2047の範囲で、1オクターブを2^(1/12)の12等分
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        
        // F-Numberの基準値（各音名の中央値）
        let baseFNumbers = [
            617, 654, 693, 734, 778, 824, 873, 925, 980, 1038, 1100, 1165
        ]
        
        // 最も近い音名を見つける
        var closestNote = 0
        var minDiff = Int.max
        
        for (i, baseFNumber) in baseFNumbers.enumerated() {
            let diff = abs(fNumber - baseFNumber)
            if diff < minDiff {
                minDiff = diff
                closestNote = i
            }
        }
        
        // 音名とオクターブを組み合わせて返す
        return "\(noteNames[closestNote])\(block)"
    }
}
