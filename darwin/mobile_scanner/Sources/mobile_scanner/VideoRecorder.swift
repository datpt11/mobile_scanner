import AVFoundation

class VideoRecorder {
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var hasWrittenFrame = false
    private var sessionAtSourceTime: CMTime?

    // ✅ Thêm biến đánh dấu trạng thái quay
    private var isRecording = false

    func startRecording(to url: URL, videoSettings: [String: Any], audioSettings: [String: Any], completion: @escaping (Int?) -> Void) throws {
        outputURL = url
        hasWrittenFrame = false
        sessionAtSourceTime = nil

        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)

        videoInput?.expectsMediaDataInRealTime = true
        audioInput?.expectsMediaDataInRealTime = true

        if let vInput = videoInput, writer!.canAdd(vInput) {
            writer!.add(vInput)
        }
        if let aInput = audioInput, writer!.canAdd(aInput) {
            print("✅ Added audio input")
            writer!.add(aInput)
        }

        // ✅ Đánh dấu trạng thái đã bắt đầu quay
        isRecording = true
        completion(1)
        print("✅ Recorder ready at: \(url)")
    }

    func append(sampleBuffer: CMSampleBuffer) {
        guard isRecording else { return }
        
        guard let writer = writer else { return }
        guard writer.status != .failed else {
            print("❌ Writer failed: \(writer.error?.localizedDescription ?? "Unknown")")
            return
        }

        let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer)
        let mediaType = CMFormatDescriptionGetMediaType(formatDesc!)

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // 👉 CHỈ start session khi gặp VIDEO FRAME ĐẦU TIÊN
        if sessionAtSourceTime == nil && mediaType == kCMMediaType_Video {
            sessionAtSourceTime = timestamp
            writer.startWriting()
            writer.startSession(atSourceTime: timestamp)
            print("▶️ Start writing at \(timestamp.seconds)")
        }

        guard writer.status == .writing else { return }
    
        if mediaType == kCMMediaType_Video {
            if let vInput = videoInput, vInput.isReadyForMoreMediaData {
                if vInput.append(sampleBuffer) {
                    hasWrittenFrame = true
                }
            }
        }

        if mediaType == kCMMediaType_Audio {
            if let aInput = audioInput, aInput.isReadyForMoreMediaData {
                print("✅ Appending audio frame at \(timestamp.seconds)")
                if aInput.append(sampleBuffer) {
                    hasWrittenFrame = true
                }
            }
        }
    }

    func stopRecording(completion: @escaping (Int?, URL?) -> Void) {
        guard isRecording else {
            completion(0, nil)
            return
        }
        
        
        guard let writer = writer else {
            completion(0, nil)
            return
        }

        // Nếu chưa ghi frame nào → hủy
        guard hasWrittenFrame else {
            print("⚠️ No frame written, cancel writing")
            writer.cancelWriting()
            completion(0, nil)
            reset()
            return
        }

        // Đảm bảo trạng thái đúng
        guard writer.status == .writing else {
            print("⚠️ Writer not in writing state: \(writer.status.rawValue)")
            completion(0, nil)
            reset()
            return
        }

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()

        writer.finishWriting { [weak self] in
            guard let self = self else { return }
            print("✅ Recording finished at: \(self.outputURL?.absoluteString ?? "nil")")
            completion(0, self.outputURL)
            self.reset()
        }
    }

    private func reset() {
        writer = nil
        videoInput = nil
        audioInput = nil
        outputURL = nil
        sessionAtSourceTime = nil
        hasWrittenFrame = false
        isRecording = false
    }
}
