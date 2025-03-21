import Foundation

class Z80 {
    // フラグ定数
    private let S_FLAG: UInt8 = 0x80 // サインフラグ
    private let Z_FLAG: UInt8 = 0x40 // ゼロフラグ
    private let H_FLAG: UInt8 = 0x10 // ハーフキャリーフラグ
    private let P_FLAG: UInt8 = 0x04 // パリティ/オーバーフローフラグ
    private let N_FLAG: UInt8 = 0x02 // 減算フラグ
    private let C_FLAG: UInt8 = 0x01 // キャリーフラグ
    
    // スレッド安全性のためのロック
    private let lock = NSLock()
    
    // CPU レジスタ
    var pc: Int = 0           // プログラムカウンタ
    var sp: Int = 0xF000      // スタックポインタ
    var a: UInt8 = 0          // アキュムレータ
    var f: UInt8 = 0          // フラグレジスタ
    var b: UInt8 = 0          // B レジスタ
    var c: UInt8 = 0          // C レジスタ
    var d: UInt8 = 0          // D レジスタ
    var e: UInt8 = 0          // E レジスタ
    var h: UInt8 = 0          // H レジスタ
    var l: UInt8 = 0          // L レジスタ
    var ixh: UInt8 = 0        // IX 高位バイト
    var ixl: UInt8 = 0        // IX 低位バイト
    var iyh: UInt8 = 0        // IY 高位バイト
    var iyl: UInt8 = 0        // IY 低位バイト
    var i: UInt8 = 0          // 割り込みベクトル
    var r: UInt8 = 0          // リフレッシュレジスタ
    
    // 交換用レジスタ（プライムレジスタ）
    var aPrime: UInt8 = 0     // A' レジスタ
    var fPrime: UInt8 = 0     // F' レジスタ
    var bPrime: UInt8 = 0     // B' レジスタ
    var cPrime: UInt8 = 0     // C' レジスタ
    var dPrime: UInt8 = 0     // D' レジスタ
    var ePrime: UInt8 = 0     // E' レジスタ
    var hPrime: UInt8 = 0     // H' レジスタ
    var lPrime: UInt8 = 0     // L' レジスタ
    
    // 複合レジスタ（便宜上）
    func ix() -> Int {
        return (Int(ixh) << 8) | Int(ixl)
    }
    
    func iy() -> Int {
        return (Int(iyh) << 8) | Int(iyl)
    }
    
    // ループ検出用
    var lastPCs = [Int]()    // 直近のPC値を保存
    var startPC: Int = 0     // 命令実行開始時のPC値
    
    // PMD固有の状態追跡
    var inOpnset46: Bool = false  // opnset46ルーチン内かどうか
    var opnset46State: Int = 0    // opnset46ルーチンの実行状態
    
    // メモリとポート
    var memory = [UInt8](repeating: 0, count: 0x10000)  // 64KBメモリ空間
    var ports = [UInt8: UInt8]()  // IOポート空間（キー：ポート番号、値：ポートの値）
    var portMap = [UInt8: UInt8]()  // ポートマッピングテーブル
    var isStopped: Bool = false  // 停止フラグ
    
    // ブレークポイントとデバッグ
    var breakPoint: Int = -1  // ブレークポイント（-1は無効）
    var stepCount: Int = 0  // 実行ステップ数
    var debugMode: Bool = false  // デバッグモード
    var debugLog = [String]()  // デバッグログ配列
    var outPortCounter = 0  // ポート出力カウンター
    
    // OPNAレジスタ関連
    public var opnaRegisters = [UInt8](repeating: 0, count: 0x200)  // OPNAレジスタ（アドレス空間を広めに確保）
    var ppiRegisters = [UInt8](repeating: 0, count: 4)  // PPIレジスタ
    var regAddrPort44: UInt8 = 0  // 表FM音源カレントレジスタアドレス
    var regAddrPort46: UInt8 = 0  // 裏FM音源カレントレジスタアドレス
    var addrWritten = [UInt8: Bool]()  // アドレスレジスタ書き込みフラグ
    var portWriteOrder = [(port: UInt8, value: UInt8)]()  // ポート書き込み順序
    
    // PMD処理関連
    var currentPortBase: UInt8 = 0x44  // 現在のポートベース (44h or 46h)
    var currentRegAddr = [UInt8: UInt8]()  // 各ポートの現在のレジスタアドレス
    var ports44_45 = [UInt8: UInt8]()  // ポート44/45に対する書き込み値
    var ports46_47 = [UInt8: UInt8]()  // ポート46/47に対する書き込み値
    
    // 特殊アドレス検出
    var sel44Address: Int = -1  // sel44ルーチンのアドレス
    var sel46Address: Int = -1  // sel46ルーチンのアドレス
    
    // OPNAビジーフラグシミュレーション
    private var port44Busy: Bool = false
    private var port44BusyCounter: Int = 0
    private var port46Busy: Bool = false
    private var port46BusyCounter: Int = 0
    
    // ボードタイプとポートマッピング
    var currentBoardType: BoardType = .pc8801_23
    
    // 初期化
    init() {
        reset()
    }
    
    // ポートをリセットして初期状態に戻す
    func reset() {
        pc = 0
        sp = 0xF000  // スタックポインタの初期値
        a = 0
        f = 0
        b = 0
        c = 0
        d = 0
        e = 0
        h = 0
        l = 0
        ixh = 0
        ixl = 0
        iyh = 0
        iyl = 0
        i = 0
        r = 0
        
        // メモリの初期化（ゼロクリア）
        memory = [UInt8](repeating: 0, count: 0x10000)
        
        // ポートの初期化
        ports = [:]
        portMap = [:]
        currentPortBase = 0x44
        addrWritten = [:]
        opnaRegisters = [UInt8](repeating: 0, count: 0x200)
        
        // デバッグログのクリア
        debugLog = []
        outPortCounter = 0
        
        // フラグのリセット
        isStopped = false
        
        // ボードタイプを検出
        detectBoardType()
    }
    
    // プログラムメモリにデータをロードする
    func loadProgram(at address: Int, data: Data) {
        for (i, byte) in data.enumerated() {
            if address + i < memory.count {
                memory[address + i] = byte
            }
        }
        addDebugLog("\(data.count)バイトのデータを\(String(format: "0x%04X", address))にロードしました")
    }
    
    // ボードタイプに応じたポートマッピングを設定する
    func setPortMapping(forBoard boardType: BoardType) {
        currentBoardType = boardType
        
        switch boardType {
        case .pc8801_23:
            // PC8801-23（第1世代FM音源ボード）のポートマッピング
            portMap[0x44] = 0xA8  // 表FM音源アドレスレジスタ
            portMap[0x45] = 0xA9  // 表FM音源データレジスタ
            portMap[0x46] = 0xAC  // 裏FM音源アドレスレジスタ
            portMap[0x47] = 0xAD  // 裏FM音源データレジスタ
            addDebugLog("PC8801-23ボード（旧OPN）ポートマッピング設定: 44h→A8h, 45h→A9h, 46h→ACh, 47h→ADh")
        case .pc8801_24:
            // PC8801-24以降（第2世代FM音源ボード）のポートマッピング
            // このモードではポート番号は変換されない（直接アクセス）
            portMap[0x44] = 0x44
            portMap[0x45] = 0x45
            portMap[0x46] = 0x46
            portMap[0x47] = 0x47
            addDebugLog("PC8801-24ボード（新OPN）ポートマッピング設定: 44h→44h, 45h→45h, 46h→46h, 47h→47h")
        }
    }
    
    // 初期化時などに呼び出す
    private func detectBoardType() {
        // PMDソースの`boardselect`ルーチンと同様の処理
        // PC8801-23: 44h→A8h, 45h→A9h, 46h→ACh, 47h→ADh
        // PC8801-24以降: 44h→44h, 45h→45h, 46h→46h, 47h→47h
        portMap[0x44] = 0xA8
        portMap[0x45] = 0xA9
        portMap[0x46] = 0xAC
        portMap[0x47] = 0xAD
        addDebugLog("PC8801-23ボード検出: ポートマッピング設定")
    }
    
    // Z80 CPUを1ステップ実行する
    func step() -> Int {
        lock.lock()
        defer { lock.unlock() }
        
        if pc == breakPoint {
            isStopped = true
            return 0
        }
        
        // PCの範囲チェック
        guard pc >= 0 && pc < memory.count else {
            addDebugLog("エラー: PCが無効な範囲です: \(String(format: "0x%04X", pc))")
            isStopped = true
            return 0
        }
        
        // 実行開始時のPC値を保存
        startPC = pc
        
        // ビジーフラグカウンターの処理
        if port44Busy {
            port44BusyCounter -= 1
            if port44BusyCounter <= 0 {
                port44Busy = false
                addDebugLog("OPNA: 表FM（ポート44/45）ビジー状態解除")
            }
        }
        
        if port46Busy {
            port46BusyCounter -= 1
            if port46BusyCounter <= 0 {
                port46Busy = false
                addDebugLog("OPNA: 裏FM（ポート46/47）ビジー状態解除")
            }
        }
        
        stepCount += 1
        
        // バッファオーバーフロー対策
        if sp < 0x100 || sp > 0xFF00 {
            addDebugLog("警告: スタックポインタが無効な値です: \(String(format: "0x%04X", sp))")
            return 0
        }
        
        // ループ検出
        lastPCs.append(startPC)
        if lastPCs.count > 100 {
            lastPCs.removeFirst()
            let uniquePCs = Set(lastPCs)
            if uniquePCs.count < 10 {
                addDebugLog("警告: 命令ループを検出しました。実行を停止します。")
                return 0
            }
        }
        
        // 命令フェッチ（PCの範囲チェック）
        guard pc < memory.count else {
            addDebugLog("エラー: PCが無効な範囲です: \(String(format: "0x%04X", pc))")
            isStopped = true
            return 0
        }
        
        let opcode = memory[pc]
        _ = 4  // 基本的なサイクル数
        var pcIncrement = 1  // 通常は1バイト進む
        
        if debugMode && stepCount % 5000 == 0 {
            addDebugLog("PC=\(String(format: "0x%04X", pc)) Opcode=\(String(format: "0x%02X", opcode))")
        }
        
        // 命令デコード＆実行
        switch opcode {
        case 0x00: break  // NOP
            // 何もしない
            
        case 0x01:  // LD BC, nn
            if pc + 2 < memory.count {
                c = memory[pc + 1]
                b = memory[pc + 2]
                
                if debugMode && stepCount % 5000 == 0 {
                    addDebugLog("LD BC, \(String(format: "0x%04X", bc()))")
                }
                
                pcIncrement = 3
            } else {
                addDebugLog("エラー: メモリ範囲外アクセス at PC=\(String(format: "0x%04X", pc))")
                pcIncrement = 0
            }
            
        case 0x11:  // LD DE, nn
            if pc + 2 < memory.count {
                e = memory[pc + 1]
                d = memory[pc + 2]
                
                if debugMode && stepCount % 5000 == 0 {
                    addDebugLog("LD DE, \(String(format: "0x%04X", de()))")
                }
                
                pcIncrement = 3
            } else {
                addDebugLog("エラー: メモリ範囲外アクセス at PC=\(String(format: "0x%04X", pc))")
                pcIncrement = 0
            }
            
        case 0x21:  // LD HL, nn
            if pc + 2 < memory.count {
                l = memory[pc + 1]
                h = memory[pc + 2]
                
                if debugMode && stepCount % 5000 == 0 {
                    addDebugLog("LD HL, \(String(format: "0x%04X", hl()))")
                }
                
                pcIncrement = 3
            } else {
                addDebugLog("エラー: メモリ範囲外アクセス at PC=\(String(format: "0x%04X", pc))")
                pcIncrement = 0
            }
            
        case 0x31:  // LD SP, nn
            if pc + 2 < memory.count {
                let low = Int(memory[pc + 1])
                let high = Int(memory[pc + 2])
                sp = (high << 8) | low
                
                if debugMode && stepCount % 5000 == 0 {
                    addDebugLog("LD SP, \(String(format: "0x%04X", sp))")
                }
                
                pcIncrement = 3
            } else {
                addDebugLog("エラー: メモリ範囲外アクセス at PC=\(String(format: "0x%04X", pc))")
                pcIncrement = 0
            }
            
        case 0x80:  // ADD A, B
            a = addA(b)
            
        case 0x81:  // ADD A, C
            a = addA(c)
            
        case 0x82:  // ADD A, D
            a = addA(d)
            
        case 0x83:  // ADD A, E
            a = addA(e)
            
        case 0x84:  // ADD A, H
            a = addA(h)
            
        case 0x85:  // ADD A, L
            a = addA(l)
            
        case 0x86:  // ADD A, (HL)
            if hl() < memory.count {
                a = addA(memory[hl()])
            } else {
                addDebugLog("エラー: メモリ範囲外アクセス at HL=\(String(format: "0x%04X", hl()))")
                isStopped = true
                return 0
            }
            
        case 0x87:  // ADD A, A
            a = addA(a)
            
        case 0x90:  // SUB B
            a = subA(b)
            
        case 0x91:  // SUB C
            a = subA(c)
            
        case 0x92:  // SUB D
            a = subA(d)
            
        case 0x93:  // SUB E
            a = subA(e)
            
        case 0x94:  // SUB H
            a = subA(h)
            
        case 0x95:  // SUB L
            a = subA(l)
            
        case 0x96:  // SUB (HL)
            if hl() < memory.count {
                a = subA(memory[hl()])
            } else {
                addDebugLog("エラー: メモリ範囲外アクセス at HL=\(String(format: "0x%04X", hl()))")
                isStopped = true
                return 0
            }
            
        case 0x97:  // SUB A
            a = subA(a)
            
        case 0xC3:  // JP nn
            if pc + 2 < memory.count {
                let lowByte = memory[pc + 1]
                let highByte = memory[pc + 2]
                let address = (Int(highByte) << 8) | Int(lowByte)
                
                if debugMode && stepCount % 5000 == 0 {
                    addDebugLog("JP \(String(format: "0x%04X", address))")
                }
                
                // 有効な範囲かチェック
                if address >= 0 && address < memory.count {
                    pc = address
                    return 1  // PCを手動で更新したので、このメソッドの最後のpc += pcIncrementをスキップ
                } else {
                    addDebugLog("エラー: 無効なアドレスへのジャンプ: \(String(format: "0x%04X", address))")
                    isStopped = true
                    return 0
                }
            } else {
                addDebugLog("エラー: メモリ範囲外アクセス at PC=\(String(format: "0x%04X", pc))")
                pcIncrement = 0
            }
            
        case 0xCD:  // CALL nn
            if pc + 2 < memory.count && sp - 2 >= 0 {
                let lowByte = memory[pc + 1]
                let highByte = memory[pc + 2]
                let address = (Int(highByte) << 8) | Int(lowByte)
                
                if debugMode && stepCount % 5000 == 0 {
                    addDebugLog("CALL \(String(format: "0x%04X", address))")
                }
                
                // アドレス範囲チェック
                if address >= 0 && address < memory.count {
                    // スタック範囲チェック
                    if sp - 2 >= 0 && sp < memory.count {
                        // リターンアドレス（PC+3）をスタックに積む
                        sp -= 2
                        let returnAddr = pc + 3
                        memory[sp] = UInt8(returnAddr & 0xFF)
                        memory[sp + 1] = UInt8((returnAddr >> 8) & 0xFF)
                        
                        pc = address
                        return 1  // PCを手動で更新
                    } else {
                        addDebugLog("エラー: スタックポインタが無効な範囲です: \(String(format: "0x%04X", sp))")
                        isStopped = true
                        return 0
                    }
                } else {
                    addDebugLog("エラー: 無効なアドレスへのコール: \(String(format: "0x%04X", address))")
                    isStopped = true
                    return 0
                }
            } else {
                addDebugLog("エラー: CALL命令でメモリ範囲外アクセス at PC=\(String(format: "0x%04X", pc))")
                pcIncrement = 0
            }
            
        case 0xC9:  // RET
            // スタック範囲チェック
            if sp >= 0 && sp + 1 < memory.count {
                let lowByte = memory[sp]
                let highByte = memory[sp + 1]
                let address = (Int(highByte) << 8) | Int(lowByte)
                
                if debugMode && stepCount % 5000 == 0 {
                    addDebugLog("RET to \(String(format: "0x%04X", address))")
                }
                
                // アドレス範囲チェック
                if address >= 0 && address < memory.count {
                    sp += 2
                    pc = address
                    return 1  // PCを手動で更新
                } else {
                    addDebugLog("エラー: 無効なアドレスへのリターン: \(String(format: "0x%04X", address))")
                    isStopped = true
                    return 0
                }
            } else {
                addDebugLog("エラー: RET命令でスタックポインタが無効な範囲です: \(String(format: "0x%04X", sp))")
                isStopped = true
                return 0
            }
            
        case 0x3E:  // LD A, n
            if pc + 1 < memory.count {
                a = memory[pc + 1]
                
                if debugMode && stepCount % 5000 == 0 {
                    addDebugLog("LD A, \(String(format: "0x%02X", a))")
                }
                
                pcIncrement = 2
            } else {
                addDebugLog("エラー: メモリ範囲外アクセス at PC=\(String(format: "0x%04X", pc))")
                pcIncrement = 0
            }
            
        case 0x06:  // LD B, n
            if pc + 1 < memory.count {
                b = memory[pc + 1]
                pcIncrement = 2
            } else {
                addDebugLog("エラー: メモリ範囲外アクセス at PC=\(String(format: "0x%04X", pc))")
                pcIncrement = 0
            }
            
        case 0x0E:  // LD C, n
            if pc + 1 < memory.count {
                c = memory[pc + 1]
                pcIncrement = 2
            } else {
                addDebugLog("エラー: メモリ範囲外アクセス at PC=\(String(format: "0x%04X", pc))")
                pcIncrement = 0
            }
            
        case 0x16:  // LD D, n
            if pc + 1 < memory.count {
                d = memory[pc + 1]
                pcIncrement = 2
            } else {
                addDebugLog("エラー: メモリ範囲外アクセス at PC=\(String(format: "0x%04X", pc))")
                pcIncrement = 0
            }
            
        case 0x1E:  // LD E, n
            if pc + 1 < memory.count {
                e = memory[pc + 1]
                pcIncrement = 2
            } else {
                addDebugLog("エラー: メモリ範囲外アクセス at PC=\(String(format: "0x%04X", pc))")
                pcIncrement = 0
            }
            
        case 0x26:  // LD H, n
            if pc + 1 < memory.count {
                h = memory[pc + 1]
                pcIncrement = 2
            } else {
                addDebugLog("エラー: メモリ範囲外アクセス at PC=\(String(format: "0x%04X", pc))")
                pcIncrement = 0
            }
            
        case 0x2E:  // LD L, n
            if pc + 1 < memory.count {
                l = memory[pc + 1]
                pcIncrement = 2
            } else {
                addDebugLog("エラー: メモリ範囲外アクセス at PC=\(String(format: "0x%04X", pc))")
                pcIncrement = 0
            }
            
        case 0xD3:  // OUT (n), A
            if pc + 1 < memory.count {
                let port = memory[pc + 1]
                
                if debugMode && stepCount % 1000 == 0 {
                    addDebugLog("OUT (\(String(format: "0x%02X", port))), A=\(String(format: "0x%02X", a))")
                }
                
                // ポート出力処理
                outPort(port: port, value: a)
                outPortCounter += 1
                
                pcIncrement = 2
            } else {
                addDebugLog("エラー: メモリ範囲外アクセス at PC=\(String(format: "0x%04X", pc))")
                pcIncrement = 0
            }
            
        case 0xDB:  // IN A, (n)
            if pc + 1 < memory.count {
                let port = memory[pc + 1]
                
                if debugMode && stepCount % 5000 == 0 {
                    addDebugLog("IN A, (\(String(format: "0x%02X", port)))")
                }
                
                // ポート入力処理
                a = inPort(port: port)
                
                pcIncrement = 2
            } else {
                addDebugLog("エラー: メモリ範囲外アクセス at PC=\(String(format: "0x%04X", pc))")
                pcIncrement = 0
            }
            
        case 0x32:  // LD (nn), A
            if pc + 2 < memory.count {
                let lowByte = memory[pc + 1]
                let highByte = memory[pc + 2]
                let address = (Int(highByte) << 8) | Int(lowByte)
                
                // アドレス範囲チェック
                if address >= 0 && address < memory.count {
                    memory[address] = a
                    
                    if debugMode && stepCount % 5000 == 0 {
                        addDebugLog("LD (\(String(format: "0x%04X", address))), A=\(String(format: "0x%02X", a))")
                    }
                } else {
                    addDebugLog("エラー: メモリ範囲外アクセス at address=\(String(format: "0x%04X", address))")
                    isStopped = true
                    return 0
                }
                
                pcIncrement = 3
            } else {
                addDebugLog("エラー: メモリ範囲外アクセス at PC=\(String(format: "0x%04X", pc))")
                pcIncrement = 0
            }
            
        case 0x3A:  // LD A, (nn)
            if pc + 2 < memory.count {
                let lowByte = memory[pc + 1]
                let highByte = memory[pc + 2]
                let address = (Int(highByte) << 8) | Int(lowByte)
                
                // アドレス範囲チェック
                if address >= 0 && address < memory.count {
                    a = memory[address]
                    
                    if debugMode && stepCount % 5000 == 0 {
                        addDebugLog("LD A, (\(String(format: "0x%04X", address))) = \(String(format: "0x%02X", a))")
                    }
                } else {
                    addDebugLog("エラー: メモリ範囲外アクセス at address=\(String(format: "0x%04X", address))")
                    isStopped = true
                    return 0
                }
                
                pcIncrement = 3
            } else {
                addDebugLog("エラー: メモリ範囲外アクセス at PC=\(String(format: "0x%04X", pc))")
                pcIncrement = 0
            }
            
        case 0xE6:  // AND n
            if pc + 1 < memory.count {
                let value = memory[pc + 1]
                a &= value
                
                // フラグ更新
                f = a == 0 ? Z_FLAG : 0
                
                if debugMode && stepCount % 5000 == 0 {
                    addDebugLog("AND \(String(format: "0x%02X", value)) = \(String(format: "0x%02X", a))")
                }
                
                pcIncrement = 2
            } else {
                addDebugLog("エラー: メモリ範囲外アクセス at PC=\(String(format: "0x%04X", pc))")
                pcIncrement = 0
            }
            
        case 0xF6:  // OR n
            if pc + 1 < memory.count {
                let value = memory[pc + 1]
                a |= value
                
                // フラグ更新
                f = a == 0 ? Z_FLAG : 0
                
                if debugMode && stepCount % 5000 == 0 {
                    addDebugLog("OR \(String(format: "0x%02X", value)) = \(String(format: "0x%02X", a))")
                }
                
                pcIncrement = 2
            } else {
                addDebugLog("エラー: メモリ範囲外アクセス at PC=\(String(format: "0x%04X", pc))")
                pcIncrement = 0
            }
            
        case 0xC2:  // JP NZ, nn
            if pc + 2 < memory.count {
                let lowByte = memory[pc + 1]
                let highByte = memory[pc + 2]
                let address = (Int(highByte) << 8) | Int(lowByte)
                
                if debugMode && stepCount % 5000 == 0 {
                    addDebugLog("JP NZ, \(String(format: "0x%04X", address)) [Z=\((f & Z_FLAG) != 0 ? "SET" : "RESET")]")
                }
                
                // Zフラグがセットされていなければジャンプ
                if (f & Z_FLAG) == 0 {
                    if address >= 0 && address < memory.count {
                        pc = address
                        return 1  // PCを手動で更新
                    } else {
                        addDebugLog("エラー: 無効なアドレスへのジャンプ: \(String(format: "0x%04X", address))")
                        isStopped = true
                        return 0
                    }
                }
                
                pcIncrement = 3
            } else {
                addDebugLog("エラー: メモリ範囲外アクセス at PC=\(String(format: "0x%04X", pc))")
                pcIncrement = 0
            }
            
        case 0xCA:  // JP Z, nn
            if pc + 2 < memory.count {
                let lowByte = memory[pc + 1]
                let highByte = memory[pc + 2]
                let address = (Int(highByte) << 8) | Int(lowByte)
                
                if debugMode && stepCount % 5000 == 0 {
                    addDebugLog("JP Z, \(String(format: "0x%04X", address)) [Z=\((f & Z_FLAG) != 0 ? "SET" : "RESET")]")
                }
                
                // Zフラグがセットされていればジャンプ
                if (f & Z_FLAG) != 0 {
                    if address >= 0 && address < memory.count {
                        pc = address
                        return 1  // PCを手動で更新
                    } else {
                        addDebugLog("エラー: 無効なアドレスへのジャンプ: \(String(format: "0x%04X", address))")
                        isStopped = true
                        return 0
                    }
                }
                
                pcIncrement = 3
            } else {
                addDebugLog("エラー: メモリ範囲外アクセス at PC=\(String(format: "0x%04X", pc))")
                pcIncrement = 0
            }
            
        case 0xD2:  // JP NC, nn
            if pc + 2 < memory.count {
                let lowByte = memory[pc + 1]
                let highByte = memory[pc + 2]
                let address = (Int(highByte) << 8) | Int(lowByte)
                
                if debugMode && stepCount % 5000 == 0 {
                    addDebugLog("JP NC, \(String(format: "0x%04X", address)) [C=\((f & C_FLAG) != 0 ? "SET" : "RESET")]")
                }
                
                // Cフラグがセットされていなければジャンプ
                if (f & C_FLAG) == 0 {
                    if address >= 0 && address < memory.count {
                        pc = address
                        return 1  // PCを手動で更新
                    } else {
                        addDebugLog("エラー: 無効なアドレスへのジャンプ: \(String(format: "0x%04X", address))")
                        isStopped = true
                        return 0
                    }
                }
                
                pcIncrement = 3
            } else {
                addDebugLog("エラー: メモリ範囲外アクセス at PC=\(String(format: "0x%04X", pc))")
                pcIncrement = 0
            }
            
        case 0xDA:  // JP C, nn
            if pc + 2 < memory.count {
                let lowByte = memory[pc + 1]
                let highByte = memory[pc + 2]
                let address = (Int(highByte) << 8) | Int(lowByte)
                
                if debugMode && stepCount % 5000 == 0 {
                    addDebugLog("JP C, \(String(format: "0x%04X", address)) [C=\((f & C_FLAG) != 0 ? "SET" : "RESET")]")
                }
                
                // Cフラグがセットされていればジャンプ
                if (f & C_FLAG) != 0 {
                    if address >= 0 && address < memory.count {
                        pc = address
                        return 1  // PCを手動で更新
                    } else {
                        addDebugLog("エラー: 無効なアドレスへのジャンプ: \(String(format: "0x%04X", address))")
                        isStopped = true
                        return 0
                    }
                }
                
                pcIncrement = 3
            } else {
                addDebugLog("エラー: メモリ範囲外アクセス at PC=\(String(format: "0x%04X", pc))")
                pcIncrement = 0
            }
            
        case 0x18:  // JR e
            if pc + 1 < memory.count {
                let offset = Int8(bitPattern: memory[pc + 1])
                let address = pc + 2 + Int(offset)  // PCはすでに命令の先頭を指している
                
                if debugMode && stepCount % 5000 == 0 {
                    addDebugLog("JR \(String(format: "%+d", Int(offset))) -> \(String(format: "0x%04X", address))")
                }
                
                if address >= 0 && address < memory.count {
                    pc = address
                    return 1  // PCを手動で更新
                } else {
                    addDebugLog("エラー: 無効なアドレスへのジャンプ: \(String(format: "0x%04X", address))")
                    isStopped = true
                    return 0
                }
            } else {
                addDebugLog("エラー: メモリ範囲外アクセス at PC=\(String(format: "0x%04X", pc))")
                pcIncrement = 0
            }
            
        case 0x20:  // JR NZ, e
            if pc + 1 < memory.count {
                let offset = Int8(bitPattern: memory[pc + 1])
                let address = pc + 2 + Int(offset)
                
                if debugMode && stepCount % 5000 == 0 {
                    addDebugLog("JR NZ, \(String(format: "%+d", Int(offset))) -> \(String(format: "0x%04X", address)) [Z=\((f & Z_FLAG) != 0 ? "SET" : "RESET")]")
                }
                
                // Zフラグがセットされていなければジャンプ
                if (f & Z_FLAG) == 0 {
                    if address >= 0 && address < memory.count {
                        pc = address
                        return 1  // PCを手動で更新
                    } else {
                        addDebugLog("エラー: 無効なアドレスへのジャンプ: \(String(format: "0x%04X", address))")
                        isStopped = true
                        return 0
                    }
                }
                
                pcIncrement = 2
            } else {
                addDebugLog("エラー: メモリ範囲外アクセス at PC=\(String(format: "0x%04X", pc))")
                pcIncrement = 0
            }
            
        case 0x28:  // JR Z, e
            if pc + 1 < memory.count {
                let offset = Int8(bitPattern: memory[pc + 1])
                let address = pc + 2 + Int(offset)
                
                if debugMode && stepCount % 5000 == 0 {
                    addDebugLog("JR Z, \(String(format: "%+d", Int(offset))) -> \(String(format: "0x%04X", address)) [Z=\((f & Z_FLAG) != 0 ? "SET" : "RESET")]")
                }
                
                // Zフラグがセットされていればジャンプ
                if (f & Z_FLAG) != 0 {
                    if address >= 0 && address < memory.count {
                        pc = address
                        return 1  // PCを手動で更新
                    } else {
                        addDebugLog("エラー: 無効なアドレスへのジャンプ: \(String(format: "0x%04X", address))")
                        isStopped = true
                        return 0
                    }
                }
                
                pcIncrement = 2
            } else {
                addDebugLog("エラー: メモリ範囲外アクセス at PC=\(String(format: "0x%04X", pc))")
                pcIncrement = 0
            }
            
        case 0x30:  // JR NC, e
            if pc + 1 < memory.count {
                let offset = Int8(bitPattern: memory[pc + 1])
                let address = pc + 2 + Int(offset)
                
                if debugMode && stepCount % 5000 == 0 {
                    addDebugLog("JR NC, \(String(format: "%+d", Int(offset))) -> \(String(format: "0x%04X", address)) [C=\((f & C_FLAG) != 0 ? "SET" : "RESET")]")
                }
                
                // Cフラグがセットされていなければジャンプ
                if (f & C_FLAG) == 0 {
                    if address >= 0 && address < memory.count {
                        pc = address
                        return 1  // PCを手動で更新
                    } else {
                        addDebugLog("エラー: 無効なアドレスへのジャンプ: \(String(format: "0x%04X", address))")
                        isStopped = true
                        return 0
                    }
                }
                
                pcIncrement = 2
            } else {
                addDebugLog("エラー: メモリ範囲外アクセス at PC=\(String(format: "0x%04X", pc))")
                pcIncrement = 0
            }
            
        case 0x38:  // JR C, e
            if pc + 1 < memory.count {
                let offset = Int8(bitPattern: memory[pc + 1])
                let address = pc + 2 + Int(offset)
                
                if debugMode && stepCount % 5000 == 0 {
                    addDebugLog("JR C, \(String(format: "%+d", Int(offset))) -> \(String(format: "0x%04X", address)) [C=\((f & C_FLAG) != 0 ? "SET" : "RESET")]")
                }
                
                // Cフラグがセットされていればジャンプ
                if (f & C_FLAG) != 0 {
                    if address >= 0 && address < memory.count {
                        pc = address
                        return 1  // PCを手動で更新
                    } else {
                        addDebugLog("エラー: 無効なアドレスへのジャンプ: \(String(format: "0x%04X", address))")
                        isStopped = true
                        return 0
                    }
                }
                
                pcIncrement = 2
            } else {
                addDebugLog("エラー: メモリ範囲外アクセス at PC=\(String(format: "0x%04X", pc))")
                pcIncrement = 0
            }
            
        default:
            if debugMode && (stepCount < 100 || stepCount % 10000 == 0) {
                addDebugLog("未実装の命令: \(String(format: "0x%02X", opcode)) at PC=\(String(format: "0x%04X", pc))")
            }
        }
        
        // PC更新
        pc += pcIncrement
        return 1
    }
    
    // レジスタアクセスヘルパー
    func bc() -> Int {
        return (Int(b) << 8) | Int(c)
    }
    
    func de() -> Int {
        return (Int(d) << 8) | Int(e)
    }
    
    func hl() -> Int {
        return (Int(h) << 8) | Int(l)
    }
    
    // デバッグログ追加ヘルパー
    func addDebugLog(_ message: String) {
        if debugMode {
            debugLog.append(message)
            if debugLog.count > 1000 {
                debugLog.removeFirst(500) // ログが大きくなりすぎないようにする
            }
        }
    }
    
    // OPNAレジスタ書き込み処理
    func processOPNARegisterWrite(portBase: UInt8, regAddr: UInt8, value: UInt8) {
        var regIndex = Int(regAddr)
        
        if portBase == 0x44 {
            // 表FM音源レジスタ (0x44/0x45)
            // 安全チェック
            if regIndex >= 0 && regIndex < opnaRegisters.count {
                opnaRegisters[regIndex] = value
                addDebugLog("OPNA: 表FM Reg[\(String(format: "%02X", regAddr))] = \(String(format: "%02X", value))]")
                
                // レジスタの機能に基づいた処理
                handleOPNARegisterEffect(isMainChip: true, regAddr: regAddr, value: value)
            } else {
                addDebugLog("エラー: 無効なOPNAレジスタアドレス: \(String(format: "0x%02X", regAddr))")
            }
        } else {
            // 裏FM音源レジスタ (0x46/0x47)
            regIndex = Int(regAddr) + 0x100  // 裏FM音源は0x100オフセット
            // 安全チェック
            if regIndex >= 0 && regIndex < opnaRegisters.count {
                opnaRegisters[regIndex] = value
                addDebugLog("OPNA: 裏FM Reg[\(String(format: "%02X", regAddr))] = \(String(format: "%02X", value))]")
                
                // レジスタの機能に基づいた処理
                handleOPNARegisterEffect(isMainChip: false, regAddr: regAddr, value: value)
            } else {
                addDebugLog("エラー: 無効なOPNAレジスタアドレス: \(String(format: "0x%02X", regAddr)) + 0x100")
            }
        }
    }
    
    // レジスタ書き込みに応じた効果を処理
    private func handleOPNARegisterEffect(isMainChip: Bool, regAddr: UInt8, value: UInt8) {
        // チップの種類に応じたログ接頭辞
        let chipPrefix = isMainChip ? "表FM" : "裏FM"
        
        switch regAddr {
        case 0x00...0x0F:  // SSG制御レジスタ（PSG互換）
            handleSSGRegister(isMainChip: isMainChip, subAddr: regAddr, value: value)
            
        case 0x10...0x1F:  // リズム・ADPCMレジスタ
            if regAddr == 0x10 {
                addDebugLog("OPNA: \(chipPrefix) ADPCMデータレジスタ設定: \(String(format: "0x%02X", value))")
            } else if regAddr == 0x11 {
                addDebugLog("OPNA: \(chipPrefix) ADPCMデータ書き込み: \(String(format: "0x%02X", value))")
            } else if regAddr == 0x1B {
                // リズムコントロールレジスタ
                let rhythmEnabled = (value & 0x80) != 0
                addDebugLog("OPNA: \(chipPrefix) リズム音源 \(rhythmEnabled ? "有効" : "無効")")
                
                if rhythmEnabled {
                    let activeChannels = [
                        (value & 0x01) != 0 ? "バスドラム" : nil,
                        (value & 0x02) != 0 ? "スネアドラム" : nil,
                        (value & 0x04) != 0 ? "トムトム" : nil,
                        (value & 0x08) != 0 ? "タムタム" : nil,
                        (value & 0x10) != 0 ? "シンバル" : nil,
                        (value & 0x20) != 0 ? "ハイハット" : nil
                    ].compactMap { $0 }
                    
                    if !activeChannels.isEmpty {
                        addDebugLog("OPNA: \(chipPrefix) アクティブリズムチャンネル: \(activeChannels.joined(separator: ", "))")
                    }
                }
            }
            
        case 0x24:  // タイマー設定
            let timerAEnabled = (value & 0x01) != 0
            let timerBEnabled = (value & 0x02) != 0
            addDebugLog("OPNA: \(chipPrefix) タイマー設定 - A: \(timerAEnabled ? "有効" : "無効"), B: \(timerBEnabled ? "有効" : "無効")")
            
        case 0x27:  // チャンネルモード
            let mode = (value >> 6) & 0x03
            let modeNames = ["2オペレータ×6チャンネル", "2オペレータ×9チャンネル", "4オペレータ×3チャンネル", "4オペレータ×6チャンネル"]
            addDebugLog("OPNA: \(chipPrefix) チャンネルモード: \(modeNames[Int(mode)])")
            
        case 0x28:  // キーオン/オフ
            let channel = value & 0x07
            let slot1 = ((value >> 4) & 0x01) != 0
            let slot2 = ((value >> 5) & 0x01) != 0
            let slot3 = ((value >> 6) & 0x01) != 0
            let slot4 = ((value >> 7) & 0x01) != 0
            
            if slot1 || slot2 || slot3 || slot4 {
                addDebugLog("OPNA: \(chipPrefix) キーオン - CH\(channel), スロット: \(slot1 ? "1" : "")\(slot2 ? "2" : "")\(slot3 ? "3" : "")\(slot4 ? "4" : "")")
            } else {
                addDebugLog("OPNA: \(chipPrefix) キーオフ - CH\(channel)")
            }
            
        case 0xA0...0xA8:  // 周波数LSB
            let ch = regAddr - 0xA0
            if ch <= 2 {
                addDebugLog("OPNA: \(chipPrefix) CH\(ch)周波数LSB設定: \(String(format: "0x%02X", value))")
            }
            
        case 0xA4...0xA6:  // 周波数MSB
            let ch = regAddr - 0xA4
            addDebugLog("OPNA: \(chipPrefix) CH\(ch)周波数MSB設定: \(String(format: "0x%02X", value))")
            
        case 0xB0...0xB2:  // アルゴリズム・フィードバック
            let ch = regAddr - 0xB0
            let algorithm = value & 0x07
            let feedback = (value >> 3) & 0x07
            addDebugLog("OPNA: \(chipPrefix) CH\(ch)アルゴリズム: \(algorithm), フィードバック: \(feedback)")
            
        case 0x0D:  // エンベロープシェイプ
            let shapeName: String
            switch value & 0x0F {
            case 0x00, 0x04, 0x08, 0x0C: shapeName = "\\___"
            case 0x01, 0x05, 0x09, 0x0D: shapeName = "/__/"
            case 0x02, 0x06, 0x0A, 0x0E: shapeName = "↘↘↘"
            case 0x03, 0x07, 0x0B, 0x0F: shapeName = "////"
            default: shapeName = "不明"
            }
            addDebugLog("OPNA: \(chipPrefix) SSGエンベロープシェイプ: \(shapeName) (値:\(String(format: "0x%02X", value)))")
            
        default:
            // その他のレジスタは単純に値を表示
            addDebugLog("OPNA: \(chipPrefix) SSGレジスタ[\(String(format: "%02X", regAddr))]: \(String(format: "0x%02X", value))")
        }
    }
    
    // SSG（PSG互換部分）のレジスタ処理
    private func handleSSGRegister(isMainChip: Bool, subAddr: UInt8, value: UInt8) {
        let chipPrefix = isMainChip ? "表FM" : "裏FM"
        
        switch subAddr {
        case 0x00, 0x02, 0x04:  // チャンネルA,B,C周波数LSB
            let ch = ["A", "B", "C"][Int(subAddr) / 2]
            addDebugLog("OPNA: \(chipPrefix) SSG CH\(ch)周波数LSB: \(String(format: "0x%02X", value))")
            
        case 0x01, 0x03, 0x05:  // チャンネルA,B,C周波数MSB
            let ch = ["A", "B", "C"][Int(subAddr - 1) / 2]
            addDebugLog("OPNA: \(chipPrefix) SSG CH\(ch)周波数MSB: \(String(format: "0x%02X", value))")
            
        case 0x06:  // ノイズ周波数
            addDebugLog("OPNA: \(chipPrefix) SSGノイズ周波数: \(String(format: "0x%02X", value))")
            
        case 0x07:  // ミキサー設定
            let toneA = (value & 0x01) == 0
            let toneB = (value & 0x02) == 0
            let toneC = (value & 0x04) == 0
            let noiseA = (value & 0x08) == 0
            let noiseB = (value & 0x10) == 0
            let noiseC = (value & 0x20) == 0
            
            var mixInfo = "OPNA: \(chipPrefix) SSGミキサー - "
            mixInfo += "A: \(toneA ? "トーン" : "")\(noiseA ? "ノイズ" : "")"
            mixInfo += ", B: \(toneB ? "トーン" : "")\(noiseB ? "ノイズ" : "")"
            mixInfo += ", C: \(toneC ? "トーン" : "")\(noiseC ? "ノイズ" : "")"
            addDebugLog(mixInfo)
            
        case 0x08, 0x09, 0x0A:  // チャンネルA,B,C音量
            let ch = ["A", "B", "C"][Int(subAddr - 0x08)]
            let volume = value & 0x0F
            let useEnvelope = (value & 0x10) != 0
            addDebugLog("OPNA: \(chipPrefix) SSG CH\(ch)音量: \(volume)\(useEnvelope ? " (エンベロープ使用)" : "")")
            
        case 0x0B:  // エンベロープ周期LSB
            addDebugLog("OPNA: \(chipPrefix) SSGエンベロープ周期LSB: \(String(format: "0x%02X", value))")
            
        case 0x0C:  // エンベロープ周期MSB
            addDebugLog("OPNA: \(chipPrefix) SSGエンベロープ周期MSB: \(String(format: "0x%02X", value))")
            
        default:
            // その他のレジスタは単純に値を表示
            addDebugLog("OPNA: \(chipPrefix) SSGレジスタ[\(String(format: "%02X", subAddr))]: \(String(format: "0x%02X", value))")
        }
    }
    
    // ポート出力処理
    private func outPort(port: UInt8, value: UInt8) {
        // ポートマッピングを確認
        var actualPort = port
        if let mapped = portMap[port] {
            actualPort = mapped
        }
        
        // ポートに値を設定
        ports[actualPort] = value
        
        // PMDが特定のメモリ位置にアクセスする時のデバッグ出力（音楽データ認識を確認）
        // 0x4C00-0x4CFFは音楽データがロードされる場所
        if (pc >= 0xAA00 && pc <= 0xAFFF) && // PMD2gのコード範囲
           (hl() >= 0x4C00 && hl() <= 0x4CFF) { // 音楽データの範囲
            addDebugLog("PMD2がメモリ位置 0x\(String(format: "%04X", hl()))にアクセスしました（音楽データ読み取り）")
            addDebugLog("  - PCが0x\(String(format: "%04X", pc))にある時、値=0x\(String(format: "%02X", memory[hl()]))")
        }
        
        // オリジナルのPMDコード（PC8801-23ボード）のために特別な処理
        switch port {
        case 0x44:  // 表FM音源アドレス
            regAddrPort44 = value
            addrWritten[0x44] = true
            // デバッグログの強化 - 常に表示
            addDebugLog("OUT (44h), \(String(format: "0x%02X", value)) - 表FMアドレス設定")
            
        case 0x45:  // 表FM音源データ
            if addrWritten[0x44] == true {
                processOPNARegisterWrite(portBase: 0x44, regAddr: regAddrPort44, value: value)
                addrWritten[0x44] = false
            }
            // デバッグログの強化 - 常に表示
            addDebugLog("OUT (45h), \(String(format: "0x%02X", value)) - 表FMデータ書き込み Reg[\(String(format: "%02X", regAddrPort44))]")
            
        case 0x46:  // 裏FM音源アドレス
            regAddrPort46 = value
            addrWritten[0x46] = true
            // デバッグログの強化 - 常に表示
            addDebugLog("OUT (46h), \(String(format: "0x%02X", value)) - 裏FMアドレス設定")
            
        case 0x47:  // 裏FM音源データ
            if addrWritten[0x46] == true {
                processOPNARegisterWrite(portBase: 0x46, regAddr: regAddrPort46, value: value)
                addrWritten[0x46] = false
            }
            // デバッグログの強化 - 常に表示
            addDebugLog("OUT (47h), \(String(format: "0x%02X", value)) - 裏FMデータ書き込み Reg[\(String(format: "%02X", regAddrPort46))]")
            
        default:
            if debugMode && stepCount % 5000 == 0 {
                addDebugLog("OUT (\(String(format: "0x%02X", port))), \(String(format: "0x%02X", value))")
            }
        }
    }
    
    // ポート入力処理
    private func inPort(port: UInt8) -> UInt8 {
        // ポートマッピングを確認
        var actualPort = port
        if let mapped = portMap[port] {
            actualPort = mapped
        }
        
        // FMポートのビジー状態をシミュレート
        if port == 0x44 && port44Busy {
            addDebugLog("IN (44h) - 表FMステータス: ビジー")
            return 0x80  // ビジーフラグを立てる
        }
        
        if port == 0x46 && port46Busy {
            addDebugLog("IN (46h) - 裏FMステータス: ビジー")
            return 0x80  // ビジーフラグを立てる
        }
        
        // ポートの値を返す
        let value = ports[actualPort] ?? 0
        
        // 重要なポートの読み取りをログに記録
        if port == 0x44 {
            addDebugLog("IN (44h) - 表FMステータス: \(String(format: "0x%02X", value))")
        } else if port == 0x46 {
            addDebugLog("IN (46h) - 裏FMステータス: \(String(format: "0x%02X", value))")
        } else if (port >= 0x30 && port <= 0x33) || port == 0x07 {
            // PMDがよく使う他のポート
            addDebugLog("IN (\(String(format: "%02Xh", port))) = \(String(format: "0x%02X", value))")
        }
        
        return value
    }
    
    // ALU操作のヘルパーメソッド
    private func addA(_ value: UInt8) -> UInt8 {
        let result16 = UInt16(a) + UInt16(value)
        let halfCarry = ((a & 0x0F) + (value & 0x0F)) > 0x0F
        
        // フラグを設定
        f = 0
        
        // サインフラグ
        if (result16 & 0x80) != 0 {
            f |= S_FLAG
        }
        
        // ゼロフラグ
        if (result16 & 0xFF) == 0 {
            f |= Z_FLAG
        }
        
        // ハーフキャリーフラグ
        if halfCarry {
            f |= H_FLAG
        }
        
        // パリティ/オーバーフローフラグ
        let overflow = (~(a ^ value) & (a ^ UInt8(result16 & 0xFF)) & 0x80) != 0
        if overflow {
            f |= P_FLAG
        }
        
        // キャリーフラグ
        if result16 > 0xFF {
            f |= C_FLAG
        }
        
        return UInt8(result16 & 0xFF)
    }
    
    private func subA(_ value: UInt8) -> UInt8 {
        let result = a &- value
        let halfCarry = (a & 0x0F) < (value & 0x0F)
        
        // フラグを設定
        f = N_FLAG  // 減算フラグは常にセット
        
        // サインフラグ
        if (result & 0x80) != 0 {
            f |= S_FLAG
        }
        
        // ゼロフラグ
        if result == 0 {
            f |= Z_FLAG
        }
        
        // ハーフキャリーフラグ
        if halfCarry {
            f |= H_FLAG
        }
        
        // パリティ/オーバーフローフラグ
        let overflow = ((a ^ value) & (a ^ result) & 0x80) != 0
        if overflow {
            f |= P_FLAG
        }
        
        // キャリーフラグ
        if a < value {
            f |= C_FLAG
        }
        
        return result
    }
} 
