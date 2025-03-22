import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject var pc88 = PC88()
    // PMD88音楽再生ボタンのみ使用
    @State private var isPMDPlaying = false
    
    var body: some View {
        VStack {
            Text("PC-8801 PMD88 音楽エミュレータ")
                .font(.title)
                .padding()
            
            // ステータス表示
            Text(pc88.status)
                .font(.headline)
                .padding()
            
            // PMD88音楽再生用ボタン（メインボタン）
            Button(action: {
                isPMDPlaying.toggle()
                if isPMDPlaying {
                    pc88.runPMDMusic()
                } else {
                    pc88.stop()
                }
            }) {
                HStack {
                    Image(systemName: isPMDPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 24))
                    Text(isPMDPlaying ? "PMD88停止" : "PMD88音楽再生")
                        .font(.headline)
                }
                .padding()
                .frame(minWidth: 220, minHeight: 50)
                .background(isPMDPlaying ? Color.red : Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding()
            .disabled(!pc88.runButtonEnabled && isPMDPlaying)
            
            // PMD88音楽再生ボタンのみ表示
            
            // チャンネル情報表示エリア
            VStack(spacing: 8) {
                Text("チャンネル状態")
                    .font(.headline)
                    .padding(.top, 4)
                
                // FM音源チャンネル表示
                VStack(spacing: 2) {
                    Text("FM音源")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .background(Color.blue.opacity(0.2))
                    
                    // FMチャンネル情報のグリッド表示
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 4) {
                        ForEach(pc88.fmChannels) { channel in
                            ChannelInfoView(channel: channel)
                        }
                    }
                }
                .padding(4)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
                
                // SSG音源チャンネル表示
                VStack(spacing: 2) {
                    Text("SSG音源")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .background(Color.green.opacity(0.2))
                    
                    // SSGチャンネル情報のグリッド表示
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 4) {
                        ForEach(pc88.ssgChannels) { channel in
                            ChannelInfoView(channel: channel)
                        }
                    }
                }
                .padding(4)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
                
                // リズム音源チャンネル表示
                VStack(spacing: 2) {
                    Text("リズム音源")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .background(Color.orange.opacity(0.2))
                    
                    // リズムチャンネル情報のグリッド表示
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 4) {
                        ForEach(pc88.rhythmChannels) { channel in
                            ChannelInfoView(channel: channel)
                        }
                    }
                }
                .padding(4)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
                
                // ADPCM音源チャンネル表示
                if let adpcmChannel = pc88.adpcmChannel {
                    VStack(spacing: 2) {
                        Text("ADPCM音源")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .background(Color.purple.opacity(0.2))
                        
                        ChannelInfoView(channel: adpcmChannel)
                            .padding(.horizontal)
                    }
                    .padding(4)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(8)
                }
                
                // PMD88ワークエリアモニター
                VStack(spacing: 2) {
                    Text("PMD88ワークエリアモニター")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .background(Color.teal.opacity(0.2))
                    
                    VStack(alignment: .leading, spacing: 6) {
                        // メインワークエリア情報
                        Group {
                            HStack {
                                Text("曲データ (0x1000):")
                                    .font(.system(size: 12, weight: .bold))
                                    .frame(width: 120, alignment: .leading)
                                Text(pc88.songDataAddress)
                                    .font(.system(size: 12, design: .monospaced))
                                    .padding(4)
                                    .background(Color.black.opacity(0.05))
                                    .cornerRadius(4)
                            }
                            
                            HStack {
                                Text("FM1位置 (0x1020):")
                                    .font(.system(size: 12, weight: .bold))
                                    .frame(width: 120, alignment: .leading)
                                Text(pc88.fm1Position)
                                    .font(.system(size: 12, design: .monospaced))
                                    .padding(4)
                                    .background(Color.black.opacity(0.05))
                                    .cornerRadius(4)
                            }
                            
                            HStack {
                                Text("キーオン (0x28):")
                                    .font(.system(size: 12, weight: .bold))
                                    .frame(width: 120, alignment: .leading)
                                Text(pc88.keyOnRegisterValue)
                                    .font(.system(size: 12, design: .monospaced))
                                    .padding(4)
                                    .background(Color.black.opacity(0.05))
                                    .cornerRadius(4)
                                Circle()
                                    .fill(pc88.isChannelActive ? Color.green : Color.red)
                                    .frame(width: 8, height: 8)
                            }
                        }
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        // FM1チャンネルワークエリア情報
                        Group {
                            Text("FM1チャンネルワークエリア (0xBD61付近)")
                                .font(.system(size: 12, weight: .bold))
                                .padding(.bottom, 2)
                            
                            // 演奏中のアドレス
                            HStack {
                                Text("address (0xBD61):")
                                    .font(.system(size: 12, weight: .bold))
                                    .frame(width: 120, alignment: .leading)
                                Text(pc88.fm1AddressHexValue)
                                    .font(.system(size: 12, design: .monospaced))
                                    .padding(4)
                                    .background(Color.black.opacity(0.05))
                                    .cornerRadius(4)
                                Circle()
                                    .fill(pc88.fm1AddressChanged ? Color.green : Color.red)
                                    .frame(width: 8, height: 8)
                            }
                            
                            // 演奏終了時の戻り先
                            HStack {
                                Text("partloop (0xBD63):")
                                    .font(.system(size: 12, weight: .bold))
                                    .frame(width: 120, alignment: .leading)
                                Text(pc88.fm1PartLoop)
                                    .font(.system(size: 12, design: .monospaced))
                                    .padding(4)
                                    .background(Color.black.opacity(0.05))
                                    .cornerRadius(4)
                            }
                            
                            // 残りの長さ
                            HStack {
                                Text("leng (0xBD65):")
                                    .font(.system(size: 12, weight: .bold))
                                    .frame(width: 120, alignment: .leading)
                                Text("\(pc88.fm1Length)")
                                    .font(.system(size: 12, design: .monospaced))
                                    .padding(4)
                                    .background(Color.black.opacity(0.05))
                                    .cornerRadius(4)
                            }
                            
                            // BLOCK/FNUM値
                            HStack {
                                Text("fnum (0xBD66):")
                                    .font(.system(size: 12, weight: .bold))
                                    .frame(width: 120, alignment: .leading)
                                Text(pc88.fm1FnumValue)
                                    .font(.system(size: 12, design: .monospaced))
                                    .padding(4)
                                    .background(Color.black.opacity(0.05))
                                    .cornerRadius(4)
                            }
                            
                            // 音量
                            HStack {
                                Text("volume (0xBD6D):")
                                    .font(.system(size: 12, weight: .bold))
                                    .frame(width: 120, alignment: .leading)
                                Text("\(pc88.fm1Volume)")
                                    .font(.system(size: 12, design: .monospaced))
                                    .padding(4)
                                    .background(Color.black.opacity(0.05))
                                    .cornerRadius(4)
                            }
                        }
                        
                        // 説明
                        Text("※ 値が変化するとエミュレーションが正しく動作している証拠です")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal)
                }
                .padding(4)
                .background(Color.teal.opacity(0.1))
                .cornerRadius(8)
            }
            .background(Color(white: 0.95))
            .cornerRadius(8)
            .padding()
        }
        .padding()
        .onAppear {
            // ビュー表示時にエミュレータを初期化
            initializeEmulator()
        }
        .onChange(of: pc88.programRunning) { oldValue, newValue in
            // プログラム実行状態の変化を監視
            isPMDPlaying = newValue
        }
    }
    
    private func initializeEmulator() {
        // ダミーのD88を作成してロード（初期化）
        let dummyData = Data(repeating: 0, count: 1024)
        let disk = D88Disk(from: dummyData)
        pc88.loadD88(disk)
        
        // チャンネル情報を定期的に更新するタイマーを設定
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if self.pc88.programRunning {
                self.pc88.updateChannelInfo()
            }
        }
    }
}

// チャンネル情報表示用のサブビュー
struct ChannelInfoView: View {
    let channel: PC88.ChannelInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // チャンネル名と演奏状態
            HStack {
                Text("\(channel.type)\(channel.number)")
                    .font(.system(size: 12, weight: .bold))
                Circle()
                    .fill(channel.isPlaying ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
            }
            
            // 音名
            Text("音名: \(channel.note)")
                .font(.system(size: 10))
            
            // アドレス
            Text("Addr: \(String(format: "0x%04X", channel.address))")
                .font(.system(size: 10, design: .monospaced))
            
            // 音量とインストゥルメント
            HStack {
                Text("Vol: \(channel.volume)")
                    .font(.system(size: 10))
                Text("Inst: \(channel.instrument)")
                    .font(.system(size: 10))
            }
        }
        .padding(4)
        .background(channel.isPlaying ? Color.white : Color(white: 0.9))
        .cornerRadius(4)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}