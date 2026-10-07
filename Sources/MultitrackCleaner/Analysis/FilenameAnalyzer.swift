import Foundation

struct FilenameAnalyzer {
    private let tokenizer = FilenameTokenizer()
    private let numberDetector = NumberPrefixDetector()
    private let segmentDetector = CommonSegmentDetector()
    private let normalizer = InstrumentNormalizer()
    private let confidenceScorer = ConfidenceScorer()

    func analyze(_ files: [AudioFile], capitalizeNames: Bool = false) -> [RenameProposal] {
        let rawBases = files.map { tokenizer.normalizedBaseName($0.baseName) }
        let numberDetections = rawBases.map { numberDetector.candidate(in: $0) }
        let numberConfirmed = zip(rawBases, numberDetections).map { base, detection in
            detection.map { numberDetector.isConfirmed($0, in: rawBases) } ?? false
        }
        let numberRemovedBases = zip(rawBases, zip(numberDetections, numberConfirmed)).map { base, pair in
            pair.1 ? pair.0?.remainder ?? base : base
        }
        let tokenLists = numberRemovedBases.map(tokenizer.segments(in:))
        let common = segmentDetector.detect(in: tokenLists)

        return files.indices.map { index in
            var segments = tokenLists[index]
            var reasons: [RenameReason] = []
            if numberConfirmed[index] { reasons.append(.numericPrefix) }

            let canRemoveLeft = common.left != nil && segments.count > 1 && hasMeaningfulRemainder(afterRemovingLeft: segments, common: common)
            if canRemoveLeft, let left = common.left {
                segments.removeFirst()
                reasons.append(.commonLeftSegment(left))
            }

            let canRemoveRight = common.right != nil && segments.count > 1 && hasMeaningfulRemainder(afterRemovingRight: segments, common: common)
            if canRemoveRight, let right = common.right {
                segments.removeLast()
                reasons.append(.commonRightSegment(right))
            }

            let candidate = tokenizer.join(segments)
            let normalized = normalizer.normalize(candidate)
            if let source = normalized.matchedSource {
                reasons.append(.normalizedInstrument(source))
            }
            let name = normalized.value.isEmpty ? files[index].originalFilename : normalized.value + ".wav"
            let proposed = capitalizeNames ? NameCapitalizer().capitalizeFilename(name) : name
            if proposed != name { reasons.append(.capitalizedName) }
            let changed = proposed != files[index].originalFilename
            if !changed { reasons.append(.ambiguous) }
            let confidence = confidenceScorer.score(changed: changed, reasons: reasons)
            return RenameProposal(
                sourceURL: files[index].url,
                originalFilename: files[index].originalFilename,
                proposedFilename: proposed,
                status: changed ? .proposed : .unchanged,
                reasons: reasons,
                confidence: confidence,
                isManualEdit: false,
                validationMessage: nil
            )
        }
    }

    private func hasMeaningfulRemainder(afterRemovingLeft segments: [String], common: CommonSegments) -> Bool {
        let result = Array(segments.dropFirst())
        guard !result.isEmpty else { return false }
        let candidate = tokenizer.join(result)
        return normalizer.isKnownTrackName(candidate) || result.count > 1 || candidate.count >= 3
    }

    private func hasMeaningfulRemainder(afterRemovingRight segments: [String], common: CommonSegments) -> Bool {
        let result = Array(segments.dropLast())
        guard !result.isEmpty else { return false }
        let candidate = tokenizer.join(result)
        return normalizer.isKnownTrackName(candidate) || result.count > 1 || candidate.count >= 3
    }
}

struct NameCapitalizer {
    private let technicalTokens: Set<String> = ["MIDI", "FX", "OH", "L", "R", "LR", "VCA", "DI", "AMBIENCE"]

    func capitalizeFilename(_ filename: String) -> String {
        let url = URL(fileURLWithPath: filename)
        let extensionPart = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        guard !base.isEmpty else { return filename }

        let capitalizedBase = base
            .split(separator: " ", omittingEmptySubsequences: false)
            .map(capitalizeHyphenatedWord)
            .joined(separator: " ")
        return extensionPart.isEmpty ? capitalizedBase : "\(capitalizedBase).\(extensionPart)"
    }

    private func capitalizeHyphenatedWord(_ word: Substring) -> String {
        word
            .split(separator: "-", omittingEmptySubsequences: false)
            .map(capitalizeWord)
            .joined(separator: "-")
    }

    private func capitalizeWord(_ word: Substring) -> String {
        let value = String(word)
        let uppercased = value.uppercased()
        if technicalTokens.contains(uppercased) { return uppercased }
        guard let first = value.first, first.isLetter else { return value }
        return first.uppercased() + String(value.dropFirst())
    }
}
