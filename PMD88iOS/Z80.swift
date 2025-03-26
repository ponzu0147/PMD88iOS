import Foundation

// Z80 CPU エミュレータのメインクラス
// 各機能は分割されたファイルに実装されています

// Z80 CPUクラス
public class Z80 {
    // Z80 CPU レジスタ
    var a: UInt8 = 0
    var f: UInt8 = 0
    var b: UInt8 = 0
    var c: UInt8 = 0
    var d: UInt8 = 0
    var e: UInt8 = 0
    var h: UInt8 = 0
    var l: UInt8 = 0
    
    var af_: UInt16 = 0
    var bc_: UInt16 = 0
    var de_: UInt16 = 0
    var hl_: UInt16 = 0
    
    // IXとIYレジスタ
    var ix_h: UInt8 = 0
    var ix_l: UInt8 = 0
    var iy_h: UInt8 = 0
    var iy_l: UInt8 = 0
    
    var i: UInt8 = 0
    var r: UInt8 = 0
    
    var pc: Int = 0
    var sp: Int = 0
    
    // フラグ定数
    let S_FLAG: UInt8 = 0x80  // サインフラグ
    let Z_FLAG: UInt8 = 0x40  // ゼロフラグ
    let H_FLAG: UInt8 = 0x10  // ハーフキャリーフラグ
    let P_FLAG: UInt8 = 0x04  // パリティ/オーバーフローフラグ
    let N_FLAG: UInt8 = 0x02  // 減算フラグ
    let C_FLAG: UInt8 = 0x01  // キャリーフラグ
    
    // メモリとI/O
    var memory: [UInt8]
    var ioPorts: [UInt8] = Array(repeating: 0, count: 256)
    var ports: [UInt8: UInt8] = [:]
    var portMap: [UInt8: UInt8] = [:]
    var portWriteOrder: [(port: UInt8, value: UInt8)] = []
    var outPortCounter: Int = 0
    var inPortCounter: Int = 0
    
    // FM音源関連
    var sel44Address: Int = -1
    var sel46Address: Int = -1
    var ports44_45: [UInt8: UInt8] = [:]
    var ports46_47: [UInt8: UInt8] = [:]
    var currentPortBase: UInt8 = 0
    var needsOPNAUpdate: Bool = false
    var currentRegAddr: [UInt8: UInt8] = [:]
    
    // opnset46ルーチン検出用
    
    // Z80Coreインスタンス
    public var core: Z80Core!
    var inOpnset46: Bool = false
    var opnset46State: Int = 0
    
    // ビジーフラグシミュレーション
    var port44Busy: Bool = false
    var port44BusyCounter: Int = 0
    var port46Busy: Bool = false
    var port46BusyCounter: Int = 0
    
    // OPNA (YM2608) レジスタ
    var opnaRegisters: [UInt8] = Array(repeating: 0, count: 512) // 表FM音源と裏FM音源用
    var opnaRegisterAddr: UInt8 = 0
    var opnaExtRegisterAddr: UInt8 = 0
    var regAddrPort44: UInt8 = 0
    var regAddrPort46: UInt8 = 0
    var addrWritten: [UInt8: Bool] = [0x44: false, 0x46: false]
    var selectedOPNARegister: UInt8 = 0 // 選択中のOPNAレジスタ
    
    // ポート入出力ハンドラ
    var portInHandler: ((UInt16) -> UInt8)? = nil
    var portOutHandler: ((UInt16, UInt8) -> Void)? = nil
    
    // デバッグ関連
    var debugLog: [String] = []
    var debugMode: Bool = false
    var breakPoint: Int = -1
    var isStopped: Bool = false
    var stepCount: Int = 0
    var startPC: Int = 0
    var lastPCs: [Int] = []
    
    // PMD88関連
    var pmd88HookAddresses: [Int] = []
    var fmKeyOnState: [Bool] = Array(repeating: false, count: 6)
    var ssgKeyOnState: [(Bool, Bool)] = Array(repeating: (false, false), count: 3)
    
    // 同期制御
    let lock = NSLock()
    
    // 初期化
    init(memorySize: Int = 0x10000) {
        memory = Array(repeating: 0, count: memorySize)
        
        // Z80Coreインスタンスの作成
        core = Z80Core(z80: self)
    }
    
    // レジスタペアのアクセサ
    func af() -> Int {
        return (Int(a) << 8) | Int(f)
    }
    
    func setAf(_ value: Int) {
        a = UInt8((value >> 8) & 0xFF)
        f = UInt8(value & 0xFF)
    }
    
    func bc() -> Int {
        return (Int(b) << 8) | Int(c)
    }
    
    func setBc(_ value: Int) {
        b = UInt8((value >> 8) & 0xFF)
        c = UInt8(value & 0xFF)
    }
    
    func de() -> Int {
        return (Int(d) << 8) | Int(e)
    }
    
    func setDe(_ value: Int) {
        d = UInt8((value >> 8) & 0xFF)
        e = UInt8(value & 0xFF)
    }
    
    func hl() -> Int {
        return (Int(h) << 8) | Int(l)
    }
    
    func setHl(_ value: Int) {
        h = UInt8((value >> 8) & 0xFF)
        l = UInt8(value & 0xFF)
    }
    
    func ix() -> Int {
        return (Int(ix_h) << 8) | Int(ix_l)
    }
    
    func setIx(_ value: Int) {
        ix_h = UInt8((value >> 8) & 0xFF)
        ix_l = UInt8(value & 0xFF)
    }
    
    func iy() -> Int {
        return (Int(iy_h) << 8) | Int(iy_l)
    }
    
    func setIy(_ value: Int) {
        iy_h = UInt8((value >> 8) & 0xFF)
        iy_l = UInt8(value & 0xFF)
    }
    
    // デバッグログの追加
    func addDebugLog(_ message: String) {
        if debugMode {
            debugLog.append(message)
            if debugLog.count > 1000 {
                debugLog.removeFirst(debugLog.count - 1000)
            }
        }
    }
    
    // リセット
    func reset() {
        a = 0
        f = 0
        b = 0
        c = 0
        d = 0
        e = 0
        h = 0
        l = 0
        
        af_ = 0
        bc_ = 0
        de_ = 0
        hl_ = 0
        
        ix_h = 0
        ix_l = 0
        iy_h = 0
        iy_l = 0
        
        i = 0
        r = 0
        
        pc = 0
        sp = 0xFFFF
        
        isStopped = false
        stepCount = 0
        lastPCs = []
        
        // OPNAレジスタのリセット
        opnaRegisters = Array(repeating: 0, count: 512)
        opnaRegisterAddr = 0
        opnaExtRegisterAddr = 0
        regAddrPort44 = 0
        regAddrPort46 = 0
        addrWritten = [0x44: false, 0x46: false]
        
        // I/Oポートのリセット
        ports = [:]
        portMap = [:]
        portWriteOrder = []
        outPortCounter = 0
        inPortCounter = 0
        
        // PMD88関連のリセット
        fmKeyOnState = Array(repeating: false, count: 6)
        ssgKeyOnState = Array(repeating: (false, false), count: 3)
        
        // Z80Coreの拡張リセット処理は別途実行される
        
        addDebugLog("Z80 CPU リセット")
    }
    
    // メモリロード
    func loadMemory(data: Data, offset: Int = 0) {
        for (i, byte) in data.enumerated() {
            let address = offset + i
            if address < memory.count {
                memory[address] = byte
            }
        }
        addDebugLog("メモリロード: \(data.count)バイト at \(String(format: "0x%04X", offset))")
    }
    
    // 実行
    func execute(steps: Int = 1) -> Int {
        for _ in 0..<steps {
            if isStopped {
                return -4  // CPU停止
            }
            
            // Z80Instructions.swiftに定義されているstep関数を実行
        lock.lock()
        defer { lock.unlock() }
        
        if pc == breakPoint {
                addDebugLog("ブレークポイント到達: \(String(format: "0x%04X", pc))")
                return -1  // ブレークポイントに達した
        }
        
        // ループ検出
            startPC = pc
            lastPCs.append(pc)
        if lastPCs.count > 100 {
            lastPCs.removeFirst()
            }
            
            // 無限ループ検出（同じPCが短時間に多数回出現）
            let pcCount = lastPCs.filter { $0 == pc }.count
            if pcCount > 50 {
                addDebugLog("無限ループ検出: PC=\(String(format: "0x%04X", pc)) が \(pcCount) 回繰り返されました")
                return -2  // 無限ループ
            }
            
            // メモリ範囲チェック
            if pc < 0 || pc >= memory.count {
                addDebugLog("メモリ範囲外アクセス: PC=\(String(format: "0x%04X", pc))")
                return -3  // メモリ範囲外
            }
            
            // 命令取得
            // 実際の命令実行は簡易化しているためオペコードは使用しない
            stepCount += 1
            
            // 命令実行（簡易実装）
            let pcIncrement = 1
            
            // ここに命令の実行処理を追加する
            // 実際の実装はZ80Instructions.swiftにある
            
            // PCを進める
            pc += pcIncrement
            
            // PMD88の状態を監視
            // Z80PMD.swiftに定義されているmonitorPMD88関数を実行
            // 簡易版を実装
            if pc == 0xAA5F || pc == 0xB9CA || pc == 0xB70E {
                addDebugLog("PMD88フックアドレス検出: \(String(format: "0x%04X", pc))")
            }
            
            // FMキーオン状態を監視
            // Z80PMD.swiftに定義されているmonitorFMKeyOn関数を実行
            let keyOnValue = opnaRegisters[0x28]
            if keyOnValue != 0 {
                let channel = keyOnValue & 0x07
                let slot = (keyOnValue >> 4) & 0x0F
                if channel < 6 && slot != 0 {
                    fmKeyOnState[Int(channel)] = true
                    addDebugLog("FMキーオン検出: チャンネル\(channel), スロット\(slot)")
                }
            }
            
            // SSGキーオン状態を監視
            // Z80PMD.swiftに定義されているmonitorSSGKeyOn関数を実行
            let mixerValue = opnaRegisters[0x07]
            for i in 0..<3 {
                let toneEnabled = (mixerValue & (1 << i)) == 0
                let noiseEnabled = (mixerValue & (1 << (i + 3))) == 0
                ssgKeyOnState[i] = (toneEnabled, noiseEnabled)
            }
        }
        
        return 0  // 正常終了
    }
    
    // FM音名計算
    func calculateFMNote(fNumber: Int, block: Int) -> String {
        // F-Number から音名を計算
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        
        // F-Number から音名のインデックスを計算（近似値）
        let fNumTable = [617, 653, 692, 733, 777, 823, 872, 924, 979, 1037, 1099, 1164]
        
        var closestIndex = 0
        var minDiff = Int.max
        
        for (i, refFNum) in fNumTable.enumerated() {
            let diff = abs(fNumber - refFNum)
            if diff < minDiff {
                minDiff = diff
                closestIndex = i
            }
        }
        
        let noteName = noteNames[closestIndex]
        return "\(noteName)\(block)"
    }
    
    // SSG音名計算
    func estimateSSGNote(toneValue: Int) -> String {
        if toneValue <= 0 {
            return "---"
        }
        
        // SSGのトーン値から音名を計算
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        
        // トーン値から周波数を計算（近似値）
        // 周波数 = 1789773 / (32 * トーン値)
        let frequency = Double(1789773) / (32.0 * Double(toneValue))
        
        // A4 (440Hz) を基準に半音ごとの周波数比は 2^(1/12)
        let a4Frequency = 440.0
        let semitoneRatio = pow(2.0, 1.0 / 12.0)
        
        // A4からの半音数を計算
        var semitonesFromA4 = log(frequency / a4Frequency) / log(semitoneRatio)
        semitonesFromA4 = round(semitonesFromA4)
        
        // 音名とオクターブを計算
        let noteIndex = (Int(semitonesFromA4) % 12 + 12) % 12
        let octave = Int(floor((semitonesFromA4 + 9.0) / 12.0)) + 4  // A4のオクターブは4
        
        let noteName = noteNames[(noteIndex + 9) % 12]  // A4を基準にしているので、インデックスを調整
        
        return "\(noteName)\(octave)"
    }
    
    // プログラムロード処理（Z80Coreへのブリッジ）
    public func loadProgram(at address: Int, data: Data) {
        core.loadProgram(at: address, data: data)
    }
    
    // ポートマッピング設定（Z80Coreへのブリッジ）
    public func setPortMapping(forBoard boardType: String) {
        core.setPortMapping(forBoard: boardType)
    }
} 
