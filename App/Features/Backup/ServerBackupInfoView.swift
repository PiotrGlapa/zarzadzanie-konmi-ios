import SwiftUI

/// „Kopia zapasowa na serwerze” (`horsely://server-backup`, spec 003, FR-019): informacja po dotknięciu powiadomienia serwera
/// o nieudanej kopii. Aplikacja nie ma ekranu kopii programu, a kopia telefonu to osobna sprawa (tryb samodzielny), więc ekran jest
/// prosty i działa bez sieci. Jak w Androidzie: tytuł, tekst i przycisk „Wstecz”.
struct ServerBackupInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.between * 2) {
                HIcon(name: "cloud_off", size: 40).foregroundStyle(HorselyColor.warning)
                Text("push_server_backup_text").font(.body)
                Button {
                    dismiss()
                } label: {
                    Text("common_back").font(.headline).frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
                }
                .buttonStyle(.bordered)
                .tint(HorselyColor.primary)
                .accessibilityIdentifier("server-backup-back")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.screenEdge)
            .padding(.vertical, Spacing.between)
        }
        .background(HorselyColor.background)
        .navigationTitle(tr("push_server_backup_title"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("server-backup-info")
    }
}
