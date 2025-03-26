import Foundation

/// PC-8801のBIOS関数コード
enum PC88BIOSFunction: UInt8 {
    case diskRead = 0x01      // ディスクからの読み込み
    case diskWrite = 0x02     // ディスクへの書き込み
    case consoleIn = 0x03     // コンソール入力
    case consoleOut = 0x04    // コンソール出力
    case listOut = 0x05       // プリンタ出力
    case directConsoleIO = 0x06 // 直接コンソールI/O
    case directConsoleStatus = 0x07 // 直接コンソール状態
    case consoleInNoEcho = 0x08 // エコーなしコンソール入力
    case printString = 0x09   // 文字列出力
    case readConsoleString = 0x0A // コンソール文字列入力
    case consoleStatus = 0x0B // コンソール状態取得
    case clearInputBuffer = 0x0C // 入力バッファクリア
    case diskReset = 0x0D     // ディスクリセット
    case selectDisk = 0x0E    // ディスク選択
    case openFile = 0x0F      // ファイルオープン
    case closeFile = 0x10     // ファイルクローズ
    case searchFirst = 0x11   // 最初のファイル検索
    case searchNext = 0x12    // 次のファイル検索
    case deleteFile = 0x13    // ファイル削除
    case readSequential = 0x14 // 順次読み込み
    case writeSequential = 0x15 // 順次書き込み
    case createFile = 0x16    // ファイル作成
    case renameFile = 0x17    // ファイル名変更
    case getDiskInfo = 0x1B   // ディスク情報取得
    case setDTA = 0x1A        // ディスク転送アドレス設定
    case getSystemParams = 0x1F // システムパラメータ取得
    case getSetUserCode = 0x20 // ユーザーコード取得/設定
    case randomRead = 0x21    // ランダム読み込み
    case randomWrite = 0x22   // ランダム書き込み
    case getFileSize = 0x23   // ファイルサイズ取得
    case setRandomRecord = 0x24 // ランダムレコード設定
    case terminateProcess = 0x31 // プロセス終了
    case getDate = 0x2A       // 日付取得
    case getTime = 0x2C       // 時刻取得
    
    // PC-8801固有の機能
    case getKeyboardStatus = 0x40 // キーボード状態取得
    case getScreenMode = 0x41  // 画面モード取得
    case setScreenMode = 0x42  // 画面モード設定
    case setCursorPosition = 0x43 // カーソル位置設定
    case getCursorPosition = 0x44 // カーソル位置取得
    case clearScreen = 0x45    // 画面クリア
}

/// PC-8801のBIOS ROMを管理するクラス
class PC88BIOS {
    /// BIOSデータ（名前をキーとする）
    private var biosData: [String: [UInt8]] = [:]
    
    /// 初期化
    init() {
        loadBIOSFromBundle()
    }
    
    /// BIOSファイルを読み込む
    func loadBIOSFile(name: String, from url: URL) -> Bool {
        do {
            let data = try Data(contentsOf: url)
            biosData[name] = [UInt8](data)
            print("BIOSファイルを読み込みました: \(name), サイズ: \(data.count)バイト")
            return true
        } catch {
            print("BIOSファイルの読み込みに失敗: \(name), エラー: \(error)")
            return false
        }
    }
    
    /// バンドルからBIOSファイルを読み込む
    @discardableResult
    func loadBIOSFromBundle() -> Bool {
        var success = true
        let biosFiles = ["N88", "N88N", "N88_0", "N88_1", "N88_2", "N88_3", "DISK"]
        
        for biosName in biosFiles {
            if let biosURL = Bundle.main.url(forResource: biosName, withExtension: "ROM") {
                if !loadBIOSFile(name: biosName, from: biosURL) {
                    success = false
                }
            } else {
                print("BIOSファイルが見つかりません: \(biosName).ROM")
                success = false
            }
        }
        
        return success
    }
    
    /// 指定したBIOSデータを取得
    func getBIOSData(name: String) -> [UInt8]? {
        return biosData[name]
    }
    
    /// BIOSデータをメモリにマッピング
    func mapBIOSToMemory(memory: inout [UInt8], biosName: String, startAddress: Int) -> Bool {
        guard let data = biosData[biosName] else {
            print("マッピングするBIOSデータが見つかりません: \(biosName)")
            return false
        }
        
        for i in 0..<data.count {
            if startAddress + i < memory.count {
                memory[startAddress + i] = data[i]
            }
        }
        
        print("BIOSをメモリにマッピングしました: \(biosName), アドレス: 0x\(String(format: "%04X", startAddress))")
        return true
    }
    
    // MARK: - BIOS関数ハンドラ
    
    /// BIOS関数を処理する
    /// - Parameters:
    ///   - functionId: BIOS関数ID
    ///   - cpu: Z80 CPUインスタンス
    ///   - disk: D88ディスクインスタンス
    ///   - screen: PC88Screenインスタンス
    /// - Returns: 処理が成功したかどうか
    func handleBIOSCall(functionId: UInt8, cpu: Z80, disk: D88Disk?, screen: PC88Screen) -> Bool {
        // BIOS関数IDを取得
        guard let biosFunction = PC88BIOSFunction(rawValue: functionId) else {
            print("未知のBIOS関数: 0x\(String(format: "%02X", functionId))")
            return false
        }
        
        // BIOS関数に応じた処理を実行
        switch biosFunction {
        case .diskRead:
            return handleDiskRead(cpu: cpu, disk: disk)
        case .diskWrite:
            return handleDiskWrite(cpu: cpu, disk: disk)
        case .consoleOut:
            return handleConsoleOut(cpu: cpu, screen: screen)
        case .printString:
            return handlePrintString(cpu: cpu, screen: screen)
        case .diskReset:
            return handleDiskReset(cpu: cpu, disk: disk)
        case .selectDisk:
            return handleSelectDisk(cpu: cpu, disk: disk)
        case .openFile:
            return handleOpenFile(cpu: cpu, disk: disk)
        case .searchFirst:
            return handleSearchFirst(cpu: cpu, disk: disk)
        case .searchNext:
            return handleSearchNext(cpu: cpu, disk: disk)
        case .readSequential:
            return handleReadSequential(cpu: cpu, disk: disk)
        case .setCursorPosition:
            return handleSetCursorPosition(cpu: cpu, screen: screen)
        case .clearScreen:
            return handleClearScreen(cpu: cpu, screen: screen)
        default:
            print("未実装のBIOS関数: \(biosFunction)")
            return false
        }
    }
    
    // MARK: - ディスクI/O関連のBIOS関数
    
    /// ディスク読み込み (BIOS関数 0x01)
    internal func handleDiskRead(cpu: Z80, disk: D88Disk?) -> Bool {
        guard let disk = disk else {
            // ディスクが挿入されていない場合はエラー
            cpu.a = 0xFF  // エラーコード
            cpu.setFlag(.carry, value: true)  // エラーフラグ
            return true
        }
        
        // パラメータ取得
        let driveNumber = cpu.e & 0x0F  // ドライブ番号
        let trackNumber = Int(cpu.d)    // トラック番号
        let sectorNumber = Int(cpu.c)   // セクタ番号
        let numSectors = cpu.b          // セクタ数
        let memoryAddress = cpu.getHL() // 転送先メモリアドレス
        
        print("BIOS: ディスク読み込み - ドライブ:\(driveNumber) トラック:\(trackNumber) セクタ:\(sectorNumber) 数:\(numSectors) アドレス:0x\(String(format: "%04X", memoryAddress))")
        
        // セクタデータを読み込む
        var sectorsRead: UInt8 = 0
        for i in 0..<numSectors {
            if let sectorData = disk.getSectorData(track: trackNumber, sector: sectorNumber + Int(i)) {
                // メモリに転送
                for (j, byte) in sectorData.enumerated() {
                    let addr = memoryAddress + UInt16(i) * 256 + UInt16(j)
                    if addr < UInt16(cpu.memory.count) {
                        cpu.memory[Int(addr)] = byte
                    }
                }
                sectorsRead += 1
            } else {
                break
            }
        }
        
        if sectorsRead == numSectors {
            // 成功
            cpu.a = 0x00  // 成功コード
            cpu.setFlag(.carry, value: false)  // 成功フラグ
            return true
        } else {
            // 一部または全部失敗
            cpu.a = 0x01  // エラーコード
            cpu.setFlag(.carry, value: true)  // エラーフラグ
            return true
        }
    }
    
    /// ディスク書き込み (BIOS関数 0x02)
    public func handleDiskWrite(cpu: Z80, disk: D88Disk?) -> Bool {
        // 書き込みは現在サポートしていないため、エラーを返す
        cpu.a = 0xFF  // エラーコード
        cpu.setFlag(.carry, value: true)  // エラーフラグ
        print("BIOS: ディスク書き込みは現在サポートされていません")
        return true
    }
    
    /// ディスクリセット (BIOS関数 0x0D)
    private func handleDiskReset(cpu: Z80, disk: D88Disk?) -> Bool {
        // ディスクシステムをリセット
        print("BIOS: ディスクシステムリセット")
        cpu.a = 0x00  // 成功コード
        cpu.setFlag(.carry, value: false)  // 成功フラグ
        return true
    }
    
    /// ディスク選択 (BIOS関数 0x0E)
    private func handleSelectDisk(cpu: Z80, disk: D88Disk?) -> Bool {
        let driveNumber = cpu.e & 0x0F  // ドライブ番号
        
        if disk != nil && driveNumber == 0 {
            // ドライブAが選択され、ディスクが挿入されている
            print("BIOS: ディスク選択 - ドライブ:\(driveNumber)")
            cpu.a = 0x00  // 成功コード
            cpu.setFlag(.carry, value: false)  // 成功フラグ
        } else {
            // 無効なドライブまたはディスクが挿入されていない
            print("BIOS: ディスク選択エラー - ドライブ:\(driveNumber)")
            cpu.a = 0xFF  // エラーコード
            cpu.setFlag(.carry, value: true)  // エラーフラグ
        }
        
        return true
    }
    
    /// ファイルオープン (BIOS関数 0x0F)
    internal func handleOpenFile(cpu: Z80, disk: D88Disk?) -> Bool {
        guard let disk = disk else {
            // ディスクが挿入されていない場合はエラー
            cpu.a = 0xFF  // エラーコード
            cpu.setFlag(.carry, value: true)  // エラーフラグ
            return true
        }
        
        // FCBアドレスを取得
        let fcbAddress = cpu.getDE()
        
        // FCBからファイル名を取得
        var fileName = ""
        for i in 1...8 {
            let charCode = cpu.memory[Int(fcbAddress) + i]
            if charCode != 0x20 { // スペース以外
                fileName.append(Character(UnicodeScalar(charCode)))
            }
        }
        
        // 拡張子を追加
        fileName += "."
        for i in 9...11 {
            let charCode = cpu.memory[Int(fcbAddress) + i]
            if charCode != 0x20 { // スペース以外
                fileName.append(Character(UnicodeScalar(charCode)))
            }
        }
        
        print("BIOS: ファイルオープン - \(fileName)")
        
        // ファイルを検索
        let fileInfo = disk.findFile(fileName: fileName)
        if fileInfo.found {
            // FCBを更新
            cpu.memory[Int(fcbAddress)] = 0  // ドライブ番号
            cpu.memory[Int(fcbAddress) + 12] = 0  // エクステント
            cpu.memory[Int(fcbAddress) + 13] = 0  // 予約
            cpu.memory[Int(fcbAddress) + 14] = 0  // レコード数
            
            // ファイルサイズ（レコード数）
            let recordCount = UInt16(fileInfo.size / 128)
            cpu.memory[Int(fcbAddress) + 15] = UInt8(recordCount & 0xFF)
            cpu.memory[Int(fcbAddress) + 16] = UInt8((recordCount >> 8) & 0xFF)
            
            // 開始クラスタ
            let startCluster = fileInfo.cluster
            cpu.memory[Int(fcbAddress) + 0x10] = UInt8(startCluster & 0xFF)
            cpu.memory[Int(fcbAddress) + 0x11] = UInt8((startCluster >> 8) & 0xFF)
            
            cpu.a = 0x00  // 成功コード
            cpu.setFlag(.carry, value: false)  // 成功フラグ
        } else {
            // ファイルが見つからない
            cpu.a = 0xFF  // エラーコード
            cpu.setFlag(.carry, value: true)  // エラーフラグ
        }
        
        return true
    }
    
    /// 最初のファイル検索 (BIOS関数 0x11)
    internal func handleSearchFirst(cpu: Z80, disk: D88Disk?) -> Bool {
        guard let disk = disk else {
            // ディスクが挿入されていない場合はエラー
            cpu.a = 0xFF  // エラーコード
            cpu.setFlag(.carry, value: true)  // エラーフラグ
            return true
        }
        
        // FCBアドレスを取得
        let fcbAddress = cpu.getDE()
        
        // FCBからファイル名パターンを取得
        var filePattern = ""
        for i in 1...8 {
            let charCode = cpu.memory[Int(fcbAddress) + i]
            if charCode == 0x3F { // '?'
                filePattern.append("?")
            } else if charCode != 0x20 { // スペース以外
                filePattern.append(Character(UnicodeScalar(charCode)))
            }
        }
        
        // 拡張子を追加
        filePattern += "."
        for i in 9...11 {
            let charCode = cpu.memory[Int(fcbAddress) + i]
            if charCode == 0x3F { // '?'
                filePattern.append("?")
            } else if charCode != 0x20 { // スペース以外
                filePattern.append(Character(UnicodeScalar(charCode)))
            }
        }
        
        print("BIOS: 最初のファイル検索 - パターン:\(filePattern)")
        
        // ファイルを検索
        let fileInfo = disk.findFirstFile()
        if fileInfo.found {
            // DTAにファイル情報を設定
            let dtaAddress = cpu.getHL()
            
            // ファイル名をDTAにコピー
            let fileName = fileInfo.fileName
            let nameParts = fileName.split(separator: ".")
            let baseName = nameParts[0]
            let fileExtension = nameParts.count > 1 ? nameParts[1] : ""
            
            // ベース名をコピー（最大8文字）
            for i in 0..<8 {
                if i < baseName.count {
                    let char = baseName[baseName.index(baseName.startIndex, offsetBy: i)]
                    cpu.memory[Int(dtaAddress) + i] = UInt8(char.asciiValue ?? 0x20)
                } else {
                    cpu.memory[Int(dtaAddress) + i] = 0x20 // スペース
                }
            }
            
            // 拡張子をコピー（最大3文字）
            for i in 0..<3 {
                if i < fileExtension.count {
                    let char = fileExtension[fileExtension.index(fileExtension.startIndex, offsetBy: i)]
                    cpu.memory[Int(dtaAddress) + 8 + i] = UInt8(char.asciiValue ?? 0x20)
                } else {
                    cpu.memory[Int(dtaAddress) + 8 + i] = 0x20 // スペース
                }
            }
            
            // ファイル属性
            cpu.memory[Int(dtaAddress) + 11] = 0x00 // 通常ファイル
            
            // ファイルサイズ
            let fileSize = fileInfo.size
            cpu.memory[Int(dtaAddress) + 12] = UInt8(fileSize & 0xFF)
            cpu.memory[Int(dtaAddress) + 13] = UInt8((fileSize >> 8) & 0xFF)
            cpu.memory[Int(dtaAddress) + 14] = UInt8((fileSize >> 16) & 0xFF)
            cpu.memory[Int(dtaAddress) + 15] = UInt8((fileSize >> 24) & 0xFF)
            
            cpu.a = 0x00  // 成功コード
            cpu.setFlag(.carry, value: false)  // 成功フラグ
        } else {
            // ファイルが見つからない
            cpu.a = 0xFF  // エラーコード
            cpu.setFlag(.carry, value: true)  // エラーフラグ
        }
        
        return true
    }
    
    /// 次のファイル検索 (BIOS関数 0x12)
    internal func handleSearchNext(cpu: Z80, disk: D88Disk?) -> Bool {
        guard let disk = disk else {
            // ディスクが挿入されていない場合はエラー
            cpu.a = 0xFF  // エラーコード
            cpu.setFlag(.carry, value: true)  // エラーフラグ
            return true
        }
        
        print("BIOS: 次のファイル検索")
        
        // 次のファイルを検索
        let fileInfo = disk.findNextFile()
        if fileInfo.found {
            // DTAにファイル情報を設定
            let dtaAddress = cpu.getHL()
            
            // ファイル名をDTAにコピー
            let fileName = fileInfo.fileName
            let nameParts = fileName.split(separator: ".")
            let baseName = nameParts[0]
            let fileExtension = nameParts.count > 1 ? nameParts[1] : ""
            
            // ベース名をコピー（最大8文字）
            for i in 0..<8 {
                if i < baseName.count {
                    let char = baseName[baseName.index(baseName.startIndex, offsetBy: i)]
                    cpu.memory[Int(dtaAddress) + i] = UInt8(char.asciiValue ?? 0x20)
                } else {
                    cpu.memory[Int(dtaAddress) + i] = 0x20 // スペース
                }
            }
            
            // 拡張子をコピー（最大3文字）
            for i in 0..<3 {
                if i < fileExtension.count {
                    let char = fileExtension[fileExtension.index(fileExtension.startIndex, offsetBy: i)]
                    cpu.memory[Int(dtaAddress) + 8 + i] = UInt8(char.asciiValue ?? 0x20)
                } else {
                    cpu.memory[Int(dtaAddress) + 8 + i] = 0x20 // スペース
                }
            }
            
            // ファイル属性
            cpu.memory[Int(dtaAddress) + 11] = 0x00 // 通常ファイル
            
            // ファイルサイズ
            let fileSize = fileInfo.size
            cpu.memory[Int(dtaAddress) + 12] = UInt8(fileSize & 0xFF)
            cpu.memory[Int(dtaAddress) + 13] = UInt8((fileSize >> 8) & 0xFF)
            cpu.memory[Int(dtaAddress) + 14] = UInt8((fileSize >> 16) & 0xFF)
            cpu.memory[Int(dtaAddress) + 15] = UInt8((fileSize >> 24) & 0xFF)
            
            cpu.a = 0x00  // 成功コード
            cpu.setFlag(.carry, value: false)  // 成功フラグ
        } else {
            // これ以上ファイルがない
            cpu.a = 0xFF  // エラーコード
            cpu.setFlag(.carry, value: true)  // エラーフラグ
        }
        
        return true
    }
    
    /// 順次読み込み (BIOS関数 0x14)
    internal func handleReadSequential(cpu: Z80, disk: D88Disk?) -> Bool {
        guard let disk = disk else {
            // ディスクが挿入されていない場合はエラー
            cpu.a = 0xFF  // エラーコード
            cpu.setFlag(.carry, value: true)  // エラーフラグ
            return true
        }
        
        // FCBアドレスを取得
        let fcbAddress = cpu.getDE()
        
        // FCBから現在のレコード位置を取得
        let currentRecord = cpu.memory[Int(fcbAddress) + 0x20]
        let currentExtent = cpu.memory[Int(fcbAddress) + 12]
        
        // 開始クラスタを取得
        let startClusterLow = cpu.memory[Int(fcbAddress) + 0x10]
        let startClusterHigh = cpu.memory[Int(fcbAddress) + 0x11]
        let startCluster = UInt16(startClusterHigh) << 8 | UInt16(startClusterLow)
        
        print("BIOS: 順次読み込み - レコード:\(currentRecord) エクステント:\(currentExtent) クラスタ:\(startCluster)")
        
        // レコード位置からファイル内のオフセットを計算
        _ = UInt32(currentExtent) * 16384 + UInt32(currentRecord) * 128
        
        // DTAアドレスを取得（デフォルトは0x0080）
        let dtaAddress: UInt16 = 0x0080
        
        // ファイルデータを読み込む
        if let fileData = disk.loadFileData(startCluster: Int(startCluster), fileSize: 128) {
            // DTAにデータをコピー
            for (i, byte) in fileData.enumerated() {
                if i < 128 {
                    cpu.memory[Int(dtaAddress) + i] = byte
                }
            }
            
            // FCBの現在のレコード位置を更新
            let newRecord = (currentRecord + 1) % 128
            cpu.memory[Int(fcbAddress) + 0x20] = newRecord
            
            // エクステントの更新（必要な場合）
            if newRecord == 0 {
                cpu.memory[Int(fcbAddress) + 12] = currentExtent + 1
            }
            
            cpu.a = 0x00  // 成功コード
            cpu.setFlag(.carry, value: false)  // 成功フラグ
        } else {
            // 読み込み失敗またはEOF
            cpu.a = 0x01  // EOFコード
            cpu.setFlag(.carry, value: true)  // エラーフラグ
        }
        
        return true
    }
    
    // MARK: - テキスト表示関連のBIOS関数
    
    /// コンソール出力 (BIOS関数 0x04)
    internal func handleConsoleOut(cpu: Z80, screen: PC88Screen) -> Bool {
        // 出力する文字コードを取得
        let charCode = cpu.e
        
        // 特殊文字の処理
        if charCode == 0x0D { // CR
            // カーソルを行の先頭に移動
            screen.setCursorX(0)
            print("BIOS: コンソール出力 - CR")
        } else if charCode == 0x0A { // LF
            // カーソルを次の行に移動
            let y = screen.getCursorY() + 1
            screen.setCursorY(y)
            // 必要に応じてスクロール
            if y >= screen.getTextRows() {
                screen.scrollUp(1)
                screen.setCursorY(Int(screen.getTextRows()) - 1)
            }
            print("BIOS: コンソール出力 - LF")
        } else if charCode == 0x08 { // BS
            // カーソルを一つ戻す
            let x = screen.getCursorX()
            if x > 0 {
                screen.setCursorX(x - 1)
            }
            print("BIOS: コンソール出力 - BS")
        } else {
            // 通常の文字を表示
            screen.putChar(charCode)
            print("BIOS: コンソール出力 - 文字: \(Character(UnicodeScalar(charCode)))")
        }
        
        return true
    }
    
    /// 文字列出力 (BIOS関数 0x09)
    internal func handlePrintString(cpu: Z80, screen: PC88Screen) -> Bool {
        // 文字列のアドレスを取得
        let stringAddress = cpu.getDE()
        
        // 文字列を出力（$で終了）
        var i: UInt16 = 0
        while true {
            let charCode = cpu.memory[Int(stringAddress + i)]
            if charCode == 0x24 { // '$'で終了
                break
            }
            
            // 文字を出力
            cpu.e = charCode
            _ = handleConsoleOut(cpu: cpu, screen: screen)
            
            i += 1
            if i > 255 { // 安全のため最大長を制限
                break
            }
        }
        
        print("BIOS: 文字列出力完了")
        return true
    }
    
    /// カーソル位置設定 (BIOS関数 0x43)
    internal func handleSetCursorPosition(cpu: Z80, screen: PC88Screen) -> Bool {
        // カーソル位置を取得
        let x = cpu.d
        let y = cpu.e
        
        // 画面の範囲内かチェック
        if x < screen.getTextColumns() && y < screen.getTextRows() {
            // カーソル位置を設定
            screen.setCursorX(Int(x))
            screen.setCursorY(Int(y))
            print("BIOS: カーソル位置設定 - X:\(x) Y:\(y)")
            return true
        } else {
            print("BIOS: カーソル位置設定エラー - 範囲外 X:\(x) Y:\(y)")
            return false
        }
    }
    
    /// 画面クリア (BIOS関数 0x45)
    public func handleClearScreen(cpu: Z80, screen: PC88Screen) -> Bool {
        // 画面をクリア
        screen.clearScreen()
        print("BIOS: 画面クリア")
        return true
    }
    
    /// カーソル位置取得 (BIOS関数 0x44)
    internal func handleGetCursorPosition(cpu: Z80, screen: PC88Screen) -> Bool {
        // 現在のカーソル位置を取得
        let x = screen.getCursorX()
        let y = screen.getCursorY()
        
        // レジスタに設定
        cpu.d = UInt8(x)
        cpu.e = UInt8(y)
        
        print("BIOS: カーソル位置取得 - X:\(x) Y:\(y)")
        return true
    }
}
