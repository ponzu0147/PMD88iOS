import SwiftUI

struct PC88ScreenView: View {
    @EnvironmentObject var pc88: PC88Core
    @State private var screenImage: UIImage?
    @State private var refreshTimer: Timer?
    @State private var debugInfo: String = "No data"
    @State private var bufferSize: Int = 0
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("PC-88画面 (インターレース表示 640x400)")
                .font(.headline)
                .padding(.bottom, 4)
            
            if let image = screenImage {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none) // ピクセルを正確に表示
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 640, maxHeight: 400)
                    .background(Color.black)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.gray, lineWidth: 1)
                    )
            } else {
                Rectangle()
                    .fill(Color.black)
                    .frame(maxWidth: 640, maxHeight: 400)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.gray, lineWidth: 1)
                    )
            }
            
            // デバッグ情報
            Text("Screen Mode: \(pc88.screen.screenMode.description)")
                .font(.caption)
            Text("Resolution: \(pc88.screen.screenMode.resolution.width)x\(pc88.screen.screenMode.resolution.height)")
                .font(.caption)
            Text("Buffer Size: \(bufferSize) bytes")
                .font(.caption)
            Text("Debug: \(debugInfo)")
                .font(.caption)
        }
        .padding()
        .onAppear {
            startRefreshTimer()
        }
        .onDisappear {
            stopRefreshTimer()
        }
    }
    
    private func startRefreshTimer() {
        // 画面更新タイマーを開始（60FPS相当）
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { _ in
            updateScreenImage()
        }
    }
    
    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func updateScreenImage() {
        // PC88Screenクラスから画面バッファを取得してUIImageに変換
        let buffer = pc88.screen.getScreenBuffer()
        let width = pc88.screen.screenMode.resolution.width
        let height = pc88.screen.screenMode.resolution.height
        
        // デバッグ情報を更新
        bufferSize = buffer.count
        
        // バッファのサイズを確認
        let expectedSize = width * height * 4
        if buffer.count < expectedSize {
            debugInfo = "Buffer too small: \(buffer.count) < \(expectedSize)"
            return
        }
        
        // バッファからUIImageを生成
        if let cgImage = createCGImage(from: buffer, width: width, height: height) {
            screenImage = UIImage(cgImage: cgImage)
            debugInfo = "Image created: \(width)x\(height)"
        } else {
            debugInfo = "Failed to create image"
        }
    }
    
    private func createCGImage(from buffer: Data, width: Int, height: Int) -> CGImage? {
        guard buffer.count >= width * height * 4 else { return nil }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let provider = CGDataProvider(data: buffer as CFData) else { return nil }
        
        // インターレース表示のため、ピクセルを正確に表示する設定
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false, // ピクセル補間を行わない
            intent: .defaultIntent
        )
    }
}

struct PC88ScreenView_Previews: PreviewProvider {
    static var previews: some View {
        PC88ScreenView()
            .environmentObject(PC88Core())
    }
}
