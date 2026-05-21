import SwiftUI

/// SwiftUI sheet shown when the user clicks "Convert to GIF…" in the recording
/// editor. Lets them pick a frame rate + max dimension, shows a live size
/// estimate, and reports the chosen settings back via `onConvert`.
struct GifConversionView: View {
    let sourceWidth: Int
    let sourceHeight: Int
    let durationSeconds: Double
    let onConvert: (_ fps: Int, _ maxLongSide: Int) -> Void
    let onCancel: () -> Void

    @State private var fps: Int = 15
    @State private var maxLongSide: Int = 720

    private var scaledSize: (Int, Int) {
        let srcLong = max(sourceWidth, sourceHeight)
        if maxLongSide == 0 || srcLong <= maxLongSide {
            return (sourceWidth, sourceHeight)
        }
        let scale = Double(maxLongSide) / Double(srcLong)
        return (Int(Double(sourceWidth) * scale), Int(Double(sourceHeight) * scale))
    }

    private var frameCount: Int {
        max(1, Int(durationSeconds * Double(fps)))
    }

    private var estimatedMB: Double {
        let (w, h) = scaledSize
        let bytes = GifConverter.estimateBytes(width: w, height: h, frameCount: frameCount)
        return Double(bytes) / (1024 * 1024)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Convert to GIF").font(.title2).bold()
            Text("Tradeoffs: GIFs work everywhere but are larger and lower quality than video. Pick smaller numbers for smaller files.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Form {
                Picker("Frame rate", selection: $fps) {
                    Text("10 fps").tag(10)
                    Text("15 fps").tag(15)
                    Text("24 fps").tag(24)
                }
                Picker("Max size", selection: $maxLongSide) {
                    Text("480 px long side").tag(480)
                    Text("720 px long side").tag(720)
                    Text("1080 px long side").tag(1080)
                    Text("Original (\(sourceWidth) × \(sourceHeight))").tag(0)
                }
            }

            let (w, h) = scaledSize
            Text(String(
                format: "Estimated: %.1f MB · %d × %d · %d frames @ %d fps",
                estimatedMB, w, h, frameCount, fps
            ))
            .font(.caption).foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Convert") { onConvert(fps, maxLongSide) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
