import Foundation

// Z80Coreの機能を実装するクラス
// Z80クラスの機能を拡張するヘルパークラス
public class Z80Core {
    // Z80クラスへの参照
    private weak var z80: Z80?
    
    // 初期化
    public init(z80: Z80) {
        self.z80 = z80
    }
    // OPNA音源更新フラグ
    var needsOPNAUpdate: Bool = false
    // 割り込み関連フラグ
    
    // 交換用レジスタアクセサメソッドはメインクラスで実装
    
    // IXとIYレジスタのアクセスメソッドはメインクラスに定義済み
    
    // PMD固有の状態追跡
    var inOpnset46: Bool = false  // opnset46ルーチン内かどうか
    var opnset46State: Int = 0    // opnset46ルーチンの実行状態
    
    // PPIレジスタ
    var ppiRegisters = [UInt8](repeating: 0, count: 4)  // PPIレジスタ
    
    // PMD処理関連
    var currentPortBase: UInt8 = 0x44  // 現在のポートベース (44h or 46h)
    var currentRegAddr = [UInt8: UInt8]()  // 各ポートの現在のレジスタアドレス
    var ports44_45 = [UInt8: UInt8]()  // ポート44/45に対する書き込み値
    var ports46_47 = [UInt8: UInt8]()  // ポート46/47に対する書き込み値
    
    // ポートマッピング
    var portMap = [Int: Int]()  // 物理ポート番号から論理ポート番号へのマッピング
    
    // 特殊アドレス検出
    var sel44Address: Int = -1  // sel44ルーチンのアドレス
    var sel46Address: Int = -1  // sel46ルーチンのアドレス
    
    // OPNAビジーフラグシミュレーション
    private var port44Busy: Bool = false
    private var port44BusyCounter: Int = 0
    private var port46Busy: Bool = false
    private var port46BusyCounter: Int = 0
    
    // ボードタイプとポートマッピング
    var currentBoardType: String = "pc8801_23"
    
    // 拡張リセット処理
    public func reset() {
        // PMD固有の状態をリセット
        inOpnset46 = false
        opnset46State = 0
        
        // PMD処理関連のリセット
        currentPortBase = 0x44
        currentRegAddr = [:]
        ports44_45 = [:]
        ports46_47 = [:]
        
        // PPIレジスタのリセット
        ppiRegisters = [UInt8](repeating: 0, count: 4)
        
        // OPNAビジーフラグシミュレーションのリセット
        port44Busy = false
        port44BusyCounter = 0
        port46Busy = false
        port46BusyCounter = 0
        
        // ボードタイプを検出
        detectBoardType()
        
        // リセット完了ログ
        z80?.addDebugLog("Z80Core リセット完了")
    }
    
    // プログラムメモリにデータをロードする拡張処理
    public func loadProgram(at address: Int, data: Data) {
        // メインのloadMemory関数を利用する
        z80?.loadMemory(data: data, offset: address)
        
        // ボードタイプの再検出
        detectBoardType()
        
        // ロード完了ログ
        z80?.addDebugLog("Z80Core: \(data.count)バイトのデータを\(String(format: "0x%04X", address))にロードしました")
    }
    
    // ボードタイプに応じたポートマッピングを設定する
    public func setPortMapping(forBoard boardType: String) {
        currentBoardType = boardType
        
        switch boardType {
        case "pc8801_23":
            // PC8801-23（第1世代FM音源ボード）のポートマッピング
            portMap[0x44] = 0xA8  // 表FM音源アドレスレジスタ
            portMap[0x45] = 0xA9  // 表FM音源データレジスタ
            portMap[0x46] = 0xAC  // 裏FM音源アドレスレジスタ
            portMap[0x47] = 0xAD  // 裏FM音源データレジスタ
            addDebugLog("PC8801-23ボード（旧OPN）ポートマッピング設定: 44h→A8h, 45h→A9h, 46h→ACh, 47h→ADh")
        case "pc8801_24":
            // PC8801-24（第2世代FM音源ボード）のポートマッピング
            portMap[0x44] = 0xA8  // 表FM音源アドレスレジスタ
            portMap[0x45] = 0xA9  // 表FM音源データレジスタ
            portMap[0x46] = 0xAA  // 裏FM音源アドレスレジスタ
            portMap[0x47] = 0xAB  // 裏FM音源データレジスタ
            addDebugLog("PC8801-24ボード（新OPN）ポートマッピング設定: 44h→A8h, 45h→A9h, 46h→AAh, 47h→ABh")
        default: // 他の全てのボードタイプ
            // デフォルトのポートマッピング
            portMap[0x44] = 0xA8  // 表FM音源アドレスレジスタ
            portMap[0x45] = 0xA9  // 表FM音源データレジスタ
            portMap[0x46] = 0xAA  // 裏FM音源アドレスレジスタ
            portMap[0x47] = 0xAB  // 裏FM音源データレジスタ
            addDebugLog("デフォルトポートマッピング設定: 44h→A8h, 45h→A9h, 46h→AAh, 47h→ABh")
        }
    }
    
    // ボードタイプを検出する
    public func detectBoardType() {
        // デフォルトはPC8801-23（旧OPN）
        setPortMapping(forBoard: "pc8801_23")
    }
    
    // レジスタアクセスヘルパーはメインクラスに定義済み
    
    // setIxとsetIy関数はメインクラスに定義済み
    
    // デバッグ関連プロパティ
    var debugMode: Bool = true
    var debugLog: [String] = []
    
    // デバッグログを追加
    func addDebugLog(_ message: String) {
        if debugMode {
            debugLog.append(message)
            // ログが大きくなりすぎないように制限
            if debugLog.count > 1000 {
                debugLog.removeFirst(500)
            }
            
            // メインのZ80クラスにもログを追加
            z80?.addDebugLog("[Z80Core] " + message)
        }
    }
}

// BoardTypeは別ファイルで定義されています
