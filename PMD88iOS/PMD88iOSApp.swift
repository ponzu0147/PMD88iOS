////
////  testApp.swift
////  test
////
////  Created by 越川将人 on 2025/03/21.
////
//
//import SwiftUI
//
//@main
//struct testApp: App {
//    var body: some Scene {
//        WindowGroup {
//            ContentView()
//        }
//    }
//}
//

import SwiftUI
import AVFoundation

@main
struct PMD88iOSApp: App {
    // PC88Coreインスタンスをアプリ全体で共有
    @StateObject private var pc88 = PC88Core()
    
    // アプリ起動時の初期化処理
    init() {
        // オーディオセッションの初期設定
        setupAudioSession()
    }
    
    // オーディオセッション設定
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // オーディオセッションカテゴリをPlaybackに設定（サイレントモード時も音を鳴らせる）
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
            
            // システム音量を確認
            print("📱 アプリ起動時のシステム音量: \(audioSession.outputVolume)")
            
            // もし音量が小さい場合は警告を表示
            if audioSession.outputVolume < 0.1 {
                print("⚠️ 警告: システム音量が非常に小さいです。デバイスの音量を上げてください。")
            }
            
            print("📱 アプリ起動時のオーディオセッション設定完了")
        } catch {
            print("📱 オーディオセッション設定エラー: \(error.localizedDescription)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(pc88)
        }
    }
}
