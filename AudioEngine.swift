// 完全に再設計された停止メソッド
func stop() {
    print("🔊 オーディオエンジン停止開始")
    
    // 現在の状態をログ出力
    print("🔊 停止前の状態: isRunning=\(isRunning), playerNode.isPlaying=\(playerNode?.isPlaying ?? false), engine.isRunning=\(engine.isRunning)")
    
    // 再生状態をオフに（最初に設定）
    isRunning = false
    
    // メインスレッドで強制的に実行
    DispatchQueue.main.async { [self] in
        // 1. プレイヤーノードを強制的に停止・解放
        if let player = playerNode {
            player.pause()
            player.stop()
            player.reset()
            print("🔊 プレイヤーノード停止完了")
            
            // すべてのバッファをキャンセル
            player.reset()
            
            // エンジンから切り離す（重要）
            engine.detach(player)
            playerNode = nil
        }
        
        // 2. エンジンを完全に停止
        engine.stop()
        
        // 3. すべてのノードを切断
        engine.reset()
        
        // 4. アプリケーションレベルの処理
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("⚠️ オーディオセッション停止エラー: \(error)")
        }
        
        // 5. 音源エンジンをリセット
        ssgEngine = SSGEngine(sampleRate: sampleRate, cpuClock: cpuClock)
        fmEngine = FMEngine(sampleRate: sampleRate, fmClock: cpuClock)
        rhythmEngine = RhythmEngine(sampleRate: sampleRate)
        adpcmEngine = ADPCMEngine(sampleRate: sampleRate, adpcmClock: cpuClock)
        
        print("🔊 オーディオエンジン完全停止・リセット完了")
    }
}

private func completeStop() {
    // 現在のプレイヤーノードを停止
    if let player = playerNode {
        // 再生中なら停止（強制的に実行）
        player.stop()
        print("🔊 プレイヤーノード停止")
        
        // バッファをリセット
        player.reset()
        
        // エンジンから切り離す
        engine.detach(player)
        playerNode = nil
        print("🔊 プレイヤーノード解放")
    }
    
    // エンジンを停止
    do {
        // 状態にかかわらず強制的に停止
        engine.stop()
        print("🔊 AVAudioEngine停止")
        
        // エンジンを完全にリセット
        engine.reset()
        print("🔊 AVAudioEngineリセット完了")
        
        // オーディオセッションを非アクティブにする
        try AVAudioSession.sharedInstance().setActive(false)
        print("🔊 オーディオセッション非アクティブ化")
    } catch {
        print("⚠️ オーディオエンジン停止エラー: \(error)")
    }
}

func recreateEngine() {
    // 古いエンジンを破棄
    engine.stop()
    engine.reset()
    
    // 新しいエンジンを作成
    engine = AVAudioEngine()
    setupEngine()
}

func applicationWillResignActive() {
    // アプリがバックグラウンドに移行する際に強制停止
    stop()
}

// 停止ボタンのデバッグ用メソッド
func debugStopButton() {
    print("🔍 停止ボタン押下検出！現在の状態:")
    print("- isRunning: \(isRunning)")
    print("- engine.isRunning: \(engine.isRunning)")
    print("- playerNode?.isPlaying: \(playerNode?.isPlaying ?? false)")
    
    // 強制停止試行
    stop()
    
    // 状態確認
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        guard let self = self else { return }
        print("🔍 停止処理後の状態:")
        print("- isRunning: \(self.isRunning)")
        print("- engine.isRunning: \(self.engine.isRunning)")
        print("- playerNode?.isPlaying: \(self.playerNode?.isPlaying ?? false)")
    }
}

// 強制停止用のメソッド追加
func forceStop() {
    print("🔊 オーディオエンジン強制停止開始")
    
    // すべてのフラグをオフに
    isRunning = false
    
    // AVAudioEngineを直接停止
    if engine.isRunning {
        engine.stop()
        print("🔊 AVAudioEngine強制停止")
    }
    
    // プレイヤーノードを強制停止
    if let player = playerNode {
        if player.isPlaying {
            player.stop()
            print("🔊 プレイヤーノード強制停止")
        }
    }
    
    // オーディオセッション終了
    do {
        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        print("🔊 オーディオセッション強制終了")
    } catch {
        print("⚠️ オーディオセッション終了エラー: \(error)")
    }
    
    // 音源エンジンのリセット
    resetAllEngines()
    
    print("🔊 オーディオエンジン強制停止完了")
} 