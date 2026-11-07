#if os(macOS)
    import Foundation
    import Testing

    private func clipMovie() async throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
        try await SyntheticMovie.write(to: url, frames: 90) { frame in
            SyntheticMovie.Point(x: 0.5, y: 0.3 + 0.3 * Double(frame) / 90)
        }
        return url
    }

    @Test func aClipLivesOnALoggedSetAcrossProcessesAndNeverTouchesTheSheet() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let movie = try await clipMovie()
        defer { try? FileManager.default.removeItem(at: movie) }
        let cli = CLI(home: home, binary: try workoutBinary())
        _ = try cli.run("init", "--scenario", "fresh-block")

        let pending = try cli.run("clip", "add", "w1d1.e0.s0", movie.path)
        #expect(pending.status == 1)
        #expect(try pending.errorJSON["code"] as? String == "set_not_logged")

        _ = try cli.run("log", "w1d1.e0.s0", "185x5@8")
        let added = try cli.run("clip", "add", "w1d1.e0.s0", movie.path)
        #expect(added.status == 0)
        #expect(try added.json["caption"] as? String == "Back Squat · W1 D1 · Set 1 · 185×5 @8")
        #expect(FileManager.default.fileExists(atPath: movie.path))
        let id = try #require(try added.json["id"] as? String)

        let traced = try cli.run("clip", "trace", id, "--x", "0.5", "--y", "0.3")
        #expect(traced.status == 0)
        let path = try #require(try traced.json["barPath"] as? [String: Any])
        #expect(path["ending"] as? String == "endOfClip")
        #expect(try #require(path["samples"] as? [Any]).count > 2)

        #expect(try cli.run("clip", "mark", id, "--at", "1.5").json["startMark"] as? Double == 1.5)
        let listed = try #require(
            try JSONSerialization.jsonObject(with: cli.run("clip", "list", "w1d1.e0.s0").stdout) as? [[String: Any]]
        )
        #expect(listed.map { $0["id"] as? String } == [id])
        #expect(listed.first?["startMark"] as? Double == 1.5)
        #expect(try cli.run("clip", "storage").json["count"] as? Int == 1)

        #expect(try cli.run("flush").status == 0)
        #expect(try cli.run("sheet", "--cell", "K15").json["value"] as? String == "185x5@8")

        #expect(try cli.run("clip", "delete", id).json["count"] as? Int == 0)
        let gone = try cli.run("clip", "delete", id)
        #expect(gone.status == 1)
        #expect(try gone.errorJSON["code"] as? String == "unknown_form_clip")
    }

    @Test func aMovieDamagedPartWayDrawsNoPathAndSaysSo() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let movie = try await clipMovie()
        defer { try? FileManager.default.removeItem(at: movie) }
        try SyntheticMovie.damageBackHalf(of: movie)
        let cli = CLI(home: home, binary: try workoutBinary())
        _ = try cli.run("init", "--scenario", "fresh-block")
        _ = try cli.run("log", "w1d1.e0.s0", "185x5@8")
        let id = try #require(try cli.run("clip", "add", "w1d1.e0.s0", movie.path).json["id"] as? String)

        let traced = try cli.run("clip", "trace", id, "--x", "0.5", "--y", "0.3")

        #expect(traced.status == 1)
        #expect(try traced.errorJSON["code"] as? String == "bar_path_failed")
        let listed = try #require(
            try JSONSerialization.jsonObject(with: cli.run("clip", "list", "w1d1.e0.s0").stdout) as? [[String: Any]]
        )
        #expect(listed.map { $0["id"] as? String } == [id])
        #expect(listed.first?["barPath"] == nil)
    }

    /// Vision prints its own diagnostics on stdout when it refuses a frame, as it does a seed with no position.
    @Test func whatVisionPrintsStaysOutOfTheOutput() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let movie = try await clipMovie()
        defer { try? FileManager.default.removeItem(at: movie) }
        let cli = CLI(home: home, binary: try workoutBinary())
        _ = try cli.run("init", "--scenario", "fresh-block")
        _ = try cli.run("log", "w1d1.e0.s0", "185x5@8")
        let id = try #require(try cli.run("clip", "add", "w1d1.e0.s0", movie.path).json["id"] as? String)

        let traced = try cli.run("clip", "trace", id, "--x", "nan", "--y", "nan")

        #expect(traced.status == 1)
        #expect(traced.stdout.isEmpty)
        #expect(try traced.errorJSON["code"] as? String == "bar_path_failed")
    }

    @Test func aFileThatIsNotAMovieIsNamedAndKept() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let cli = CLI(home: home, binary: try workoutBinary())
        _ = try cli.run("init", "--scenario", "fresh-block")
        _ = try cli.run("log", "w1d1.e0.s0", "185x5@8")
        let file = home.appendingPathComponent("notes.mov")
        try Data("not a movie".utf8).write(to: file)

        let refused = try cli.run("clip", "add", "w1d1.e0.s0", file.path)

        #expect(refused.status == 1)
        #expect(try refused.errorJSON["code"] as? String == "not_a_movie")
        #expect(FileManager.default.fileExists(atPath: file.path))
    }
#endif
