import Foundation
import Observation

@MainActor
@Observable
final class ServiceBriefViewModel {
    var sections = BriefSections()
    var status = "empty"
    var isBusy = false
    var errorText: String?
    var promptText = ""

    // Document attach
    var showPasteSheet = false
    var pasteText = ""
    var pendingGaps: [String] = []   // sections still thin after autodraft/extract

    // Interview
    struct InterviewTurn: Identifiable, Sendable { let id = UUID(); let role: String; let text: String }
    var interviewActive = false
    var interviewTurns: [InterviewTurn] = []
    var interviewOptions: [String] = []
    var interviewAnswer = ""
    private var interviewTargets: [String]?

    private let repo: CrmDataProviding
    let serviceId: String

    init(serviceId: String, repo: CrmDataProviding = CrmRepository()) {
        self.serviceId = serviceId
        self.repo = repo
    }

    var isEmpty: Bool { status != "ready" }

    func load() async {
        if let b = try? await repo.fetchServiceBrief(serviceId: serviceId) {
            sections = b.sections
            status = b.status
        }
    }

    // First-pass draft from connection signals only.
    func autodraft() async {
        await runCapturingGaps {
            try await self.repo.synthesizeBrief(serviceId: self.serviceId, document: nil, transcript: nil, currentSections: nil, userPrompt: nil)
        }
    }

    // Natural-language edit: Claude rewrites the brief at its discretion.
    func applyPrompt() async {
        let p = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Check isBusy before clearing: `run` also guards isBusy and would no-op a
        // concurrent send, so clearing first would silently discard the typed text.
        guard !p.isEmpty, !isBusy else { return }
        promptText = ""
        await run {
            try await self.repo.synthesizeBrief(serviceId: self.serviceId, document: nil, transcript: nil, currentSections: self.sections, userPrompt: p)
        }
    }

    // MARK: Document

    func ingestPaste() async {
        let t = pasteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        pasteText = ""
        showPasteSheet = false
        await runCapturingGaps {
            try await self.repo.synthesizeBrief(serviceId: self.serviceId, document: t, transcript: nil, currentSections: nil, userPrompt: nil)
        }
    }

    func ingestFile(url: URL) async {
        do {
            // Read + PDF text extraction can be slow on large files; keep it off the
            // @MainActor so the UI doesn't freeze while a big PDF is parsed.
            let text = try await Self.extractText(from: url)
            await runCapturingGaps {
                try await self.repo.synthesizeBrief(serviceId: self.serviceId, document: text, transcript: nil, currentSections: nil, userPrompt: nil)
            }
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private nonisolated static func extractText(from url: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let needs = url.startAccessingSecurityScopedResource()
            defer { if needs { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            return try DocumentTextExtractor.extract(data: data, ext: url.pathExtension)
        }.value
    }

    // MARK: Interview

    func startInterview(targets: [String]? = nil) async {
        interviewActive = true
        interviewTargets = targets
        interviewTurns = []
        interviewOptions = []
        await nextInterviewStep()
    }

    func answerInterview(_ text: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Guard isBusy before appending: nextInterviewStep no-ops while busy, so a
        // double-submit (TextField.onSubmit isn't disabled) would append a user turn
        // that never gets a reply.
        guard !t.isEmpty, !isBusy else { return }
        interviewAnswer = ""
        interviewOptions = []
        interviewTurns.append(.init(role: "user", text: t))
        await nextInterviewStep()
    }

    private func transcriptWire() -> [[String: String]] {
        interviewTurns.map { ["role": $0.role, "content": $0.text] }
    }

    private func nextInterviewStep() async {
        guard !isBusy else { return }
        isBusy = true
        errorText = nil
        defer { isBusy = false }
        do {
            let step = try await repo.interviewStep(serviceId: serviceId, transcript: transcriptWire(), targetSections: interviewTargets)
            let finished: Bool
            switch step {
            case .question(let q, let opts):
                // A blank question means off-spec model output; treat it as "done"
                // and synthesize rather than showing an empty prompt that stalls.
                if q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    finished = true
                } else {
                    interviewTurns.append(.init(role: "assistant", text: q))
                    interviewOptions = opts
                    finished = false
                }
            case .done:
                finished = true
            }
            if finished {
                interviewActive = false
                let b = try await repo.synthesizeBrief(serviceId: serviceId, document: nil, transcript: transcriptWire(), currentSections: sections, userPrompt: nil)
                sections = b.sections
                status = b.status
                pendingGaps = b.gaps ?? []
            }
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            interviewActive = false
        }
    }

    // MARK: Helpers

    private func run(_ op: @escaping () async throws -> ServiceBrief) async {
        guard !isBusy else { return }
        isBusy = true
        errorText = nil
        defer { isBusy = false }
        do {
            let b = try await op()
            sections = b.sections
            status = b.status
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func runCapturingGaps(_ op: @escaping () async throws -> ServiceBrief) async {
        guard !isBusy else { return }
        isBusy = true
        errorText = nil
        defer { isBusy = false }
        do {
            let b = try await op()
            sections = b.sections
            status = b.status
            pendingGaps = b.gaps ?? []
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
