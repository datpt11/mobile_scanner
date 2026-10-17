import AVFoundation

class VideoRecorder {
    enum RecordingError: Error {
        case alreadyRecording
        case unsupportedSettings
        case outputAlreadyExists
    }

    // Audio, video and method calls arrive on different queues. All writer
    // state belongs to this queue; terminal callbacks always run on main.
    private let queue = DispatchQueue(label: "mobile_scanner.recorder")
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var hasWrittenVideo = false
    private var sessionStarted = false
    private var finishing = false
    private var onFinished: ((URL?) -> Void)?
    private var stopCallbacks: [() -> Void] = []

    func startRecording(to url: URL, videoSettings: [String: Any], audioSettings: [String: Any], onFinished: @escaping (URL?) -> Void) throws {
        try queue.sync {
            guard writer == nil else { throw RecordingError.alreadyRecording }
            guard !FileManager.default.fileExists(atPath: url.path) else {
                throw RecordingError.outputAlreadyExists
            }
            let newWriter = try AVAssetWriter(outputURL: url, fileType: .mp4)
            let video = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            video.expectsMediaDataInRealTime = true
            audio.expectsMediaDataInRealTime = true
            guard newWriter.canAdd(video), newWriter.canAdd(audio) else {
                newWriter.cancelWriting()
                try? FileManager.default.removeItem(at: url)
                throw RecordingError.unsupportedSettings
            }
            newWriter.add(video)
            newWriter.add(audio)
            writer = newWriter
            videoInput = video
            audioInput = audio
            outputURL = url
            self.onFinished = onFinished
        }
    }

    func append(sampleBuffer: CMSampleBuffer) {
        queue.sync {
            guard let writer = writer, !finishing else { return }
            guard writer.status != .failed else {
                completeRecording(url: nil)
                return
            }
            guard let format = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
            let mediaType = CMFormatDescriptionGetMediaType(format)

            // Audio received before the first video frame is intentionally skipped.
            if !sessionStarted && mediaType == kCMMediaType_Video {
                guard writer.startWriting() else {
                    completeRecording(url: nil)
                    return
                }
                writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                sessionStarted = true
            }
            guard writer.status == .writing else { return }

            if mediaType == kCMMediaType_Video, let input = videoInput, input.isReadyForMoreMediaData {
                if input.append(sampleBuffer) { hasWrittenVideo = true }
            } else if mediaType == kCMMediaType_Audio, let input = audioInput, input.isReadyForMoreMediaData {
                input.append(sampleBuffer)
            }
            if writer.status == .failed { completeRecording(url: nil) }
        }
    }

    func stopRecording(completion: @escaping () -> Void) {
        queue.async {
            guard let writer = self.writer else {
                DispatchQueue.main.async(execute: completion)
                return
            }
            self.stopCallbacks.append(completion)
            guard !self.finishing else { return }
            self.finishing = true

            guard self.hasWrittenVideo, writer.status == .writing else {
                self.completeRecording(url: nil)
                return
            }
            self.videoInput?.markAsFinished()
            self.audioInput?.markAsFinished()
            let url = self.outputURL
            writer.finishWriting {
                self.queue.async {
                    // finishWriting may itself fail (for example when storage fills).
                    self.completeRecording(url: writer.status == .completed ? url : nil)
                }
            }
        }
    }

    // Called only on queue. Reset before publishing so a later start cannot
    // have its writer or id cleared by the previous recording's completion.
    private func completeRecording(url: URL?) {
        if url == nil {
            if let writer = writer, writer.status == .unknown || writer.status == .writing {
                writer.cancelWriting()
            }
            if let outputURL = outputURL { try? FileManager.default.removeItem(at: outputURL) }
        }
        let callback = onFinished
        let callbacks = stopCallbacks
        writer = nil
        videoInput = nil
        audioInput = nil
        outputURL = nil
        hasWrittenVideo = false
        sessionStarted = false
        finishing = false
        onFinished = nil
        stopCallbacks = []
        DispatchQueue.main.async {
            callback?(url)
            callbacks.forEach { $0() }
        }
    }
}
