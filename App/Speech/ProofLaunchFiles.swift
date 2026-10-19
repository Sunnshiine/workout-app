#if DEBUG
    import AVFoundation

    /// What a Simulator proof launch reads from the host: a press's recording and the recording
    /// engine's model, neither of them bundled. Each stops the launch, naming the path, when it is
    /// not there, so a proof never quietly runs without them.
    enum ProofLaunchFiles {
        /// The samples of a 16 kHz mono WAV file, as `DictationRecorder` collects them.
        static func recording(at path: String) -> [Float] {
            let file: AVAudioFile
            do {
                file = try AVAudioFile(forReading: URL(filePath: path), commonFormat: .pcmFormatFloat32, interleaved: false)
            } catch {
                fatalError("\(LaunchFlag.recording.argument) could not read \(path): \(error)")
            }
            let format = file.processingFormat
            guard format.sampleRate == Double(DictationRecorder.sampleRate), format.channelCount == 1,
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)),
                (try? file.read(into: buffer)) != nil, let samples = buffer.floatChannelData
            else {
                fatalError("\(LaunchFlag.recording.argument) takes a 16 kHz mono WAV file, and \(path) is \(format)")
            }
            return Array(UnsafeBufferPointer(start: samples[0], count: Int(buffer.frameLength)))
        }

        /// The host folder, once it holds every file the recording engine loads.
        static func speechModels(at path: String) -> URL {
            let folder = URL(filePath: path, directoryHint: .isDirectory)
            let missing = WhisperEngine.missingFiles(inHost: folder)
            guard missing.isEmpty else {
                fatalError("\(LaunchFlag.speechModels.argument) \(path) lacks \(missing.map(\.path).joined(separator: ", "))")
            }
            return folder
        }
    }
#endif
