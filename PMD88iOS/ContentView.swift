//
//  ContentView.swift
//  PMD88iOS
//
//  Created on 2022/01/04.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var pc88: PC88
    @State private var isPMDPlaying = false
    @State private var selectedFile: URL?
    @State private var isFilePickerPresented = false
    @State private var refreshTimer: Timer?
    
    // チャンネル状態表示用の色
    let activeColor = Color.green
    let inactiveColor = Color.gray
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // ヘッダー部分
                Text("PMD88 Music Player")
                    .font(.title)
                    .padding(.bottom, 8)
                
                // ステータス表示
                Text("ステータス: \(pc88.status)")
                    .font(.headline)
                    .padding(.bottom, 8)
                
                // コントロールボタン
                HStack(spacing: 20) {
                    // PMD88音楽再生/停止ボタン
                    Button(action: {
                        if !isPMDPlaying {
                            // 再生開始
                            isPMDPlaying = true
                            
                            // バックグラウンドで実行
                            DispatchQueue.global(qos: .userInitiated).async {
                                self.pc88.runPMDMusic()
                            }
                            
                            // 情報更新タイマー開始
                            startRefreshTimer()
                        } else {
                            // 停止
                            isPMDPlaying = false
                            
                            // バックグラウンドで停止処理
                            DispatchQueue.global(qos: .userInitiated).async {
                                self.pc88.stop()
                            }
                            
                            // 更新タイマーを停止
                            stopRefreshTimer()
                        }
                    }) {
                        Text(isPMDPlaying ? "停止" : "再生")
                            .frame(minWidth: 100)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    // ボタンの無効化条件を修正
                    .disabled(false) // 常に有効にする
                    
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
                
                // FM音源チャンネル情報表示
                VStack(alignment: .leading, spacing: 4) {
                    Text("FM音源チャンネル")
                        .font(.headline)
                        .padding(.bottom, 4)
                    
                    // FMチャンネルの状態表示
                    ForEach(0..<6) { i in
                        if let info = pc88.fmChannelInfo[i] {
                            HStack {
                                Text("FM\(i+1):")
                                    .frame(width: 50, alignment: .leading)
                                
                                Circle()
                                    .fill(info.isActive ? activeColor : inactiveColor)
                                    .frame(width: 12, height: 12)
                                
                                Text("アドレス: \(String(format:"0x%04X", info.playingAddress))")
                                    .frame(width: 120, alignment: .leading)
                                
                                Text("音色: \(info.toneNumber)")
                                    .frame(width: 80, alignment: .leading)
                                
                                Text("音量: \(info.volume)")
                                    .frame(width: 80, alignment: .leading)
                            }
                            .padding(.vertical, 2)
                        } else {
                            HStack {
                                Text("FM\(i+1):")
                                    .frame(width: 50, alignment: .leading)
                                
                                Circle()
                                    .fill(inactiveColor)
                                    .frame(width: 12, height: 12)
                                
                                Text("停止中")
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .padding(.bottom, 16)
                
                // SSG音源チャンネル情報表示
                VStack(alignment: .leading, spacing: 4) {
                    Text("SSG音源チャンネル")
                        .font(.headline)
                        .padding(.bottom, 4)
                    
                    // SSGチャンネルの状態表示
                    ForEach(0..<3) { i in
                        if let info = pc88.ssgChannelInfo[i] {
                            HStack {
                                Text("SSG\(i+1):")
                                    .frame(width: 50, alignment: .leading)
                                
                                Circle()
                                    .fill(info.isActive ? activeColor : inactiveColor)
                                    .frame(width: 12, height: 12)
                                
                                Text("アドレス: \(String(format:"0x%04X", info.playingAddress))")
                                    .frame(width: 120, alignment: .leading)
                                
                                Text("音色: \(info.toneNumber)")
                                    .frame(width: 80, alignment: .leading)
                                
                                Text("音量: \(info.volume)")
                                    .frame(width: 80, alignment: .leading)
                            }
                            .padding(.vertical, 2)
                        } else {
                            HStack {
                                Text("SSG\(i+1):")
                                    .frame(width: 50, alignment: .leading)
                                
                                Circle()
                                    .fill(inactiveColor)
                                    .frame(width: 12, height: 12)
                                
                                Text("停止中")
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .padding(.bottom, 16)
                
                // リズム音源とADPCM状態表示
                VStack(alignment: .leading, spacing: 4) {
                    Text("リズム・ADPCM音源")
                        .font(.headline)
                        .padding(.bottom, 4)
                    
                    HStack {
                        Text("リズム:")
                            .frame(width: 50, alignment: .leading)
                        
                        Circle()
                            .fill(pc88.isRhythmActive ? activeColor : inactiveColor)
                            .frame(width: 12, height: 12)
                        
                        Text(pc88.isRhythmActive ? "演奏中" : "停止中")
                    }
                    .padding(.vertical, 2)
                    
                    HStack {
                        Text("ADPCM:")
                            .frame(width: 50, alignment: .leading)
                        
                        Circle()
                            .fill(pc88.isADPCMActive ? activeColor : inactiveColor)
                            .frame(width: 12, height: 12)
                        
                        Text(pc88.isADPCMActive ? "演奏中" : "停止中")
                    }
                    .padding(.vertical, 2)
                }
                .padding(.bottom, 16)
                
                // PMD88ワークエリアモニター
                VStack(alignment: .leading, spacing: 4) {
                    Text("PMD88ワークエリアモニター")
                        .font(.headline)
                        .padding(.bottom, 4)
                    
                    // モニター表示
                    HStack {
                        Text("曲データアドレス:")
                            .frame(width: 120, alignment: .leading)
                        Text(pc88.songDataAddress)
                    }
                    .padding(.vertical, 2)
                    
                    HStack {
                        Text("処理ステップ数:")
                            .frame(width: 120, alignment: .leading)
                        Text("\(pc88.stepCount)")
                    }
                    .padding(.vertical, 2)
                }
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
        // 引数で受け取ったURLを使用する
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
                }
            } catch {
                // エラーが発生した場合
                DispatchQueue.main.async {
                    self.pc88.status = "エラー: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // 更新タイマーの開始
    private func startRefreshTimer() {
        // 既存のタイマーを停止
        stopRefreshTimer()
        
        // 新しいタイマーを開始（0.2秒ごとに更新）
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            // チャンネル情報を更新（メインスレッドで実行）
            self.pc88.updateChannelInfo()
        }
    }
    
    // 更新タイマーの停止
    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
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
