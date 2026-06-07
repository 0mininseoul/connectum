import SwiftUI
import Observation

@MainActor
@Observable
final class ConnectionsViewModel {
    var supabase: [ConnAccount] = []
    var amplitude: [ConnAccount] = []
    var axiom: [ConnAccount] = []
    var status: String?
    var isBusy = false
    private let repo: CrmDataProviding
    init(repo: CrmDataProviding = CrmRepository()) { self.repo = repo }

    func load() async {
        do {
            supabase = try await repo.fetchSupabaseAccounts()
            amplitude = try await repo.fetchAmplitudeAccounts()
            axiom = try await repo.fetchAxiomAccounts()
        } catch { status = "불러오기 실패: \(error)" }
    }
    func addSupabase(pat: String, label: String) async {
        isBusy = true; defer { isBusy = false }
        do { try await repo.connectSupabasePAT(pat: pat, label: label.isEmpty ? "Supabase" : label); status = "Supabase 연결됨"; await load() }
        catch { status = "Supabase 연결 실패: \(error)" }
    }
    func addAmplitude(key: String, secret: String, region: String, label: String) async {
        isBusy = true; defer { isBusy = false }
        do { try await repo.connectAmplitude(apiKey: key, secretKey: secret, region: region.isEmpty ? "us" : region, label: label.isEmpty ? "Amplitude" : label); status = "Amplitude 연결됨"; await load() }
        catch { status = "Amplitude 연결 실패: \(error)" }
    }
    func addAxiom(token: String, label: String) async {
        isBusy = true; defer { isBusy = false }
        do { let ds = try await repo.connectAxiom(token: token, label: label.isEmpty ? "Axiom" : label); status = "Axiom 연결됨 (데이터셋 \(ds.count)개)"; await load() }
        catch { status = "Axiom 연결 실패: \(error)" }
    }
}

struct ConnectionsView: View {
    @State private var vm = ConnectionsViewModel()
    // form state
    @State private var sbPat = ""; @State private var sbLabel = ""
    @State private var amKey = ""; @State private var amSecret = ""; @State private var amRegion = "us"; @State private var amLabel = ""
    @State private var axToken = ""; @State private var axLabel = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                Text("연동").font(Typography.cardTitle).foregroundStyle(Palette.ink)
                if let s = vm.status { Text(s).font(Typography.caption).foregroundStyle(Palette.accentBlue) }

                section(title: "Supabase (PAT)", accounts: vm.supabase) {
                    field("Personal Access Token", $sbPat, secure: true)
                    field("레이블", $sbLabel)
                    addButton { await vm.addSupabase(pat: sbPat, label: sbLabel); sbPat = "" }
                }
                section(title: "Amplitude", accounts: vm.amplitude) {
                    field("API Key", $amKey); field("Secret Key", $amSecret, secure: true)
                    field("리전 (us/eu)", $amRegion); field("레이블", $amLabel)
                    addButton { await vm.addAmplitude(key: amKey, secret: amSecret, region: amRegion, label: amLabel); amKey = ""; amSecret = "" }
                }
                section(title: "Axiom", accounts: vm.axiom) {
                    field("API Token", $axToken, secure: true); field("레이블", $axLabel)
                    addButton { await vm.addAxiom(token: axToken, label: axLabel); axToken = "" }
                }
            }
            .padding(Spacing.xl).frame(maxWidth: 640, alignment: .leading)
        }
        .background(Palette.canvas)
        .task { await vm.load() }
    }

    @ViewBuilder private func section<C: View>(title: String, accounts: [ConnAccount], @ViewBuilder _ form: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title).font(Typography.body).foregroundStyle(Palette.ink)
            ForEach(accounts) { a in
                HStack { Circle().fill(Palette.accentGreen).frame(width: 6, height: 6); Text(a.label).font(Typography.caption).foregroundStyle(Palette.body); Spacer() }
            }
            form()
        }
        .padding(Spacing.lg).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceCard).clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.hairline))
    }
    @ViewBuilder private func field(_ ph: String, _ text: Binding<String>, secure: Bool = false) -> some View {
        Group {
            if secure { SecureField(ph, text: text) } else { TextField(ph, text: text) }
        }
        .textFieldStyle(.plain).padding(Spacing.sm)
        .background(Palette.surfaceElevated).clipShape(RoundedRectangle(cornerRadius: Radius.button))
    }
    @ViewBuilder private func addButton(_ action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Text(vm.isBusy ? "연결 중…" : "연결").font(Typography.caption).foregroundStyle(Palette.ctaText)
                .padding(.horizontal, Spacing.md).frame(height: 28).background(Palette.ctaFill).clipShape(Capsule())
        }.buttonStyle(.plain).disabled(vm.isBusy)
    }
}
