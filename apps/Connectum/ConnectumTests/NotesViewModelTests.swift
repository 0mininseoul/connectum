import XCTest
@testable import Connectum

final class NotesViewModelTests: XCTestCase {
    @MainActor
    func testLoadCombinesExistingBlocksIntoSingleEditableNote() async {
        let repo = NotesRepositorySpy(blocks: [
            NoteBlock(id: "note-1", type: "text", text: "첫 메모"),
            NoteBlock(id: "note-2", type: "text", text: "둘째 메모")
        ])
        let vm = NotesViewModel(crmUserId: "user-1", repo: repo)

        await vm.load()

        XCTAssertEqual(vm.text, "첫 메모\n\n둘째 메모")
    }

    @MainActor
    func testSaveUpdatesSingleExistingNoteAndDeletesExtraBlocks() async {
        let repo = NotesRepositorySpy(blocks: [
            NoteBlock(id: "note-1", type: "text", text: "기존"),
            NoteBlock(id: "note-2", type: "text", text: "이전 블록")
        ])
        let vm = NotesViewModel(crmUserId: "user-1", repo: repo)

        await vm.load()
        vm.text = "업데이트된 메모"
        await vm.save()

        XCTAssertEqual(repo.updatedNotes, [UpdatedNote(id: "note-1", text: "업데이트된 메모")])
        XCTAssertEqual(repo.deletedNoteIds, ["note-2"])
        XCTAssertTrue(repo.addedNotes.isEmpty)
    }

    @MainActor
    func testSaveCreatesNoteWhenNoExistingBlockExists() async {
        let repo = NotesRepositorySpy()
        let vm = NotesViewModel(crmUserId: "user-1", repo: repo)

        vm.text = "새 메모"
        await vm.save()

        XCTAssertEqual(repo.addedNotes, [AddedNote(crmUserId: "user-1", text: "새 메모")])
        XCTAssertTrue(repo.updatedNotes.isEmpty)
        XCTAssertTrue(repo.deletedNoteIds.isEmpty)
    }

    @MainActor
    func testExistingNoteCanBeSavedAfterUserClearsText() async {
        let repo = NotesRepositorySpy(blocks: [
            NoteBlock(id: "note-1", type: "text", text: "삭제할 메모")
        ])
        let vm = NotesViewModel(crmUserId: "user-1", repo: repo)

        await vm.load()
        vm.text = ""

        XCTAssertTrue(vm.canSave)
    }
}

private struct AddedNote: Equatable {
    let crmUserId: String
    let text: String
}

private struct UpdatedNote: Equatable {
    let id: String
    let text: String
}

private final class NotesRepositorySpy: CrmDataProviding, @unchecked Sendable {
    var blocks: [NoteBlock]
    var addedNotes: [AddedNote] = []
    var updatedNotes: [UpdatedNote] = []
    var deletedNoteIds: [String] = []

    init(blocks: [NoteBlock] = []) {
        self.blocks = blocks
    }

    func fetchNoteBlocks(crmUserId: String) async throws -> [NoteBlock] {
        blocks
    }

    func addNoteBlock(crmUserId: String, text: String) async throws {
        addedNotes.append(AddedNote(crmUserId: crmUserId, text: text))
    }

    func updateNoteBlock(id: String, text: String) async throws {
        updatedNotes.append(UpdatedNote(id: id, text: text))
    }

    func deleteNoteBlock(id: String) async throws {
        deletedNoteIds.append(id)
    }
}

private extension CrmDataProviding {
    func fetchServices() async throws -> [Service] { throw XCTSkip("unused") }
    func syncService(serviceId: String) async throws { throw XCTSkip("unused") }
    func deleteService(serviceId: String) async throws { throw XCTSkip("unused") }
    func fetchUsers(serviceId: String) async throws -> [CrmUser] { throw XCTSkip("unused") }
    func excludeUser(crmUserId: String, reason: String?) async throws { throw XCTSkip("unused") }
    func fetchEvents(crmUserId: String, limit: Int) async throws -> [CrmUserEvent] { throw XCTSkip("unused") }
    func setContactStatus(crmUserId: String, status: String) async throws { throw XCTSkip("unused") }
    func regenerateSummary(crmUserId: String) async throws -> String { throw XCTSkip("unused") }
    func fetchChannelRecords(crmUserId: String) async throws -> [ChannelRecord] { throw XCTSkip("unused") }
    func addChannelRecord(crmUserId: String, channel: String, occurredAt: String, body: String) async throws { throw XCTSkip("unused") }
    func fetchHistory(crmUserId: String) async throws -> [HistoryEntry] { throw XCTSkip("unused") }
    func addHistory(crmUserId: String, entryDate: String, memo: String, imageData: Data?, fileExt: String) async throws { throw XCTSkip("unused") }
    func fetchMetrics(serviceId: String) async throws -> DashboardMetrics { throw XCTSkip("unused") }
    func previewKPI(serviceId: String, title: String, prompt: String) async throws -> KPIPreview { throw XCTSkip("unused") }
    func recomputeKPI(serviceId: String, spec: KPISpec) async throws -> Double { throw XCTSkip("unused") }
    func fetchKPIs(serviceId: String) async throws -> [DashboardKPIDefinition] { throw XCTSkip("unused") }
    func seedSystemKPIs(serviceId: String) async throws { throw XCTSkip("unused") }
    func insertKPI(serviceId: String, title: String, prompt: String, spec: KPISpec, unit: String, value: Double, position: Double) async throws { throw XCTSkip("unused") }
    func deleteKPIRow(id: String) async throws { throw XCTSkip("unused") }
    func renameKPIRow(id: String, title: String) async throws { throw XCTSkip("unused") }
    func updateKPIValue(id: String, value: Double) async throws { throw XCTSkip("unused") }
    func updateKPIPosition(id: String, position: Double) async throws { throw XCTSkip("unused") }
    func fetchViews() async throws -> [SavedView] { throw XCTSkip("unused") }
    func createView(name: String, config: ViewConfig) async throws { throw XCTSkip("unused") }
    func fetchSupabaseAccounts() async throws -> [ConnAccount] { throw XCTSkip("unused") }
    func fetchAmplitudeAccounts() async throws -> [ConnAccount] { throw XCTSkip("unused") }
    func fetchAxiomAccounts() async throws -> [ConnAccount] { throw XCTSkip("unused") }
    func supabaseOAuthAuthorizeURL(state: String) async throws -> URL { throw XCTSkip("unused") }
    func connectSupabaseOAuth(code: String, state: String) async throws { throw XCTSkip("unused") }
    func connectSupabasePAT(pat: String, label: String) async throws { throw XCTSkip("unused") }
    func connectAmplitude(projectName: String, apiKey: String, secretKey: String, region: String) async throws { throw XCTSkip("unused") }
    func connectAxiom(token: String) async throws -> [String] { throw XCTSkip("unused") }
    func deleteSupabaseAccount(id: String) async throws { throw XCTSkip("unused") }
    func deleteAmplitudeAccount(id: String) async throws { throw XCTSkip("unused") }
    func deleteAxiomAccount(id: String) async throws { throw XCTSkip("unused") }
    func updateServiceSupabaseAccount(serviceId: String, accountId: String) async throws { throw XCTSkip("unused") }
    func updateServiceAmplitudeAccount(serviceId: String, accountId: String) async throws { throw XCTSkip("unused") }
    func updateServiceAxiomAccount(serviceId: String, accountId: String, dataset: String?) async throws { throw XCTSkip("unused") }
    func fetchSupabaseAccountProfile(id: String) async throws -> String? { throw XCTSkip("unused") }
    func listAxiomDatasets(accountId: String) async throws -> [String] { throw XCTSkip("unused") }
    func listProjects(supabaseAccountId: String) async throws -> [ProjectInfo] { throw XCTSkip("unused") }
    func listTables(supabaseAccountId: String, projectRef: String) async throws -> [TableInfo] { throw XCTSkip("unused") }
    func createService(name: String, supabaseAccountId: String, projectRef: String, projectName: String?, tables: [ServiceTableSpec], amplitudeAccountId: String?, amplitudeProjectName: String?, axiomAccountId: String?, axiomDataset: String?) async throws -> String { throw XCTSkip("unused") }
    func listColumns(supabaseAccountId: String, projectRef: String, schema: String, table: String) async throws -> [ColumnInfo] { throw XCTSkip("unused") }
    func fetchDisplayColumns(serviceId: String) async throws -> [String] { throw XCTSkip("unused") }
    func updateDisplayColumns(serviceId: String, columns: [String]) async throws { throw XCTSkip("unused") }
    func fetchServiceTables(serviceId: String) async throws -> [ServiceTableInfo] { throw XCTSkip("unused") }
    func addRelatedTable(serviceId: String, schema: String, table: String) async throws { throw XCTSkip("unused") }
    func removeServiceTable(id: String) async throws { throw XCTSkip("unused") }
    func fetchMirroredRows(serviceTableId: String, limit: Int) async throws -> [MirroredRow] { throw XCTSkip("unused") }
    func fetchAIAccount() async throws -> AIAccount? { throw XCTSkip("unused") }
    func connectClaude(code: String, state: String?, codeVerifier: String, redirectURI: String) async throws { throw XCTSkip("unused") }
    func disconnectClaude(id: String) async throws { throw XCTSkip("unused") }
    func fetchChatMessages(serviceId: String) async throws -> [ChatMessage] { throw XCTSkip("unused") }
    func saveChatMessage(serviceId: String, role: String, content: String) async throws { throw XCTSkip("unused") }
    func fetchServiceBrief(serviceId: String) async throws -> ServiceBrief? { throw XCTSkip("unused") }
    func synthesizeBrief(serviceId: String, document: String?, transcript: [[String: String]]?, currentSections: BriefSections?, userPrompt: String?) async throws -> ServiceBrief { throw XCTSkip("unused") }
    func interviewStep(serviceId: String, transcript: [[String: String]], targetSections: [String]?) async throws -> InterviewStep { throw XCTSkip("unused") }
    func fetchLatestRelease() async throws -> AppRelease? { throw XCTSkip("unused") }
}
