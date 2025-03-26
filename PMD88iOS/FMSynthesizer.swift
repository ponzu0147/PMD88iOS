//
//  FMSynthesizer.swift
//  PMD88iOS
//
//  Created by 越川将人 on 2025/03/22.
//

import Foundation
import AVFoundation

class FMSynthesizer {
    private let audioEngine = AVAudioEngine()
    private let sourceNode: AVAudioSourceNode
    private let fmGenerator: FMGenerator
    
    // サンプルレート
    private let sampleRate: Double = 44100.0
    
    init() {
        // FM合成エンジンの初期化
        fmGenerator = FMGenerator(sampleRate: Float(sampleRate))
        
        // オーディオソースノードの作成
        let generator = fmGenerator // ローカル変数に保存して、クロージャでselfを使わないようにする
        sourceNode = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            
            // 各フレームでFM合成エンジンからサンプルを生成
            for frame in 0..<Int(frameCount) {
                // FM合成エンジンからサンプルを取得
                let sample = generator.generateSample()
                
                // 全てのチャンネルに同じ値を設定（モノラル→ステレオ変換）
                for buffer in ablPointer {
                    let bufferPointer = UnsafeMutableBufferPointer<Float>(
                        start: buffer.mData?.assumingMemoryBound(to: Float.self),
                        count: Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                    )
                    bufferPointer[frame] = sample
                }
            }
            
            return noErr
        }
        
        // オーディオエンジンの設定
        setupAudioEngine()
    }
    
    private func setupAudioEngine() {
        // ソースノードをエンジンに接続
        audioEngine.attach(sourceNode)
        
        // 出力フォーマットの設定
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        
        // ソースノードをメインミキサーに接続
        audioEngine.connect(sourceNode, to: audioEngine.mainMixerNode, format: format)
        
        // エンジンの準備
        do {
            try audioEngine.start()
        } catch {
            print("オーディオエンジンの起動に失敗しました: \(error.localizedDescription)")
        }
    }
    
    // レジスタを更新してFM音源のパラメータを変更
    func updateRegisters(registers: [UInt8]) {
        fmGenerator.updateRegisters(registers)
    }
    
    // 特定のノートを演奏（簡易的な実装）
    func playNote(channel: Int, note: Int, velocity: Int) {
        // MIDIノート番号からF-NumberとBlockを計算
        let (fnum, block) = calculateFnumAndBlock(note: note)
        
        // レジスタ更新用の配列
        var newRegisters = [UInt8](repeating: 0, count: 0x100)
        
        // チャンネルのグループとオフセットを計算
        let group = channel >= 3 ? 1 : 0
        let offset = channel % 3
        
        // F-NumberとBlockを設定
        let fnumLowReg = FMRegisterOffsets.fnum_low + offset
        let fnumHighBlockReg = FMRegisterOffsets.fnum_high_block + offset
        
        newRegisters[fnumLowReg + group * 0x100] = UInt8(fnum & 0xFF)
        newRegisters[fnumHighBlockReg + group * 0x100] = UInt8((block << 3) | (fnum >> 8))
        
        // アルゴリズムとフィードバックを設定（例: アルゴリズム0、フィードバック0）
        let fbAlgReg = FMRegisterOffsets.feedback_algorithm + offset
        newRegisters[fbAlgReg + group * 0x100] = 0x00  // アルゴリズム0、フィードバック0
        
        // 各オペレータのパラメータを設定（簡易的な例）
        for op in 0..<4 {
            let opOffset = calculateOperatorOffset(channel, op)
            
            // デチューン・マルチプル
            newRegisters[FMRegisterOffsets.detune_multiple + opOffset] = 0x01  // マルチプル=1
            
            // トータルレベル（ベロシティに応じて調整）
            let tl = UInt8(max(0, min(127, 127 - velocity)))
            newRegisters[FMRegisterOffsets.totalLevel + opOffset] = tl
            
            // アタックレート
            newRegisters[FMRegisterOffsets.keyScale_attackRate + opOffset] = 0x1F  // 高速アタック
            
            // ディケイレート
            newRegisters[FMRegisterOffsets.decayRate + opOffset] = 0x05
            
            // サスティンレート
            newRegisters[FMRegisterOffsets.sustainRate + opOffset] = 0x01
            
            // サスティンレベル・リリースレート
            newRegisters[FMRegisterOffsets.sustainLevel_releaseRate + opOffset] = 0x11
        }
        
        // レジスタを更新
        fmGenerator.updateRegisters(newRegisters)
        
        // キーオン
        newRegisters[FMRegisterOffsets.keyOn] = UInt8(0xF0 | channel)  // すべてのオペレータをキーオン
        fmGenerator.updateRegisters(newRegisters)
    }
    
    // ノートオフ
    func stopNote(channel: Int) {
        var newRegisters = [UInt8](repeating: 0, count: 0x100)
        newRegisters[FMRegisterOffsets.keyOn] = UInt8(channel)  // キーオフ
        fmGenerator.updateRegisters(newRegisters)
    }
    
    // MIDIノート番号からF-NumberとBlockを計算
    private func calculateFnumAndBlock(note: Int) -> (Int, Int) {
        // A4（ノート番号69）を基準音（440Hz）とする
        let baseNote = 69
        let baseFreq = 440.0
        
        // ノート番号から周波数を計算（平均律）
        let semitones = Double(note - baseNote)
        let freq = baseFreq * pow(2.0, semitones / 12.0)
        
        // 周波数からF-NumberとBlockを計算
        let clockValue = Double(FMConstants.baseClock)
        let scaleFactor = 144.0 * pow(2.0, 20.0)
        var fnum = Int(freq * scaleFactor / clockValue)
        var block = 0
        
        // Blockの調整（F-Numberが適切な範囲に収まるように）
        while fnum > 0x3FF {
            fnum >>= 1
            block += 1
            if block >= 7 {
                block = 7
                fnum = min(fnum, 0x3FF)
                break
            }
        }
        
        return (fnum, block)
    }
    
    // オペレータのレジスタオフセットを計算
    private func calculateOperatorOffset(_ channel: Int, _ op: Int) -> Int {
        let group = channel >= 3 ? 1 : 0
        let chOffset = channel % 3
        let opOffset = op * 4 + chOffset
        return opOffset + group * 0x100
    }
}
