import SwiftUI

// Connectum settings (Cmd+,). Lets the team point the app at a backend
// (writes ~/Library/Application Support/Connectum/config.json) and shows info.
struct SettingsView: View {
    @State private var url = ""
    @State private var anon = ""
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            Text("설정").font(Typography.cardTitle).foregroundStyle(Palette.ink)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("백엔드 연결").font(Typography.caption).foregroundStyle(Palette.muted)
                field("Supabase URL", $url)
                field("Anon Key", $anon)
                HStack(spacing: Spacing.sm) {
                    Button("저장") { save() }
                        .buttonStyle(.plain)
                        .font(Typography.body).foregroundStyle(Palette.ctaText)
                        .padding(.horizontal, Spacing.lg).frame(height: 32)
                        .background(Palette.ctaFill).clipShape(Capsule())
                    if saved {
                        Text("저장됨 · 앱 재시작 후 적용").font(Typography.caption).foregroundStyle(Palette.accentGreen)
                    }
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surfaceCard).clipShape(RoundedRectangle(cornerRadius: Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.hairline))

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("정보").font(Typography.caption).foregroundStyle(Palette.muted)
                Text("Connectum \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                    .font(Typography.body).foregroundStyle(Palette.body)
                Text(SupabaseClientProvider.configFileURL().path)
                    .font(Typography.caption).foregroundStyle(Palette.muted).textSelection(.enabled)
            }
            Spacer()
        }
        .padding(Spacing.xl)
        .frame(width: 480, height: 380)
        .background(Palette.canvas)
        .onAppear(perform: load)
    }

    private func field(_ ph: String, _ text: Binding<String>) -> some View {
        TextField(ph, text: text)
            .textFieldStyle(.plain).foregroundStyle(Palette.ink).padding(Spacing.sm)
            .background(Palette.surfaceElevated).clipShape(RoundedRectangle(cornerRadius: Radius.button))
    }

    private func load() {
        let (u, a) = SupabaseClientProvider.resolve()
        url = u; anon = a
    }

    private func save() {
        let fileURL = SupabaseClientProvider.configFileURL()
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: ["supabaseUrl": url, "supabaseAnonKey": anon]) {
            try? data.write(to: fileURL)
            saved = true
        }
    }
}
