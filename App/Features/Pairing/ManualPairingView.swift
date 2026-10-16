import HorselyCore
import HorselyKit
import SwiftUI

/// Wpis ręczny: adres, klucz (ukryty, z „Pokaż klucz”) i opcjonalny odcisk certyfikatu; sprawdzenie formatu przy polach.
struct ManualPairingView: View {
    let error: String?
    let onConnect: (PairingRequest) -> Void

    @State private var address = ""
    @State private var key = ""
    @State private var fingerprint = ""
    @State private var showKey = false
    @State private var addressError: String?
    @State private var keyError: String?
    @State private var fingerprintError: String?

    var body: some View {
        Form {
            if let error {
                Section { Text(error).foregroundStyle(HorselyColor.warning).accessibilityIdentifier("pairing-error") }
            }
            Section {
                TextField(tr("pairing_manual_address"), text: $address, prompt: Text("pairing_manual_address_hint"))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("pairing-address")
                if let addressError { Text(addressError).font(.footnote).foregroundStyle(HorselyColor.error) }
            } header: {
                Text("pairing_manual_address")
            }
            Section {
                HStack {
                    Group {
                        if showKey {
                            TextField(tr("pairing_manual_key"), text: $key)
                        } else {
                            SecureField(tr("pairing_manual_key"), text: $key)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("pairing-key")
                    Button(showKey ? tr("pairing_manual_key_hide") : tr("pairing_manual_key_show")) { showKey.toggle() }
                        .font(.footnote)
                }
                if let keyError { Text(keyError).font(.footnote).foregroundStyle(HorselyColor.error) }
            } header: {
                Text("pairing_manual_key")
            }
            Section {
                TextField(tr("pairing_manual_fingerprint"), text: $fingerprint, axis: .vertical)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(.footnote, design: .monospaced))
                    .accessibilityIdentifier("pairing-fingerprint")
                if let fingerprintError { Text(fingerprintError).font(.footnote).foregroundStyle(HorselyColor.error) }
            } header: {
                Text("pairing_manual_fingerprint")
            } footer: {
                Text("address_edit_fingerprint_hint")
            }
            Section {
                Button(action: connect) {
                    Text("pairing_manual_connect").font(.headline).frame(maxWidth: .infinity, minHeight: Spacing.minTouchTarget)
                }
                .buttonStyle(.primaryFilled)
                .tint(HorselyColor.primary)
                .listRowInsets(EdgeInsets())
                .accessibilityIdentifier("pairing-connect")
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle(tr("pairing_manual_title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func connect() {
        addressError = nil
        keyError = nil
        fingerprintError = nil
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        var checked: CheckedAddress?
        if trimmedAddress.isEmpty {
            addressError = tr("pairing_manual_address_required")
        } else {
            switch AddressRules.default.check(trimmedAddress) {
            case let .ok(value): checked = value
            case let .rejected(reason): addressError = reason.message
            }
        }
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.hasPrefix(PairingCodeParser.keyPrefix) || trimmedKey.count <= PairingCodeParser.keyPrefix.count {
            keyError = tr("pairing_manual_key_format")
        }
        let cleanedFingerprint = fingerprint.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: " ", with: "")
        var pin: String?
        if !cleanedFingerprint.isEmpty {
            pin = PairingCodeParser.normalizeFingerprint(cleanedFingerprint)
            if pin == nil { fingerprintError = tr("pairing_manual_fingerprint_format") }
        }
        guard let checked, keyError == nil, fingerprintError == nil else { return }
        onConnect(PairingRequest(url: checked, key: trimmedKey, certSha256: pin))
    }
}
