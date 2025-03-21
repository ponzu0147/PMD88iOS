import Foundation
import AVFoundation

class AudioEngine {
    private let engine = AVAudioEngine()
    private var playerNode: AVAudioPlayerNode?
    private var isRunning = false
    
    private weak var z80: Z80?
    private var ssgRegisters: [UInt8] = Array(repeating: 0, count: 16)
    
    private struct SSGChannel {
        var frequency: Float = 0
        var volume: Float = 0
        var phase: Float = 0
        var enabled: Bool = false
    }
    private var channels: [SSGChannel] = Array(repeating: SSGChannel(), count: 3)
    private let channelsLock = NSLock() // スレッドセーフのためのロック
    
    private let sampleRate: Float = 44100
    private let cpuClock: Float = 8_000_000
    private let bufferDuration: Float = 0.02
    private var bufferQueue: [AVAudioPCMBuffer] = []
    private let bufferCount = 3
    
    init(z80: Z80) {
        self.z80 = z80
        setupEngine()
        print("🔊 AudioEngine初期化: channels.count = \(channels.count)")
    }
    
    private func setupEngine() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            try session.setActive(true)
            print("🔊 AudioSession設定完了")
        } catch {
            print("❌ AudioSessionエラー: \(error)")
        }
        
        playerNode = AVAudioPlayerNode()
        if let player = playerNode {
            engine.attach(player)
            let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1)!
            engine.connect(player, to: engine.mainMixerNode, format: format)
            print("🔊 PlayerNode接続完了")
        }
    }
    
    private func generateSSGBuffer() -> AVAudioPCMBuffer? {
        let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1)!
        let frameCount = AVAudioFrameCount(sampleRate * bufferDuration)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            print("❌ バッファ作成失敗")
            return nil
        }
        
        if let channelData = buffer.floatChannelData?[0] {
            let samples = Int(frameCount)
            let timeStep: Float = 1.0 / sampleRate
            
            channelsLock.lock() // channelsへのアクセスを保護
            defer { channelsLock.unlock() }
            
            guard channels.count >= 3 else {
                print("❌ channels配列のサイズが不足: \(channels.count)")
                return nil
            }
            
            for i in 0..<samples {
                var sample: Float = 0
                
                for ch in 0..<3 {
                    if ch < channels.count {
                        if channels[ch].enabled && channels[ch].frequency > 0 {
                            channels[ch].phase += timeStep * channels[ch].frequency
                            if channels[ch].phase >= 1.0 {
                                channels[ch].phase -= 1.0
                            }
                            
                            let value: Float = channels[ch].phase < 0.5 ? 1.0 : -1.0
                            sample += value * channels[ch].volume
                        }
                    } else {
                        print("❌ チャンネルインデックス範囲外: ch=\(ch), channels.count=\(channels.count)")
                    }
                }
                
                channelData[i] = max(min(sample / 3.0, 1.0), -1.0) * 0.7
            }
            
            buffer.frameLength = frameCount
        }
        
        return buffer
    }
    
    public func updateSSGState() {
        if let z80 = z80 {
            for i in 0..<16 {
                ssgRegisters[i] = z80.opnaRegisters[i]
            }
            
            channelsLock.lock() // channelsへの書き込みを保護
            defer { channelsLock.unlock() }
            
            guard channels.count >= 3 else {
                print("❌ updateSSGStateでchannelsサイズ不足: \(channels.count)")
                return
            }
            
            for ch in 0..<3 {
                let freqLow = UInt16(ssgRegisters[ch * 2])
                let freqHigh = UInt16(ssgRegisters[ch * 2 + 1] & 0x0F)
                let period = (freqHigh << 8) | freqLow
                
                channels[ch].frequency = period > 0 ? cpuClock / (32.0 * Float(period & 0xFFF)) : 0
                channels[ch].volume = Float(ssgRegisters[8 + ch] & 0x0F) / 15.0
                channels[ch].enabled = (ssgRegisters[7] & (1 << ch)) == 0
                
                if channels[ch].enabled {
                    print("🔊 CH\(ch): 周波数=\(channels[ch].frequency)Hz, 音量=\(channels[ch].volume)")
                } else {
                    print("🔊 CH\(ch): 無効")
                }
            }
        } else {
            print("⚠️ Z80参照がnilです")
        }
    }
    
    func start() {
        completeStop()
        
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            try session.setActive(true)
            
            playerNode = AVAudioPlayerNode()
            guard let player = playerNode else {
                print("❌ PlayerNode作成失敗")
                return
            }
            
            engine.attach(player)
            let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1)!
            engine.connect(player, to: engine.mainMixerNode, format: format)
            
            try engine.start()
            print("🔊 エンジン開始")
            
            bufferQueue.removeAll()
            for i in 0..<bufferCount {
                updateSSGState()
                if let buffer = generateSSGBuffer() {
                    bufferQueue.append(buffer)
                    player.scheduleBuffer(buffer)
                    print("🔊 バッファ\(i)スケジュール完了")
                }
            }
            
            player.play()
            isRunning = true
            print("🔊 再生開始")
            
            DispatchQueue.global().async { [weak self] in
                guard let self = self else { return }
                while self.isRunning {
                    if let z80 = self.z80 {
                        _ = z80.step()
                    }
                    
                    self.scheduleNextBuffer()
                    Thread.sleep(forTimeInterval: TimeInterval(self.bufferDuration * 0.5))
                }
            }
            
            print("🔊 オーディオ開始")
        } catch {
            print("❌ オーディオ開始エラー: \(error)")
        }
    }
    
    private func scheduleNextBuffer() {
        guard isRunning, let player = playerNode else { return }
        
        updateSSGState()
        if let buffer = generateSSGBuffer() {
            bufferQueue.append(buffer)
            player.scheduleBuffer(buffer)
            print("🔊 バッファ追加 (キュー数: \(bufferQueue.count))")
            while bufferQueue.count > bufferCount {
                bufferQueue.removeFirst()
            }
        } else {
            print("❌ バッファ生成失敗")
        }
    }
    
    func stop() {
        if let player = playerNode {
            player.pause()
        }
        isRunning = false
        print("🔊 オーディオ停止")
    }
    
    private func completeStop() {
        if let player = playerNode {
            player.stop()
            player.reset()
            engine.detach(player)
        }
        engine.stop()
        isRunning = false
        bufferQueue.removeAll()
        print("🔊 オーディオ完全停止")
    }
}
