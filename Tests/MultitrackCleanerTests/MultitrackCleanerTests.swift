import XCTest
import AppKit
@testable import MultitrackCleaner

private final class URLResults: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        values.append(url)
        lock.unlock()
    }

    func all() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

final class FileScannerTests: XCTestCase {
    func testScansTopLevelWAVFilesInNaturalOrderAndDeduplicates() throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try touch(folder.appendingPathComponent("0003.WAV"))
        try touch(folder.appendingPathComponent("0001.wav"))
        try touch(folder.appendingPathComponent("notes.txt"))
        let nested = folder.appendingPathComponent("Nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try touch(nested.appendingPathComponent("0002.wav"))

        let files = try FileScanner().scan(urls: [folder, folder.appendingPathComponent("0001.wav")])
        XCTAssertEqual(files.map(\.originalFilename), ["0001.wav", "0003.WAV"])
    }
}

final class NumberPrefixDetectorTests: XCTestCase {
    func testDetectsSupportedPrefixesAndPreservesMeaningfulNumbers() {
        let detector = NumberPrefixDetector()
        let cases = ["0001 - Bass", "0001_Bass", "0001-Bass", "0001. Bass", "0001 Bass", "01 - Bass"]
        for value in cases {
            let detection = detector.candidate(in: value)
            XCTAssertNotNil(detection, value)
            XCTAssertTrue(detector.isConfirmed(detection!, in: cases), value)
        }
        XCTAssertNil(detector.candidate(in: "808"))
        let meaningful = detector.candidate(in: "12 String")!
        XCTAssertFalse(detector.isConfirmed(meaningful, in: ["12 String"]))
    }
}

final class CommonSegmentDetectorTests: XCTestCase {
    func testDetectsCommonLeftAndRightSegments() {
        let detector = CommonSegmentDetector()
        let result = detector.detect(in: [
            ["Битмейкер", "Bass", "Щука"],
            ["Битмейкер", "Kick", "Щука"],
            ["Битмейкер", "Snare", "Щука"]
        ])
        XCTAssertEqual(result.left, "Битмейкер")
        XCTAssertEqual(result.right, "Щука")
    }
}

final class FilenameAnalyzerTests: XCTestCase {
    func testFixtureSetsANumberingBPrefixCCombinationAndRealWorldSuffix() throws {
        XCTAssertEqual(proposed(["0001 - Bass.wav", "0002 - Kick.wav", "0003 - Snare.wav"]), ["Bass.wav", "Kick.wav", "Snare.wav"])
        XCTAssertEqual(proposed(["Щука - Bass.wav", "Щука - Kick.wav", "Щука - Snare.wav"]), ["Bass.wav", "Kick.wav", "Snare.wav"])
        XCTAssertEqual(proposed(["01 - Щука - Bass.wav", "02 - Щука - Kick.wav", "03 - Щука - Snare.wav"]), ["Bass.wav", "Kick.wav", "Snare.wav"])
        XCTAssertEqual(proposed(["0001 - conga1 - Щука.wav", "0002 - conga2 - Щука.wav", "0003 - tamburin - Щука.wav", "0034 - Vocal Anya - Щука.wav"]), ["conga1.wav", "conga2.wav", "tamburin.wav", "Vocal Anya.wav"])
    }

    func testRussianNormalizationAndMeaningfulNumbers() throws {
        XCTAssertEqual(proposed(["Бочка.wav", "Снейр.wav", "Хэт.wav", "Бас.wav", "Вокал.wav"]), ["Kick.wav", "Snare.wav", "Hat.wav", "Bass.wav", "Vocal.wav"])
        XCTAssertEqual(proposed(["808.wav", "909.wav", "303.wav", "12 String.wav"]), ["808.wav", "909.wav", "303.wav", "12 String.wav"])
    }

    private func proposed(_ names: [String]) -> [String] {
        let files = names.map { name in AudioFile(url: URL(fileURLWithPath: "/tmp/\(name)"), originalFilename: name) }
        return FilenameAnalyzer().analyze(files).map(\.proposedFilename)
    }
}

final class NameCapitalizerTests: XCTestCase {
    func testOptionUsesLightweightCapitalizationAndPreservesTechnicalTokens() {
        let names = ["vocal alex.wav", "midi fx oh l r lr vca di ambience.wav", "808.wav"]
        let files = names.map { name in AudioFile(url: URL(fileURLWithPath: "/tmp/\(name)"), originalFilename: name) }

        XCTAssertEqual(
            FilenameAnalyzer().analyze(files, capitalizeNames: true).map(\.proposedFilename),
            ["Vocal Alex.wav", "MIDI FX OH L R LR VCA DI AMBIENCE.wav", "808.wav"]
        )
        XCTAssertEqual(
            FilenameAnalyzer().analyze(files).map(\.proposedFilename),
            ["vocal alex.wav", "midi fx oh l r lr vca di ambience.wav", "808.wav"]
        )
    }

    @MainActor
    func testCapitalizationTogglePreservesManualTarget() throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("0001 - vocal alex.wav")
        try touch(source)

        let model = RenamePreviewViewModel()
        model.load(urls: [folder])
        model.updateProposal(id: try XCTUnwrap(model.proposals.first?.id), name: "Custom Vocal.wav")
        model.capitalizeNames = true

        XCTAssertEqual(model.proposals.first?.proposedFilename, "Custom Vocal.wav")
        XCTAssertTrue(model.proposals.first?.isManualEdit == true)
    }

    @MainActor
    func testLoadingAdditionalWAVURLsUsesExistingScanPipelineAndKeepsCurrentFiles() throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("001 - Kick.wav")
        let second = folder.appendingPathComponent("002 - Snare.wav")
        let third = folder.appendingPathComponent("003 - Hat.wav")
        try touch(first); try touch(second); try touch(third)

        let model = RenamePreviewViewModel()
        model.load(urls: [first])
        model.loadAdditional(urls: [second, third])

        XCTAssertEqual(model.files.map(\.originalFilename), ["001 - Kick.wav", "002 - Snare.wav", "003 - Hat.wav"])
        XCTAssertEqual(model.proposals.count, 3)
    }

    @MainActor
    func testLoadingAdditionalFolderAndWAVScansFolderTopLevelAndDeduplicates() throws {
        let folder = try makeTemporaryFolder()
        let nested = folder.appendingPathComponent("Nested")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let inside = folder.appendingPathComponent("001 - Kick.wav")
        let dropped = folder.appendingPathComponent("002 - Snare.wav")
        let nestedWAV = nested.appendingPathComponent("003 - Hat.wav")
        try touch(inside); try touch(dropped); try touch(nestedWAV)

        let model = RenamePreviewViewModel()
        model.loadAdditional(urls: [folder, dropped])

        XCTAssertEqual(model.files.map(\.originalFilename), ["001 - Kick.wav", "002 - Snare.wav"])
        XCTAssertEqual(model.proposals.count, 2)
    }
}

final class AppLocalizationTests: XCTestCase {
    @MainActor
    func testLanguageSwitchUpdatesCopyAndPersistsPreference() {
        let suiteName = "F-Renamer-Localization-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let copy = AppLocalization(defaults: defaults, language: .en)

        XCTAssertEqual(copy.text("app.subtitle"), "Multitrack audio filename cleaner")
        XCTAssertEqual(copy.userMessage("A new name is required."), "A new name is required.")
        XCTAssertEqual(copy.userMessage("Renamed 2 files."), "Renamed 2 files.")
        copy.setLanguage(.ru)
        XCTAssertEqual(copy.text("app.subtitle"), "Очистка имён многодорожечных аудиофайлов")
        XCTAssertEqual(copy.userMessage("A new name is required."), "Введите новое имя.")
        XCTAssertEqual(copy.userMessage("Renamed 2 files."), "Переименовано файлов: 2.")
        XCTAssertEqual(defaults.string(forKey: "app.language"), "ru")
        XCTAssertEqual(AppLocalization(defaults: defaults).language, .ru)
    }
}

final class SelectedRenameTests: XCTestCase {
    @MainActor
    func testRenamesOnlySelectedProposal() async throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("001 - vocal alex.wav")
        let second = folder.appendingPathComponent("002 - bass.wav")
        try touch(first)
        try touch(second)

        let model = RenamePreviewViewModel()
        model.load(urls: [folder])
        model.selectAll(false)
        model.setSelected(true, id: try XCTUnwrap(model.proposals.first { $0.originalFilename == first.lastPathComponent }?.id))
        XCTAssertEqual(model.selectedRenameCount, 1)
        XCTAssertTrue(model.canRename)

        await model.rename()

        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Vocal Alex.wav").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertEqual(model.files.count, 1)
        XCTAssertEqual(model.proposals.map(\.originalFilename), ["002 - bass.wav"])
    }

    @MainActor
    func testRenameCountTracksEditedTargetsAndSelection() throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("001 - Kick.wav")
        let second = folder.appendingPathComponent("002 - Snare.wav")
        try touch(first)
        try touch(second)

        let model = RenamePreviewViewModel()
        model.load(urls: [folder])
        XCTAssertEqual(model.renameCount, 2)
        XCTAssertEqual(model.selectedRenameCount, 2)

        model.selectAll(false)
        XCTAssertEqual(model.renameCount, 2)
        XCTAssertEqual(model.selectedRenameCount, 0)

        let firstID = try XCTUnwrap(model.proposals.first { $0.originalFilename == first.lastPathComponent }?.id)
        model.setSelected(true, id: firstID)
        XCTAssertEqual(model.selectedRenameCount, 1)

        model.updateProposal(id: firstID, name: first.lastPathComponent)
        XCTAssertEqual(model.renameCount, 1)
        XCTAssertEqual(model.selectedRenameCount, 0)
    }
}

final class ProposedNameResolverTests: XCTestCase {
    func testNumbersDuplicateTargetsInStableOrderAndSkipsOccupiedSlots() throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("source-a.wav")
        let second = folder.appendingPathComponent("source-b.wav")
        try touch(first); try touch(second)
        try touch(folder.appendingPathComponent("Name 1.wav"))
        try touch(folder.appendingPathComponent("Name 3.wav"))

        let resolved = ProposedNameResolver().resolve([
            proposal(first, "Name.wav"), proposal(second, "Name.wav")
        ])

        XCTAssertEqual(resolved.map(\.proposedFilename), ["Name 2.wav", "Name 4.wav"])
        XCTAssertEqual(resolved.map(\.reasons), [[.collisionNumber(2)], [.collisionNumber(4)]])
        XCTAssertTrue(RenameValidator().validate(resolved).isEmpty)
    }

    func testLeavesUniqueNamesWithMeaningfulExistingNumbersUntouched() throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("source-a.wav")
        let second = folder.appendingPathComponent("source-b.wav")
        try touch(first); try touch(second)

        let resolved = ProposedNameResolver().resolve([
            proposal(first, "Vocal Alex 1.wav"), proposal(second, "Vocal Alex 2.wav")
        ])

        XCTAssertEqual(resolved.map(\.proposedFilename), ["Vocal Alex 1.wav", "Vocal Alex 2.wav"])
    }

    func testKeepsManualTargetAndNumbersOnlyAutomaticDuplicates() throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let automatic = folder.appendingPathComponent("source-a.wav")
        let manual = folder.appendingPathComponent("source-b.wav")
        try touch(automatic); try touch(manual)
        var manuallyEdited = proposal(manual, "Name.wav")
        manuallyEdited.isManualEdit = true
        manuallyEdited.status = .manual
        manuallyEdited.reasons = [.manual]

        let resolved = ProposedNameResolver().resolve([proposal(automatic, "Name.wav"), manuallyEdited])

        XCTAssertEqual(resolved.map(\.proposedFilename), ["Name 1.wav", "Name.wav"])
        XCTAssertTrue(resolved[1].isManualEdit)
    }

    func testCombinesCapitalizationAndDuplicateNumbering() throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let names = ["0001 - vocal alex.wav", "0002 - vocal alex.wav"]
        for name in names { try touch(folder.appendingPathComponent(name)) }

        let scanned = try FileScanner().scan(urls: [folder])
        let resolved = ProposedNameResolver().resolve(FilenameAnalyzer().analyze(scanned, capitalizeNames: true))

        XCTAssertEqual(resolved.map(\.proposedFilename), ["Vocal Alex 1.wav", "Vocal Alex 2.wav"])
        XCTAssertTrue(RenameValidator().validate(resolved).isEmpty)
    }
}

final class FinderSelectionTests: XCTestCase {
    func testExtractsOneWAVURLFromItsAdvertisedType() {
        let expectedURL = URL(fileURLWithPath: "/tmp/one.wav")
        assertExtractedURL(expectedURL, advertisedType: "com.microsoft.waveform-audio")
    }

    func testExtractsEveryURLFromMultipleWAVProviders() {
        let expectedURLs = [
            URL(fileURLWithPath: "/tmp/one.wav"),
            URL(fileURLWithPath: "/tmp/two.wav"),
            URL(fileURLWithPath: "/tmp/three.wav")
        ]
        let providers = expectedURLs.map { makeURLProvider($0, advertisedType: "com.microsoft.waveform-audio") }
        let completed = expectation(description: "all WAV provider URLs extracted")
        completed.expectedFulfillmentCount = providers.count
        let extractedURLs = URLResults()

        for provider in providers {
            FinderAttachmentURLExtractor().loadURL(from: provider) { url, error in
                XCTAssertNil(error)
                XCTAssertNotNil(url)
                if let url {
                    extractedURLs.append(url)
                }
                completed.fulfill()
            }
        }

        wait(for: [completed], timeout: 3)
        XCTAssertEqual(Set(extractedURLs.all()), Set(expectedURLs))
    }

    func testExtractsFolderURLFromItsAdvertisedType() {
        let expectedURL = URL(fileURLWithPath: "/tmp/Tracks", isDirectory: true)
        assertExtractedURL(expectedURL, advertisedType: "public.folder")
    }

    func testAcceptsOneFolderAndUnicodeWAVFilesWhileIgnoringUnsupportedItems() throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let wav = folder.appendingPathComponent("01 - Вокал Максим.wav")
        let unsupported = folder.appendingPathComponent("notes.txt")
        try touch(wav); try touch(unsupported)

        let folderSelection = try FinderSelectionFilter().filter(urls: [folder])
        XCTAssertEqual(folderSelection.urls, [folder.standardizedFileURL])
        XCTAssertEqual(folderSelection.ignoredItemCount, 0)

        let fileSelection = try FinderSelectionFilter().filter(urls: [unsupported, wav])
        XCTAssertEqual(fileSelection.urls, [wav.standardizedFileURL])
        XCTAssertEqual(fileSelection.ignoredItemCount, 1)
    }

    func testAcceptsMultipleWAVFilesFromSameFolderInInputOrderForScannerSorting() throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let ten = folder.appendingPathComponent("10 - Kick.wav")
        let two = folder.appendingPathComponent("2 - Snare.wav")
        try touch(ten); try touch(two)

        let selection = try FinderSelectionFilter().filter(urls: [ten, two])
        XCTAssertEqual(selection.urls, [ten.standardizedFileURL, two.standardizedFileURL])
        XCTAssertEqual(try FileScanner().scan(urls: selection.urls).map(\.originalFilename), ["2 - Snare.wav", "10 - Kick.wav"])
    }

    func testAcceptsWAVSymlinksFromOneFinderVisibleFolder() throws {
        let selectionFolder = try makeTemporaryFolder()
        let firstTargetFolder = try makeTemporaryFolder()
        let secondTargetFolder = try makeTemporaryFolder()
        defer {
            try? FileManager.default.removeItem(at: selectionFolder)
            try? FileManager.default.removeItem(at: firstTargetFolder)
            try? FileManager.default.removeItem(at: secondTargetFolder)
        }
        let firstTarget = firstTargetFolder.appendingPathComponent("Kick.wav")
        let secondTarget = secondTargetFolder.appendingPathComponent("Snare.wav")
        let firstLink = selectionFolder.appendingPathComponent("Kick.wav")
        let secondLink = selectionFolder.appendingPathComponent("Snare.wav")
        try touch(firstTarget)
        try touch(secondTarget)
        try FileManager.default.createSymbolicLink(at: firstLink, withDestinationURL: firstTarget)
        try FileManager.default.createSymbolicLink(at: secondLink, withDestinationURL: secondTarget)

        let selection = try FinderSelectionFilter().filter(urls: [firstLink, secondLink])

        XCTAssertEqual(selection.urls, [firstLink.standardizedFileURL, secondLink.standardizedFileURL])
    }

    func testRejectsMultipleFoldersAndWAVFilesFromDifferentFolders() throws {
        let finderError = FinderImportError.wavFilesFromDifferentFolders as NSError
        XCTAssertEqual(finderError.domain, "com.multitrackcleaner.finder-import")
        XCTAssertEqual(finderError.code, 6)

        let first = try makeTemporaryFolder()
        let second = try makeTemporaryFolder()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let firstWAV = first.appendingPathComponent("A.wav")
        let secondWAV = second.appendingPathComponent("B.wav")
        try touch(firstWAV); try touch(secondWAV)

        XCTAssertThrowsError(try FinderSelectionFilter().filter(urls: [first, second])) { error in
            XCTAssertEqual(error as? FinderImportError, .multipleFolders)
        }
        XCTAssertThrowsError(try FinderSelectionFilter().filter(urls: [firstWAV, secondWAV])) { error in
            XCTAssertEqual(error as? FinderImportError, .wavFilesFromDifferentFolders)
        }
    }

    @MainActor
    func testPasteboardHandoffClaimsOneTimeRequestAndRouterParsesOnlyOpaqueImportURL() throws {
        let now = Date()
        let pasteboard = FinderImportPasteboard(now: { now })
        let request = try pasteboard.write(entries: [.init(bookmarkData: Data([1, 2, 3]), displayName: "Tracks")])

        XCTAssertEqual(try pasteboard.claim(id: request.id).entries.count, 1)
        XCTAssertThrowsError(try pasteboard.claim(id: request.id)) { error in
            XCTAssertEqual(error as? FinderImportError, .unavailableRequest)
        }

        let router = ApplicationInputRouter(pasteboard: pasteboard)
        XCTAssertEqual(try router.parseRequestID(from: URL(string: "multitrackcleaner://import/\(request.id.uuidString)")!), request.id)
        XCTAssertThrowsError(try router.parseRequestID(from: URL(string: "multitrackcleaner://import/not-a-uuid")!))
        XCTAssertThrowsError(try router.parseRequestID(from: URL(string: "multitrackcleaner://other/\(request.id.uuidString)")!))
    }

    private func assertExtractedURL(_ expectedURL: URL, advertisedType: String, file: StaticString = #filePath, line: UInt = #line) {
        let provider = makeURLProvider(expectedURL, advertisedType: advertisedType)
        let completed = expectation(description: "URL extracted for \(advertisedType)")

        FinderAttachmentURLExtractor().loadURL(from: provider) { url, error in
            XCTAssertNil(error, file: file, line: line)
            XCTAssertEqual(url, expectedURL, file: file, line: line)
            completed.fulfill()
        }

        wait(for: [completed], timeout: 3)
    }

    private func makeURLProvider(_ url: URL, advertisedType: String) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerItem(forTypeIdentifier: advertisedType) { completion, _, _ in
            completion?(url as NSURL, nil)
        }
        return provider
    }
}

final class RenameValidatorTests: XCTestCase {
    func testDetectsDuplicateNormalizedOutputs() {
        let folder = try! makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("Бочка.wav")
        let second = folder.appendingPathComponent("Кик.wav")
        try! touch(first); try! touch(second)
        let proposals = [
            proposal(first, "Kick.wav"), proposal(second, "Kick.wav")
        ]
        let issues = RenameValidator().validate(proposals)
        XCTAssertEqual(issues.count, 2)
        XCTAssertTrue(issues.allSatisfy { $0.status == .conflict })
    }

    func testAllowsSameTargetNameInDifferentFolders() throws {
        let firstFolder = try makeTemporaryFolder()
        let secondFolder = try makeTemporaryFolder()
        defer {
            try? FileManager.default.removeItem(at: firstFolder)
            try? FileManager.default.removeItem(at: secondFolder)
        }
        let first = firstFolder.appendingPathComponent("source.wav")
        let second = secondFolder.appendingPathComponent("source.wav")
        try touch(first); try touch(second)

        XCTAssertTrue(RenameValidator().validate([proposal(first, "Name.wav"), proposal(second, "Name.wav")]).isEmpty)
    }

    func testDetectsExistingExternalTargetAndInvalidExtension() {
        let folder = try! makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("0001 - Kick.wav")
        let existing = folder.appendingPathComponent("Kick.wav")
        try! touch(source); try! touch(existing)
        XCTAssertEqual(RenameValidator().validate([proposal(source, "Kick.wav")]).first?.status, .conflict)
        XCTAssertEqual(RenameValidator().validate([proposal(source, "Kick.mp3")]).first?.status, .invalid)

        let unchanged = proposal(existing, "Kick.wav")
        XCTAssertEqual(RenameValidator().validate([proposal(source, "Kick.wav"), unchanged]).first?.status, .conflict)
    }
}

final class RenameEngineTests: XCTestCase {
    func testEndToEndSyntheticMultitrackWithManualEdit() throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let sourceNames = ["0001 - conga1 - Щука.wav", "0002 - conga2 - Щука.wav", "0003 - tamburin - Щука.wav", "0034 - Vocal Anya - Щука.wav"]
        for name in sourceNames { try touch(folder.appendingPathComponent(name)) }

        var proposals = FilenameAnalyzer().analyze(try FileScanner().scan(urls: [folder]))
        let manualIndex = try XCTUnwrap(proposals.firstIndex { $0.originalFilename == "0034 - Vocal Anya - Щука.wav" })
        proposals[manualIndex].proposedFilename = "Vocal Anya Top.wav"
        proposals[manualIndex].isManualEdit = true
        proposals[manualIndex].status = .manual

        let plan = try RenamePlanner().makePlan(from: proposals)
        _ = try RenameEngine().execute(plan)

        for name in ["conga1.wav", "conga2.wav", "tamburin.wav", "Vocal Anya Top.wav"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path), name)
        }
        for name in sourceNames {
            XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path), name)
        }
    }

    func testRenamesAndSupportsSwapsTransactionally() throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let a = folder.appendingPathComponent("A.wav")
        let b = folder.appendingPathComponent("B.wav")
        try touch(a); try touch(b)
        let operations = [RenameOperation(sourceURL: a, targetURL: b), RenameOperation(sourceURL: b, targetURL: a)]
        let plan = try RenamePlanner().makePlan(from: operations)
        _ = try RenameEngine().execute(plan)
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.path))
    }

    func testRollbackRestoresSourcesWhenAStagedMoveFails() throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("0001.wav")
        let second = folder.appendingPathComponent("0002.wav")
        try touch(first); try touch(second)
        let operations = [RenameOperation(sourceURL: first, targetURL: folder.appendingPathComponent("A.wav")), RenameOperation(sourceURL: second, targetURL: folder.appendingPathComponent("B.wav"))]
        let access = FailingFileAccess(failOnMove: 2)
        let plan = RenamePlan(operations: operations)
        XCTAssertThrowsError(try RenameEngine(fileAccess: access).execute(plan))
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("A.wav").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("B.wav").path))
    }
}

private final class FailingFileAccess: FileAccess {
    private let manager = FileManager.default
    private let failOnMove: Int
    private var moveCount = 0

    init(failOnMove: Int) { self.failOnMove = failOnMove }
    func fileExists(at url: URL) -> Bool { manager.fileExists(atPath: url.path) }
    func moveItem(at sourceURL: URL, to targetURL: URL) throws {
        moveCount += 1
        if moveCount == failOnMove { throw CocoaError(.fileWriteUnknown) }
        try manager.moveItem(at: sourceURL, to: targetURL)
    }
}

private func proposal(_ url: URL, _ proposed: String) -> RenameProposal {
    RenameProposal(sourceURL: url, originalFilename: url.lastPathComponent, proposedFilename: proposed, status: .proposed, reasons: [], confidence: .medium, isManualEdit: false, validationMessage: nil)
}

private func makeTemporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("MultitrackCleanerTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func touch(_ url: URL) throws {
    guard FileManager.default.createFile(atPath: url.path, contents: Data()) else {
        throw CocoaError(.fileWriteUnknown)
    }
}
