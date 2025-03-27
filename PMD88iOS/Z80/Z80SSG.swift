import Foundation

// Z80 SSG (Sound Source Generator) register handling extension
extension Z80 {
    // SSG（PSG互換部分）のレジスタ処理
    func handleSSGRegister(isMainChip: Bool, subAddr: UInt8, value: UInt8) {
        let chipPrefix = isMainChip ? "表FM" : "裏FM"
        let regOffset = isMainChip ? 0 : 0x100 // レジスタオフセット
        
        // プログラムカウンタの値を取得（デバッグ用）
        let sourcePC = String(format: "0x%04X", pc)
        
        // 前の値を取得
        let prevValue = opnaRegisters[Int(regOffset) + Int(subAddr)]
        
        // 新しい値を設定
        opnaRegisters[Int(regOffset) + Int(subAddr)] = value
        
        // SSGレジスタの種類に応じた処理
        switch subAddr {
        case 0x00, 0x02, 0x04:  // チャンネルA,B,C周波数LSB
            let chIndex = Int(subAddr) / 2
            let ch = ["A", "B", "C"][chIndex]
            let lsbValue = value
            
            // 対応するMSBレジスタを取得
            let msbAddr = subAddr + 1
            let msbValue = opnaRegisters[Int(regOffset) + Int(msbAddr)]
            
            // 完全なトーン値を計算
            let toneValue = (Int(msbValue) << 8) | Int(lsbValue)
            
            // 音名を推定
            let noteName = estimateSSGNoteSSG(toneValue: toneValue)
            
            // PMD88ワークエリアから情報を取得
            var pmdInfo = ""
            if let pmdToneAddr = getPMD88ToneAddress(channel: chIndex) {
                let pmdTone = readMemory16(at: pmdToneAddr)
                pmdInfo = ", PMD88トーン値=\(pmdTone)"
            }
            
            // 前の値との差分を計算
            let prevLSB = prevValue
            let prevMSB = opnaRegisters[Int(regOffset) + Int(msbAddr)]
            let prevTone = (Int(prevMSB) << 8) | Int(prevLSB)
            let toneDiff = toneValue - prevTone
            let diffInfo = toneDiff != 0 ? ", 差分=\(toneDiff > 0 ? "+" : "")\(toneDiff)" : ""
            
            addDebugLog("🎵 \(chipPrefix) SSGチャンネル\(ch)周波数LSB[\(String(format: "%02X", subAddr))]: PC=\(sourcePC) - \(String(format: "0x%02X", value)) [前: \(String(format: "0x%02X", prevValue))], トーン値=\(toneValue) (\(noteName))\(diffInfo)\(pmdInfo)")
            
        case 0x01, 0x03, 0x05:  // チャンネルA,B,C周波数MSB
            let chIndex = Int(subAddr - 1) / 2
            let ch = ["A", "B", "C"][chIndex]
            let msbValue = value
            
            // 対応するLSBレジスタを取得
            let lsbAddr = subAddr - 1
            let lsbValue = opnaRegisters[Int(regOffset) + Int(lsbAddr)]
            
            // 完全なトーン値を計算
            let toneValue = (Int(msbValue) << 8) | Int(lsbValue)
            
            // 音名を推定
            let noteName = estimateSSGNoteSSG(toneValue: toneValue)
            
            // PMD88ワークエリアから情報を取得
            var pmdInfo = ""
            if let pmdToneAddr = getPMD88ToneAddress(channel: chIndex) {
                let pmdTone = readMemory16(at: pmdToneAddr)
                pmdInfo = ", PMD88トーン値=\(pmdTone)"
            }
            
            // 前の値との差分を計算
            let prevMSB = prevValue
            let prevLSB = opnaRegisters[Int(regOffset) + Int(lsbAddr)]
            let prevTone = (Int(prevMSB) << 8) | Int(prevLSB)
            let toneDiff = toneValue - prevTone
            let diffInfo = toneDiff != 0 ? ", 差分=\(toneDiff > 0 ? "+" : "")\(toneDiff)" : ""
            
            addDebugLog("🎵 \(chipPrefix) SSGチャンネル\(ch)周波数MSB[\(String(format: "%02X", subAddr))]: PC=\(sourcePC) - \(String(format: "0x%02X", value)) [前: \(String(format: "0x%02X", prevValue))], トーン値=\(toneValue) (\(noteName))\(diffInfo)\(pmdInfo)")
            
        case 0x06:  // ノイズ周期
            let noisePeriod = value & 0x1F
            
            // 前の値との差分を計算
            let prevNoise = prevValue & 0x1F
            let noiseDiff = Int(noisePeriod) - Int(prevNoise)
            let diffInfo = noiseDiff != 0 ? ", 差分=\(noiseDiff > 0 ? "+" : "")\(noiseDiff)" : ""
            
            addDebugLog("🎵 \(chipPrefix) SSGノイズ周期[\(String(format: "%02X", subAddr))]: PC=\(sourcePC) - \(String(format: "0x%02X", value)) [前: \(String(format: "0x%02X", prevValue))], 周期=\(noisePeriod)\(diffInfo)")
            
        case 0x07:  // ミキサー設定
            let toneA = (value & 0x01) == 0
            let toneB = (value & 0x02) == 0
            let toneC = (value & 0x04) == 0
            let noiseA = (value & 0x08) == 0
            let noiseB = (value & 0x10) == 0
            let noiseC = (value & 0x20) == 0
            
            // 前の値と比較して変更を検出
            let prevToneA = (prevValue & 0x01) == 0
            let prevToneB = (prevValue & 0x02) == 0
            let prevToneC = (prevValue & 0x04) == 0
            let prevNoiseA = (prevValue & 0x08) == 0
            let prevNoiseB = (prevValue & 0x10) == 0
            let prevNoiseC = (prevValue & 0x20) == 0
            
            // 変更された設定を強調表示
            let toneAStr = toneA != prevToneA ? (toneA ? "【トーンA:ON】" : "【トーンA:OFF】") : (toneA ? "トーンA:ON" : "トーンA:OFF")
            let toneBStr = toneB != prevToneB ? (toneB ? "【トーンB:ON】" : "【トーンB:OFF】") : (toneB ? "トーンB:ON" : "トーンB:OFF")
            let toneCStr = toneC != prevToneC ? (toneC ? "【トーンC:ON】" : "【トーンC:OFF】") : (toneC ? "トーンC:ON" : "トーンC:OFF")
            let noiseAStr = noiseA != prevNoiseA ? (noiseA ? "【ノイズA:ON】" : "【ノイズA:OFF】") : (noiseA ? "ノイズA:ON" : "ノイズA:OFF")
            let noiseBStr = noiseB != prevNoiseB ? (noiseB ? "【ノイズB:ON】" : "【ノイズB:OFF】") : (noiseB ? "ノイズB:ON" : "ノイズB:OFF")
            let noiseCStr = noiseC != prevNoiseC ? (noiseC ? "【ノイズC:ON】" : "【ノイズC:OFF】") : (noiseC ? "ノイズC:ON" : "ノイズC:OFF")
            
            addDebugLog("🎵 \(chipPrefix) SSGミキサー設定[\(String(format: "%02X", subAddr))]: PC=\(sourcePC) - \(String(format: "0x%02X", value)) [前: \(String(format: "0x%02X", prevValue))]")
            addDebugLog("   トーン: \(toneAStr), \(toneBStr), \(toneCStr)")
            addDebugLog("   ノイズ: \(noiseAStr), \(noiseBStr), \(noiseCStr)")
            
        case 0x08, 0x09, 0x0A:  // チャンネルA,B,C音量
            let chIndex = Int(subAddr - 0x08)
            let ch = ["A", "B", "C"][chIndex]
            let volume = value & 0x0F
            let useEnvelope = (value & 0x10) != 0
            
            // 前の値と比較
            let prevVolume = prevValue & 0x0F
            let prevUseEnvelope = (prevValue & 0x10) != 0
            
            // 変更の強調表示
            let volumeChanged = volume != prevVolume
            let envelopeChanged = useEnvelope != prevUseEnvelope
            
            // PMD88ワークエリアから情報を取得
            var pmdInfo = ""
            if let pmdVolAddr = getPMD88VolumeAddress(channel: chIndex) {
                let pmdVol = memory[pmdVolAddr]
                pmdInfo = ", PMD88音量=\(pmdVol)"
            }
            
            // 変更情報
            let volumeInfo = volumeChanged ? ", 音量変化: \(prevVolume) → \(volume)" : ""
            let envelopeInfo = envelopeChanged ? ", エンベロープ: \(prevUseEnvelope ? "使用" : "未使用") → \(useEnvelope ? "使用" : "未使用")" : ""
            
            addDebugLog("🎵 \(chipPrefix) SSGチャンネル\(ch)音量[\(String(format: "%02X", subAddr))]: PC=\(sourcePC) - \(String(format: "0x%02X", value)) [前: \(String(format: "0x%02X", prevValue))], 音量=\(volume), エンベロープ=\(useEnvelope ? "使用" : "未使用")\(volumeInfo)\(envelopeInfo)\(pmdInfo)")
            
        case 0x0B, 0x0C:  // エンベロープ周期
            let regName = subAddr == 0x0B ? "エンベロープ周期LSB" : "エンベロープ周期MSB"
            
            // エンベロープ周期の完全な値を計算
            let lsbValue = opnaRegisters[Int(regOffset) + 0x0B]
            let msbValue = opnaRegisters[Int(regOffset) + 0x0C]
            let envPeriod = (Int(msbValue) << 8) | Int(lsbValue)
            
            addDebugLog("🎵 \(chipPrefix) SSG\(regName)[\(String(format: "%02X", subAddr))]: PC=\(sourcePC) - \(String(format: "0x%02X", value)) [前: \(String(format: "0x%02X", prevValue))], 周期=\(envPeriod)")
            
        case 0x0D:  // エンベロープシェイプ
            let shapeName: String
            switch value & 0x0F {
            case 0x00, 0x04, 0x08, 0x0C: shapeName = "\\___"
            case 0x01, 0x05, 0x09, 0x0D: shapeName = "/__/"
            case 0x02, 0x06, 0x0A, 0x0E: shapeName = "\\\\\\\\"
            case 0x03, 0x07, 0x0B, 0x0F: shapeName = "////"
            default: shapeName = "???"
            }
            
            addDebugLog("🎵 \(chipPrefix) SSGエンベロープシェイプ[\(String(format: "%02X", subAddr))]: PC=\(sourcePC) - \(String(format: "0x%02X", value)) [前: \(String(format: "0x%02X", prevValue))], シェイプ=\(shapeName)")
            
        case 0x0E, 0x0F:  // I/Oポート
            let regName = subAddr == 0x0E ? "I/OポートA" : "I/OポートB"
            addDebugLog("🎵 \(chipPrefix) SSG\(regName)[\(String(format: "%02X", subAddr))]: PC=\(sourcePC) - \(String(format: "0x%02X", value)) [前: \(String(format: "0x%02X", prevValue))]")
            
        default:
            // その他のレジスタは単純に値を表示
            addDebugLog("🎵 SSGレジスタ[\(String(format: "%02X", subAddr))]: PC=\(sourcePC) - \(String(format: "0x%02X", value)) [前: \(String(format: "0x%02X", prevValue))]")
            
            // オーディオエンジン更新フラグをセット
            needsOPNAUpdate = true
        }
    }
    
    // SSG音名推定
    func estimateSSGNoteSSG(toneValue: Int) -> String {
        if toneValue == 0 {
            return "---"
        }
        
        // SSGの周波数は以下の式で計算される
        // f = 1.79MHz / (32 * toneValue)
        // 音名は周波数から計算
        
        // 各音名の基準トーン値（近似値）
        // C4（ミドルC）を基準にしている
        let baseToneValues = [
            3822, 3608, 3405, 3214, 3034, 2863, 2703, 2551, 2408, 2273, 2145, 2025, // C3-B3
            1911, 1804, 1703, 1607, 1517, 1432, 1351, 1276, 1204, 1136, 1073, 1012, // C4-B4
            956, 902, 851, 804, 758, 716, 676, 638, 602, 568, 536, 506,            // C5-B5
            478, 451, 426, 402, 379, 358, 338, 319, 301, 284, 268, 253             // C6-B6
        ]
        
        // オクターブと音名の配列
        let octaveNotes = [
            "C3", "C#3", "D3", "D#3", "E3", "F3", "F#3", "G3", "G#3", "A3", "A#3", "B3",
            "C4", "C#4", "D4", "D#4", "E4", "F4", "F#4", "G4", "G#4", "A4", "A#4", "B4",
            "C5", "C#5", "D5", "D#5", "E5", "F5", "F#5", "G5", "G#5", "A5", "A#5", "B5",
            "C6", "C#6", "D6", "D#6", "E6", "F6", "F#6", "G6", "G#6", "A6", "A#6", "B6"
        ]
        
        // 最も近い音名を見つける
        var closestIndex = 0
        var minDiff = Int.max
        
        for (i, baseToneValue) in baseToneValues.enumerated() {
            let diff = abs(toneValue - baseToneValue)
            if diff < minDiff {
                minDiff = diff
                closestIndex = i
            }
        }
        
        // 音名とオクターブを返す
        return octaveNotes[closestIndex]
    }
    
    // PMD88ワークエリアからトーン値のアドレスを取得
    private func getPMD88ToneAddress(channel: Int) -> Int? {
        // PMD88ワークエリアのベースアドレス（仮の値、実際のアドレスに置き換える）
        let pmdWorkArea = 0xC200
        
        // 各チャンネルのトーン値オフセット（仮の値、実際のオフセットに置き換える）
        let toneOffsets = [0x10, 0x30, 0x50]
        
        if channel >= 0 && channel < toneOffsets.count {
            return pmdWorkArea + toneOffsets[channel]
        }
        
        return nil
    }
    
    // PMD88ワークエリアから音量値のアドレスを取得
    private func getPMD88VolumeAddress(channel: Int) -> Int? {
        // PMD88ワークエリアのベースアドレス（仮の値、実際のアドレスに置き換える）
        let pmdWorkArea = 0xC200
        
        // 各チャンネルの音量値オフセット（仮の値、実際のオフセットに置き換える）
        let volumeOffsets = [0x18, 0x38, 0x58]
        
        if channel >= 0 && channel < volumeOffsets.count {
            return pmdWorkArea + volumeOffsets[channel]
        }
        
        return nil
    }
}
