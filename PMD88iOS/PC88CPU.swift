// PC88CPU.swift
import Foundation

// CPU処理を行うクラス
class PC88CPU: ObservableObject {
    // 各レジスタを格納する構造体
    struct Registers {
        var a: UInt8 = 0
        var b: UInt8 = 0
        var c: UInt8 = 0
        var d: UInt8 = 0
        var e: UInt8 = 0
        var h: UInt8 = 0
        var l: UInt8 = 0
        var sp: UInt16 = 0
        var pc: UInt16 = 0
        var f: UInt8 = 0 // フラグレジスタ
    }
    
    // メモリマップ
    var memory: [UInt8] = Array(repeating: 0, count: 0xFFFF + 1)
    
    // レジスタ構造体
    var registers = Registers()
    
    // 実行状態
    var isRunning = false
    
    // 初期化処理
    init(){
        // レジスタを初期化
        registers.a = 0
        registers.b = 0
        registers.c = 0
        registers.d = 0
        registers.e = 0
        registers.h = 0
        registers.l = 0
        registers.sp = 0
        registers.pc = 0
        registers.f = 0
        
        // メモリを0で初期化
        for i in 0..<memory.count {
            memory[i] = 0x00
        }
    }
    
    // 1バイトの命令を読み込む
    func fetchInstruction() -> UInt8 {
        let instruction = readMemory(at: registers.pc)
        registers.pc += 1
        return instruction
    }
    
    // メモリを読み込む
    func readMemory(at address: UInt16) -> UInt8 {
        return memory[Int(address)]
    }
    
    // メモリに書き込む
    func writeMemory(at address: UInt16, value: UInt8) {
        memory[Int(address)] = value
    }
    
    // 命令を実行する
    func executeInstruction(_ instruction: UInt8) {
        // 命令を処理する
        print("未実装命令：0x\(String(instruction, radix: 16).uppercased())")
        // ... 命令に対応したコードを実装する ...
    }
    
    // プログラムの実行
    func run() {
        isRunning = true
        while isRunning {
            let instruction = fetchInstruction()
            executeInstruction(instruction)
        }
    }

    // プログラムを停止する
    func stop(){
        isRunning = false
    }
}
