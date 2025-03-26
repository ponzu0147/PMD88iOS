//
//  ContentView.swift
//  PMD88iOS
//
//  Created on 2022/01/04.
//

import SwiftUI
import UniformTypeIdentifiers
import Combine

// ヘッダービュー
struct HeaderView: View {
    var status: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PMD88 Music Player")
                .font(.title)
                .padding(.bottom, 8)
            
            Text("ステータス: \(status)")
                .font(.headline)
                .padding(.bottom, 8)
        }
    }
}

// コントロールパネルビュー
struct ControlPanelView: View {
    @Binding var isPMDPlaying: Bool
    @Binding var playbackState: PlaybackState
    @Binding var isFilePickerPresented: Bool
    @EnvironmentObject var pc88: PC88Core
    var selectedFile: URL?
    var onPlayPause: () -> Void
    
    // 再生状態に応じたボタンテキストを取得
    private var buttonText: String {
        switch playbackState {
        case .stopped:
            return "リセット"  // 停止中はリセットボタン
        case .resetting:
            return "再生"     // リセット中は再生ボタン
        case .playing:
            return "停止"     // 再生中は停止ボタン
        }
    }
    
    // D88データが取得されているかどうかを確認
    private var isD88DataAvailable: Bool {
        return pc88.d88Data != nil && pc88.d88Data!.count > 0
    }
    
    // 再生状態に応じたボタンの色を取得
    private var buttonColor: Color {
        switch playbackState {
        case .stopped:
            return Color.orange  // 停止中はオレンジ色
        case .resetting:
            return Color.green   // リセット中は緑色
        case .playing:
            return Color.red     // 再生中は赤色
        }
    }
    
    var body: some View {
        HStack(spacing: 20) {
            // PMD88音楽再生/停止/リセットボタン
            Button(action: onPlayPause) {
                Text(buttonText)
                    .frame(minWidth: 100)
                .padding()
                    .background(isD88DataAvailable ? buttonColor : Color.gray)
                .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .disabled(!isD88DataAvailable) // D88データが取得されるまで非活性化
            
            // ファイル選択ボタン
            Button(action: {
                isFilePickerPresented = true
            }) {
                Text("D88ファイル選択")
                    .frame(minWidth: 100)
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .disabled(isPMDPlaying)
            
            // 選択ファイル名表示
            if let selectedFile = selectedFile {
                Text(selectedFile.lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.bottom, 16)
    }
}

// FMチャンネル情報ビュー
struct FMChannelInfoView: View {
    var channelInfo: [Int: ChannelInfo]
    let activeColor: Color
    let inactiveColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("FM音源チャンネル")
                .font(.headline)
                .padding(.bottom, 4)
            
            // ヘッダー行
            ChannelHeaderRow()
            
            // FMチャンネルの状態表示
            ForEach(0..<6) { i in
                if let info = channelInfo[i] {
                    ChannelInfoRow(channelName: "FM\(i+1)", info: info, activeColor: activeColor, inactiveColor: inactiveColor)
                } else {
                    EmptyChannelInfoRow(channelName: "FM\(i+1)", inactiveColor: inactiveColor)
                }
            }
        }
        .padding(.bottom, 16)
        .padding(.horizontal, 8)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}

// SSGチャンネル情報ビュー
struct SSGChannelInfoView: View {
    var channelInfo: [Int: ChannelInfo]
    let activeColor: Color
    let inactiveColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SSG音源チャンネル")
                .font(.headline)
                .padding(.bottom, 4)
            
            // ヘッダー行
            ChannelHeaderRow()
            
            // SSGチャンネルの状態表示
            ForEach(0..<3) { i in
                if let info = channelInfo[i] {
                    ChannelInfoRow(channelName: "SSG\(i+1)", info: info, activeColor: activeColor, inactiveColor: inactiveColor)
                } else {
                    EmptyChannelInfoRow(channelName: "SSG\(i+1)", inactiveColor: inactiveColor)
                }
            }
        }
        .padding(.bottom, 16)
        .padding(.horizontal, 8)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}

// チャンネルヘッダー行
struct ChannelHeaderRow: View {
    var body: some View {
        HStack {
            Text("CH")
                .frame(width: 40, alignment: .leading)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("状態")
                .frame(width: 30, alignment: .leading)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("音名")
                .frame(width: 50, alignment: .leading)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("アドレス")
                .frame(width: 80, alignment: .leading)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("音色")
                .frame(width: 50, alignment: .leading)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("音量")
                .frame(width: 50, alignment: .leading)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// チャンネル情報行
struct ChannelInfoRow: View {
    var channelName: String
    var info: ChannelInfo
    let activeColor: Color
    let inactiveColor: Color
    
    var body: some View {
        HStack {
            Text(channelName)
                .frame(width: 40, alignment: .leading)
                .fontWeight(.medium)
            
            Circle()
                .fill(info.isPlaying ? activeColor : (info.isActive ? Color.yellow : inactiveColor))
                .frame(width: 12, height: 12)
                .padding(.trailing, 18)
            
            Text(info.note)
                .frame(width: 50, alignment: .leading)
                .fontWeight(info.isPlaying ? .bold : .regular)
            
            Text("0x\(String(format:"%04X", info.playingAddress))")
                .frame(width: 80, alignment: .leading)
                .font(.system(.body, design: .monospaced))
            
            Text("\(info.instrument)")
                .frame(width: 50, alignment: .leading)
            
            Text("\(info.volume)")
                .frame(width: 50, alignment: .leading)
        }
        .padding(.vertical, 2)
        .background(info.isPlaying ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(4)
    }
}

// 空のチャンネル情報行
struct EmptyChannelInfoRow: View {
    var channelName: String
    let inactiveColor: Color
    
    var body: some View {
        HStack {
            Text(channelName)
                .frame(width: 40, alignment: .leading)
            
            Circle()
                .fill(inactiveColor)
                .frame(width: 12, height: 12)
                .padding(.trailing, 18)
            
            Text("---")
                .frame(width: 50, alignment: .leading)
            
            Text("------")
                .frame(width: 80, alignment: .leading)
                .font(.system(.body, design: .monospaced))
            
            Text("--")
                .frame(width: 50, alignment: .leading)
            
            Text("--")
                .frame(width: 50, alignment: .leading)
        }
        .padding(.vertical, 2)
        .foregroundColor(.gray)
    }
}

// リズム・ADPCM状態表示ビュー
struct RhythmADPCMView: View {
    var isRhythmActive: Bool
    var isADPCMActive: Bool
    let activeColor: Color
    let inactiveColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("リズム・ADPCM音源")
                .font(.headline)
                .padding(.bottom, 4)
            
            HStack {
                Text("リズム:")
                    .frame(width: 50, alignment: .leading)
                
                Circle()
                    .fill(isRhythmActive ? activeColor : inactiveColor)
                    .frame(width: 12, height: 12)
                
                Text(isRhythmActive ? "演奏中" : "停止中")
            }
            .padding(.vertical, 2)
            
            HStack {
                Text("ADPCM:")
                    .frame(width: 50, alignment: .leading)
                
                Circle()
                    .fill(isADPCMActive ? activeColor : inactiveColor)
                    .frame(width: 12, height: 12)
                
                Text(isADPCMActive ? "演奏中" : "停止中")
            }
            .padding(.vertical, 2)
        }
        .padding(.bottom, 16)
    }
}

// PMD88ワークエリアモニタービュー
struct PMDWorkAreaMonitorView: View {
    var songDataAddress: String
    var stepCount: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PMD88ワークエリアモニター")
                .font(.headline)
                .padding(.bottom, 4)
            
            // モニター表示
            HStack {
                Text("曲データアドレス:")
                    .frame(width: 120, alignment: .leading)
                Text(songDataAddress)
            }
            .padding(.vertical, 2)
            
            HStack {
                Text("処理ステップ数:")
                    .frame(width: 120, alignment: .leading)
                Text("\(stepCount)")
            }
            .padding(.vertical, 2)
        }
        .padding(.bottom, 16)
    }
}

// 再生状態の列挙型
enum PlaybackState {
    case stopped    // 停止中
    case playing    // 再生中
    case resetting  // リセット中
}

// メインのContentView
struct ContentView: View {
    @EnvironmentObject var pc88: PC88Core
    @State private var isPMDPlaying = false
    @State private var playbackState: PlaybackState = .resetting
    @State private var selectedFile: URL?
    @State private var isFilePickerPresented = false
    @State private var refreshTimer: Timer?
    
    // PC88PMDクラスの再生状態を監視するためのキャンセル可能なストレージ
    // @Stateを使用してクロージャ内でも変更可能にする
    @State private var cancellables = Set<AnyCancellable>()
    
    // チャンネル状態表示用の色
    let activeColor = Color.green
    let inactiveColor = Color.gray
    
    var body: some View {
            ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // ヘッダー部分
                HeaderView(status: pc88.status)
                    .onAppear {
                        // PC88PMDクラスの再生状態を監視する
                        let subscription = pc88.pmd.playbackStatePublisher
                            .receive(on: RunLoop.main)
                            .sink { newState in
                                // PC88PMDの再生状態をContentViewの再生状態に反映
                                switch newState {
                                case .stopped:
                                    playbackState = .stopped
                                    isPMDPlaying = false
                                case .playing:
                                    playbackState = .playing
                                    isPMDPlaying = true
                                case .resetting:
                                    playbackState = .resetting
                                    isPMDPlaying = false
                                }
                            }
                        
                        // サブスクリプションを保存
                        // @Stateプロパティはクロージャ内でも変更可能
                        DispatchQueue.main.async {
                            cancellables.insert(subscription)
                        }
                    }
                
                // コントロールパネル
                ControlPanelView(
                    isPMDPlaying: $isPMDPlaying,
                    playbackState: $playbackState,
                    isFilePickerPresented: $isFilePickerPresented,
                    selectedFile: selectedFile,
                    onPlayPause: playPauseAction
                )
                .padding(.bottom, 16)
                
                // FM音源チャンネル情報表示
                FMChannelInfoView(
                    channelInfo: pc88.fmChannelInfo,
                    activeColor: activeColor,
                    inactiveColor: inactiveColor
                )
                
                // SSG音源チャンネル情報表示
                SSGChannelInfoView(
                    channelInfo: pc88.ssgChannelInfo,
                    activeColor: activeColor,
                    inactiveColor: inactiveColor
                )
                
                // リズム音源とADPCM状態表示
                RhythmADPCMView(
                    isRhythmActive: pc88.isRhythmActive,
                    isADPCMActive: pc88.isADPCMActive,
                    activeColor: activeColor,
                    inactiveColor: inactiveColor
                )
                
                // PMD88ワークエリアモニター
                PMDWorkAreaMonitorView(
                    songDataAddress: pc88.songDataAddress,
                    stepCount: pc88.stepCount
                )
            }
            .padding()
        }
        .sheet(isPresented: $isFilePickerPresented) {
            DocumentPicker(selectedURL: $selectedFile, onPick: { url in
                // ファイルを選択したら読み込む
                loadD88File(url: url)
            })
        }
        .onAppear {
            // PC88の状態を監視して同期
            isPMDPlaying = pc88.programRunning
        }
        .onReceive(pc88.$programRunning) { newValue in
            // PC88の状態変化を監視して同期
            isPMDPlaying = newValue
        }
        .onDisappear {
            // ビューが非表示になったらタイマーを停止
            stopRefreshTimer()
        }
    }
    
    // ファイル読み込み処理
    private func loadD88File(url: URL) {
        // 処理開始前にUIを更新
        pc88.appendLog("D88ファイル読み込み開始: \(url.lastPathComponent)")
        // ファイル読み込み処理（バックグラウンドで実行）
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // セキュリティスコープドアクセスの開始
                let securityScopedURL = url.startAccessingSecurityScopedResource()
                
                // ファイルデータの読み込み
                let data = try Data(contentsOf: url)
                
                // セキュリティスコープドアクセスの終了
                if securityScopedURL {
                    url.stopAccessingSecurityScopedResource()
                }
                
                // メインスレッドでPC88のプロパティを更新
                DispatchQueue.main.async {
                    self.pc88.status = "D88ファイルを読み込みました: \(url.lastPathComponent)"
                    self.pc88.d88Data = data
                    
                    // D88データの解析を実行
                    self.analyzeD88Data()
                }
            } catch {
                // エラーが発生した場合
                DispatchQueue.main.async {
                    self.pc88.status = "エラー: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // D88データの解析処理
    private func analyzeD88Data() {
        guard let data = pc88.d88Data, data.count > 0 else { return }
        
        pc88.appendLog("D88データの解析を開始します...")
        
        // D88ファイルのヘッダー情報を解析
        if data.count >= 0x20 { // 最低限のヘッダーサイズ
            let diskName = String(data: data[0..<16], encoding: .ascii)?.trimmingCharacters(in: .controlCharacters) ?? "不明"
            let writeProtected = data[0x1A] > 0 ? "あり" : "なし"
            let diskType = data[0x1B]
            let diskSize = data[0x1C...0x1F].withUnsafeBytes { $0.load(as: UInt32.self) }
            
            pc88.appendLog("===== D88ファイル情報 =====")
            pc88.appendLog("ディスク名: \(diskName)")
            pc88.appendLog("書き込み保護: \(writeProtected)")
            pc88.appendLog("ディスクタイプ: \(diskType)")
            pc88.appendLog("ディスクサイズ: \(diskSize) バイト")
            
            // PMD88関連のデータを探索
            pc88.appendLog("\n===== PMD88データ探索 =====")
            
            // PMD88のプログラムデータを検索
            let pmdSignature: [UInt8] = [0x50, 0x4D, 0x44, 0x38, 0x38] // "PMD88"のASCIIコード
            var foundPMD = false
            
            for i in 0..<(data.count - pmdSignature.count) {
                let range = i..<(i + pmdSignature.count)
                let bytes = [UInt8](data[range])
                
                if bytes == pmdSignature {
                    foundPMD = true
                    pc88.appendLog("PMD88シグネチャを発見: オフセット 0x\(String(format: "%X", i))")
                    break
                }
            }
            
            if foundPMD {
                pc88.appendLog("PMD88プログラムが見つかりました。")
                // 曲データと音色データの位置を推定
                pc88.appendLog("曲データと音色データの位置を推定しています...")
                
                // 曲データアドレスを0x4C00に設定
                pc88.cpu.writeMemory(at: 0x4C00, value: 0x00)
                pc88.cpu.writeMemory(at: 0x4C01, value: 0x4C)
                
                // 音色データアドレスを0x6000に設定
                pc88.cpu.writeMemory(at: 0x6000, value: 0x00)
                pc88.cpu.writeMemory(at: 0x6001, value: 0x60)
                
                pc88.appendLog("曲データアドレス: 0x4C00")
                pc88.appendLog("音色データアドレス: 0x6000")
            } else {
                pc88.appendLog("PMD88シグネチャが見つかりませんでした。")
            }
        } else {
            pc88.appendLog("D88データが不完全です。解析できません。")
        }
    }
    
    // 更新タイマーの開始
    private func startRefreshTimer() {
        // 既存のタイマーを停止
        stopRefreshTimer()
        
        // 新しいタイマーを開始（0.1秒ごとに更新）
        // RunLoop.mainでタイマーを作成してメインスレッドで確実に実行されるようにする
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak pc88Ref = pc88] _ in
            // 弱参照を使用して循環参照を防止
            guard let pc88Ref = pc88Ref else { return }
            
            // チャンネル情報を更新
            pc88Ref.updateChannelInfo()
            
            // デバッグ情報を定期的に更新
            if self.isPMDPlaying && pc88Ref.pmd.isRunning() {
                pc88Ref.debug.printPMD88WorkingAreaStatus()
            }
        }
        
        // メインスレッドのランループにタイマーを追加
        RunLoop.main.add(refreshTimer!, forMode: .common)
    }
    
    // 更新タイマーの停止
    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    // 再生/停止/リセットアクション
    private func playPauseAction() {
        // デバッグ出力
        print("\n[ContentView] ボタン押下時の状態: \(playbackState)")
        
        // すべての処理をメインスレッドで実行して状態更新を確実に行う
        DispatchQueue.main.async { [self] in
            switch playbackState {
            case .stopped:
                // 停止中の場合はリセット処理を実行
                print("[ContentView] リセット処理を実行")
                
                // 状態を更新
                playbackState = .resetting
                isPMDPlaying = false
                
                // リセット処理を実行
                DispatchQueue.global(qos: .userInitiated).async { [weak pc88Ref = pc88] in
                    guard let pc88Ref = pc88Ref else { return }
                    pc88Ref.pmd.reset()
                    
                    // 状態更新をメインスレッドで行う
                    DispatchQueue.main.async {
                        pc88Ref.pmd.updatePlaybackState(.resetting)
                    }
                }
                
            case .resetting:
                // リセット中の場合は再生処理を実行
                print("[ContentView] 再生処理を実行")
                
                // 状態を更新
                playbackState = .playing
                isPMDPlaying = true
                
                // 再生処理を実行
                DispatchQueue.global(qos: .userInitiated).async { [weak pc88Ref = pc88] in
                    guard let pc88Ref = pc88Ref else { return }
                    pc88Ref.runPMDMusic()
                    
                    // 状態更新をメインスレッドで行う
                    DispatchQueue.main.async {
                        pc88Ref.pmd.updatePlaybackState(.playing)
                    }
                }
                
                // 情報更新タイマー開始
                startRefreshTimer()
                
            case .playing:
                // 再生中の場合は停止処理を実行
                print("[ContentView] 停止処理を実行")
                
                // 状態を更新
                playbackState = .stopped
                isPMDPlaying = false
                
                // 停止処理を実行
                DispatchQueue.global(qos: .userInitiated).async { [weak pc88Ref = pc88] in
                    guard let pc88Ref = pc88Ref else { return }
                    pc88Ref.stop()
                    
                    // 状態更新をメインスレッドで行う
                    DispatchQueue.main.async {
                        pc88Ref.pmd.updatePlaybackState(.stopped)
                    }
                }
                
                // 更新タイマーを停止
                stopRefreshTimer()
            }
        }
    }
}

// ファイル選択のDocumentPicker
struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var selectedURL: URL?
    var onPick: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // D88ファイルとすべてのデータファイルを対象にする
        var supportedTypes: [UTType] = [UTType.data]
        // カスタムUTTypeの定義（D88ファイル用）
        if let d88Type = UTType(filenameExtension: "d88") {
            supportedTypes.append(d88Type)
        }
        
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            // セキュリティスコープドアクセスの開始
            let securityScopedURL = url.startAccessingSecurityScopedResource()
            
            // 選択されたURLを保存して処理を実行
            parent.selectedURL = url
            parent.onPick(url)
            
            // セキュリティスコープドアクセスの終了
            if securityScopedURL {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }
}
