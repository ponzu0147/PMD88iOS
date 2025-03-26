//
//  PC88Debug.swift
//  PMD88iOS
//
//  Created by 越川将人 on 2025/03/23.
//

import Foundation
import Combine

// MARK: - PC88デバッグ機能
class PC88Debug {
    // 親クラスへの参照
    private weak var pc88: PC88Core?
    
    // ログ関連
    private var logs: [String] = []
    private var lastLog: String = ""
    
    // PublisherとSubject
    private let logSubject = PassthroughSubject<String, Never>()
    private let logsSubject = CurrentValueSubject<[String], Never>([])
    
    // 公開するPublisher
    var logPublisher: AnyPublisher<String, Never> {
        return logSubject.eraseToAnyPublisher()
    }
    
    var logsPublisher: AnyPublisher<[String], Never> {
        return logsSubject.eraseToAnyPublisher()
    }
    
    // 初期化
    init(pc88: PC88Core) {
        self.pc88 = pc88
    }
    
    // ログの追加
    func appendLog(_ message: String) {
        let timestamp = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timeString = formatter.string(from: timestamp)
        
        let logMessage = "[\(timeString)] \(message)"
        
        // ログを追加
        logs.append(logMessage)
        
        // 最大100件までに制限
        if logs.count > 100 {
            logs.removeFirst(logs.count - 100)
        }
        
        // 最新のログを保存
        lastLog = logMessage
        
        // PublisherとSubjectを更新
        logSubject.send(logMessage)
        logsSubject.send(logs)
    }
    
    // 現在のログを取得
    func getLogs() -> [String] {
        return logs
    }
    
    // 最新のログを取得
    func getLastLog() -> String {
        return lastLog
    }
    
    // PMD88の曲データアドレスを取得
    func getPMDSongDataAddress() -> UInt16? {
        guard let pc88 = pc88 else { return nil }
        
        // 曲データアドレスを取得
        let songDataAddrL = pc88.cpu.memory[PMDWorkArea.songDataAddr]
        let songDataAddrH = pc88.cpu.memory[PMDWorkArea.songDataAddr + 1]
        let songDataAddr = UInt16(songDataAddrH) << 8 | UInt16(songDataAddrL)
        
        return songDataAddr
    }
    
    // PMD88ワークエリアの状態を出力
    func printPMD88WorkingAreaStatus() {
        guard let pc88 = pc88 else { return }
        
        appendLog("===== PMD88ワークエリア状態 =====")
        
        // 曲データアドレス
        let songDataAddrL = pc88.cpu.memory[PMDWorkArea.songDataAddr]
        let songDataAddrH = pc88.cpu.memory[PMDWorkArea.songDataAddr + 1]
        let songDataAddr = UInt16(songDataAddrH) << 8 | UInt16(songDataAddrL)
        appendLog("曲データアドレス: 0x\(String(format: "%04X", songDataAddr))")
        
        // 音色データアドレス
        let toneDataAddrL = pc88.cpu.memory[PMDWorkArea.toneDataAddr]
        let toneDataAddrH = pc88.cpu.memory[PMDWorkArea.toneDataAddr + 1]
        let toneDataAddr = UInt16(toneDataAddrH) << 8 | UInt16(toneDataAddrL)
        appendLog("音色データアドレス: 0x\(String(format: "%04X", toneDataAddr))")
        
        // FM音源チャンネル情報
        appendLog("--- FM音源チャンネル情報 ---")
        for ch in 0..<6 {
            let baseAddr = PMDWorkArea.fmChannelBase + (ch * PMDWorkArea.fmChannelSize)
            let addrL = pc88.cpu.memory[baseAddr]
            let addrH = pc88.cpu.memory[baseAddr + 1]
            let addr = UInt16(addrH) << 8 | UInt16(addrL)
            
            let volume = pc88.cpu.memory[baseAddr + 0x04]
            let panpot = pc88.cpu.memory[baseAddr + 0x05]
            let detune = Int8(bitPattern: pc88.cpu.memory[baseAddr + 0x06])
            
            appendLog("FM\(ch+1): アドレス=0x\(String(format: "%04X", addr)), 音量=\(volume), パン=\(panpot), デチューン=\(detune)")
        }
        
        // SSG音源チャンネル情報
        appendLog("--- SSG音源チャンネル情報 ---")
        for ch in 0..<3 {
            let baseAddr = PMDWorkArea.ssgChannelBase + (ch * PMDWorkArea.ssgChannelSize)
            let addrL = pc88.cpu.memory[baseAddr]
            let addrH = pc88.cpu.memory[baseAddr + 1]
            let addr = UInt16(addrH) << 8 | UInt16(addrL)
            
            let volume = pc88.cpu.memory[baseAddr + 0x04]
            
            appendLog("SSG\(ch+1): アドレス=0x\(String(format: "%04X", addr)), 音量=\(volume)")
        }
        
        // リズム音源の状態
        let rhythmStatus = pc88.cpu.memory[PMDWorkArea.rhythmStatusAddr]
        appendLog("リズム音源状態: 0x\(String(format: "%02X", rhythmStatus))")
        
        // OPNAレジスタの状態
        appendLog("--- OPNAレジスタ状態 ---")
        appendLog("キーオン状態(0x28): 0x\(String(format: "%02X", pc88.cpu.opnaRegisters[OPNARegister.keyOnOff]))")
        
        // SSG音量
        for ch in 0..<3 {
            let reg = OPNARegister.ssgVolumeBase + ch
            appendLog("SSG\(ch+1)音量(0x\(String(format: "%02X", reg))): 0x\(String(format: "%02X", pc88.cpu.opnaRegisters[reg]))")
        }
        
        // リズムキーオン状態
        appendLog("リズムキーオン(0x10): 0x\(String(format: "%02X", pc88.cpu.opnaRegisters[OPNARegister.rhythmKeyOnOff]))")
    }
    
    // Z80 CPUの状態を出力
    func printZ80Status() {
        guard let pc88 = pc88 else { return }
        
        let cpu = pc88.cpu
        appendLog("===== Z80 CPU状態 =====")
        appendLog("PC=0x\(String(format: "%04X", cpu.pc)), SP=0x\(String(format: "%04X", cpu.sp))")
        appendLog("A=0x\(String(format: "%02X", cpu.a)), F=0x\(String(format: "%02X", cpu.f))")
        appendLog("BC=0x\(String(format: "%04X", UInt16(cpu.b) << 8 | UInt16(cpu.c)))")
        appendLog("DE=0x\(String(format: "%04X", UInt16(cpu.d) << 8 | UInt16(cpu.e)))")
        appendLog("HL=0x\(String(format: "%04X", UInt16(cpu.h) << 8 | UInt16(cpu.l)))")
        appendLog("IX=0x\(String(format: "%04X", cpu.ix())), IY=0x\(String(format: "%04X", cpu.iy()))")
    }
    
    // メモリダンプを出力
    func printMemoryDump(startAddr: Int, length: Int) {
        guard let pc88 = pc88 else { return }
        
        let endAddr = min(startAddr + length, pc88.cpu.memory.count)
        appendLog("===== メモリダンプ 0x\(String(format: "%04X", startAddr))-0x\(String(format: "%04X", endAddr-1)) =====")
        
        var line = ""
        var ascii = ""
        var count = 0
        
        for addr in startAddr..<endAddr {
            if count % 16 == 0 {
                if count > 0 {
                    appendLog("\(line)  \(ascii)")
                }
                line = String(format: "%04X: ", addr)
                ascii = ""
            }
            
            let value = pc88.cpu.memory[addr]
            line += String(format: "%02X ", value)
            
            // ASCII表示用（表示可能な文字のみ）
            if value >= 0x20 && value <= 0x7E {
                ascii += String(UnicodeScalar(value))
            } else {
                ascii += "."
            }
            
            count += 1
        }
        
        // 最後の行を出力
        if !line.isEmpty {
            // 16バイト未満の場合、スペースで埋める
            let padding = 16 - (count % 16)
            if padding < 16 {
                for _ in 0..<padding {
                    line += "   "
                }
            }
            appendLog("\(line)  \(ascii)")
        }
    }
}
