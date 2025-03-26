import Foundation
import AVFoundation

/// OPNAのリズム音色サンプルを管理するクラス
class RhythmSample {
    /// サンプル名
    var name: String
    /// サンプルデータ
    var sampleData: [Float] = []
    /// サンプルレート
    var sampleRate: Double = 44100
    
    /// 初期化
    init(name: String) {
        self.name = name
    }
    
    /// WAVファイルを読み込む
    func loadWAVFile(from url: URL) -> Bool {
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let format = audioFile.processingFormat
            let frameCount = UInt32(audioFile.length)
            
            self.sampleRate = format.sampleRate
            
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                print("PCMバッファの作成に失敗: \(name)")
                return false
            }
            
            try audioFile.read(into: buffer)
            
            // モノラルデータとして読み込む
            if let floatChannelData = buffer.floatChannelData {
                let channelData = floatChannelData[0]
                sampleData = Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
                print("WAVファイルを読み込みました: \(name), サンプル数: \(sampleData.count)")
                return true
            } else {
                print("チャンネルデータの取得に失敗: \(name)")
                return false
            }
        } catch {
            print("WAVファイルの読み込みに失敗: \(name), エラー: \(error)")
            return false
        }
    }
}

/// リズム音色サンプルを管理するクラス
class RhythmSampleManager {
    /// リズムサンプル（名前をキーとする）
    private var samples: [String: RhythmSample] = [:]
    
    /// 初期化
    init() {
        loadSamplesFromBundle()
    }
    
    /// バンドルからリズム音色サンプルを読み込む
    func loadSamplesFromBundle() -> Bool {
        var success = true
        let rhythmFiles = ["2608_bd", "2608_sd", "2608_top", "2608_hh", "2608_tom", "2608_rim"]
        
        for rhythmName in rhythmFiles {
            if let rhythmURL = Bundle.main.url(forResource: rhythmName, withExtension: "wav") {
                let sample = RhythmSample(name: rhythmName)
                if sample.loadWAVFile(from: rhythmURL) {
                    samples[rhythmName] = sample
                } else {
                    success = false
                }
            } else {
                print("リズム音色ファイルが見つかりません: \(rhythmName).wav")
                success = false
            }
        }
        
        return success
    }
    
    /// 指定した名前のリズムサンプルを取得
    func getSample(name: String) -> RhythmSample? {
        return samples[name]
    }
}
