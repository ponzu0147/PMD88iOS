import SwiftUI

struct ContentView: View {
    @StateObject var pc88 = PC88()
    @State private var isPlayingSineWave = false
    
    var body: some View {
        VStack {
            Text("PC-8801 PMD エミュレータ")
                .font(.title)
                .padding()
            
            // ステータス表示
            Text(pc88.status)
                .font(.headline)
                .padding()
            
            // 実行制御ボタン
            HStack {
                Button("実行") {
                    loadAndRunEmulator()
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .disabled(pc88.programRunning)
                
                Button("停止") {
                    pc88.stop()
                }
                .padding()
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(10)
                .disabled(!pc88.programRunning)
                
                Button("デバッグ表示") {
                    pc88.showDebugLog()
                }
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding()
            
            // 正弦波テスト用トグルボタン
            Button(action: {
                isPlayingSineWave.toggle()
                if isPlayingSineWave {
                    pc88.playSineWave()
                } else {
                    pc88.stopSineWave()
                }
            }) {
                HStack {
                    Image(systemName: isPlayingSineWave ? "speaker.wave.3.fill" : "speaker.slash.fill")
                    Text(isPlayingSineWave ? "音声停止" : "音声再生")
                }
                .padding()
                .frame(minWidth: 180)
                .background(isPlayingSineWave ? Color.purple : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding(.bottom)
            
            // ログ表示領域
            ScrollView {
                Text(pc88.lastDebugLog.isEmpty ? pc88.lastLog : pc88.lastDebugLog)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color(white: 0.95))
            .cornerRadius(5)
            .padding()
        }
        .padding()
    }
    
    private func loadAndRunEmulator() {
        // ダミーのD88を作成してロード
        let dummyData = Data(repeating: 0, count: 1024)
        let disk = D88Disk(from: dummyData)
        pc88.loadD88(disk)
        
        // エミュレータ実行
        DispatchQueue.global().async {
            pc88.run()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
} 