import AVFoundation

// Run on macOS, without a camera or Flutter engine:
// swiftc darwin/mobile_scanner/Sources/mobile_scanner/VideoRecorder.swift \
//   test/native/video_recorder_test.swift -o /tmp/video_recorder_test
// /tmp/video_recorder_test
@main
struct VideoRecorderTests {
    static let video: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: 64,
        AVVideoHeightKey: 64
    ]
    static let audio: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVNumberOfChannelsKey: 1,
        AVSampleRateKey: 44100,
        AVEncoderBitRateKey: 64000
    ]

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    static func wait(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(10)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        check(condition(), "Timed out waiting for recorder completion")
    }

    static func frame(_ index: Int64) -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        check(CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA,
                                 nil, &pixelBuffer) == kCVReturnSuccess, "Create pixel buffer")
        let buffer = pixelBuffer!
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), 128, CVPixelBufferGetDataSize(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        var format: CMVideoFormatDescription?
        check(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                          imageBuffer: buffer,
                                                          formatDescriptionOut: &format) == noErr,
              "Create video format")
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30),
                                        presentationTimeStamp: CMTime(value: index, timescale: 30),
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        check(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                                                      imageBuffer: buffer,
                                                      formatDescription: format!,
                                                      sampleTiming: &timing,
                                                      sampleBufferOut: &sample) == noErr,
              "Create sample buffer")
        return sample!
    }

    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = VideoRecorder()
        let first = directory.appendingPathComponent("empty.mp4")
        var events: [String] = []
        try recorder.startRecording(to: first, videoSettings: video, audioSettings: audio) { url in
            check(Thread.isMainThread, "File callback must run on main")
            check(url == nil, "No frames must not report a successful video")
            events.append("file")
        }
        do {
            try recorder.startRecording(to: directory.appendingPathComponent("rejected.mp4"),
                                        videoSettings: video, audioSettings: audio) { _ in
                preconditionFailure("Rejected start must not replace the first completion")
            }
            preconditionFailure("Duplicate start must fail")
        } catch VideoRecorder.RecordingError.alreadyRecording {}
        recorder.stopRecording { events.append("stop1") }
        recorder.stopRecording { events.append("stop2") }
        wait { events.count == 3 }
        check(events == ["file", "stop1", "stop2"], "Publish exactly one file before replying to both stops")
        check(!FileManager.default.fileExists(atPath: first.path), "Remove empty output")
        recorder.stopRecording { events.append("idleStop") }
        wait { events.count == 4 }
        check(events.filter { $0 == "file" }.count == 1, "Idle stop must not emit a second result")
        print("PASS: duplicate start, repeated/idle stop, empty output cleanup and main-thread callbacks")

        // Reuse the same recorder after its previous completion and create real footage.
        let second = directory.appendingPathComponent("video.mp4")
        var saved: URL?
        var finished = false
        var reply = false
        try recorder.startRecording(to: second, videoSettings: video, audioSettings: audio) { url in
            check(Thread.isMainThread, "Successful file callback must run on main")
            saved = url
            finished = true
        }
        for index in 0..<15 {
            recorder.append(sampleBuffer: frame(Int64(index)))
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        recorder.stopRecording {
            check(finished, "File result must precede stop reply")
            reply = true
        }
        wait { reply }
        check(saved == second, "Successful finalize must return its own output URL")
        let asset = AVURLAsset(url: second)
        check(!asset.tracks(withMediaType: .video).isEmpty, "Finalized output must contain a readable video track")
        check(asset.duration.seconds > 0, "Finalized video must have positive duration")
        print("PASS: recorder reuse, real frames, finalized playable output and callback order")

        // AVAssetWriter must not overwrite an existing file or leave stale state on failure.
        do {
            try recorder.startRecording(to: second, videoSettings: video, audioSettings: audio) { _ in
                preconditionFailure("Failed writer initialization must not register a completion")
            }
            preconditionFailure("Existing output must fail writer initialization")
        } catch {}
        let third = directory.appendingPathComponent("after-failed-start.mp4")
        var recovered = false
        try recorder.startRecording(to: third, videoSettings: video, audioSettings: audio) { _ in recovered = true }
        recorder.stopRecording {}
        wait { recovered }
        check(FileManager.default.fileExists(atPath: second.path), "Failed start must preserve earlier video")
        print("PASS: existing output rejection preserves footage and permits retry")
    }
}
