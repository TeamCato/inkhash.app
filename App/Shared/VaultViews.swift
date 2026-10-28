import InkhashCore
import KennelKit
import KennelKitUI
import SwiftUI

/// End-to-end encryption's windows from KennelKitUI (Kennel ADR 0043, 0065, ADR 0082): set up, unlock, add an own device.
/// The same windows and the same key as in every
/// teamCato app. Where encryption is chosen (a new encrypted workspace), `then` runs right after setting up or unlocking.
enum VaultSheet: String, Identifiable {
    case setUp
    case open
    case addDevice

    var id: String { rawValue }
}

struct VaultSheetView: View {
    @Environment(AppModel.self) private var model
    let sheet: VaultSheet
    var then: (@MainActor () async -> String?)?

    #if os(macOS)
    /// On the Mac every app unlocks once itself (Kennel ADR 0065): say where the QR code can come from, without naming
    /// other apps (ADR 0085).
    static let hint: String? =
        "Auf einem anderen Gerät schon freigeschaltet? In inkhash zeigt dort Einstellungen › Kennel › Verschlüsselung „Eigenes Gerät hinzufügen …“ einen QR-Code. Hat dieser Mac keine Kamera, nimm den Wiederherstellungsschlüssel."
    #else
    static let hint: String? = nil
    #endif

    var body: some View {
        NavigationStack {
            switch sheet {
            case .setUp:
                KennelVaultSetupView(what: "Notizen verschlüsselter Workspaces", confirmTitle: then == nil ? "Einrichten" : "Anlegen") {
                    key in
                    if let failure = await model.createVault(key) { return failure }
                    return await then?()
                }
            case .open:
                KennelVaultUnlockView(
                    isFromInkhash: model.vaultFromInkhash, hint: Self.hint,
                    confirmTitle: then == nil ? "Freischalten" : "Anlegen",
                    openWithKey: { key in
                        if let failure = await model.openVault(key) { return failure }
                        return await then?()
                    },
                    openWithCode: { code in
                        if let failure = await model.openVault(pairingCode: code) { return failure }
                        return await then?()
                    })
            case .addDevice:
                KennelPairingOfferView(
                    offer: { await model.offerPairing().mapError { KennelVaultMessage($0.message) } },
                    withdraw: { await model.withdraw($0) })
            }
        }
        .kennelBrand(.inkhash)
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 520)
        #endif
    }
}

extension AppModel {
    /// What „Freischalten …“ opens: setting up without a key, else unlocking.
    var vaultSheetToOpen: VaultSheet {
        if case .some(.none) = vaultState { return .setUp }
        return .open
    }

    /// „Verschlüsselung“ on the Kennel page, only with a key or encrypted workspaces (Kennel ADR 0065). Confirming team
    /// members is left out: inkhash's workspaces are each person's own.
    func vaultSection(_ show: @escaping @MainActor (VaultSheet) -> Void) -> KennelVaultSection? {
        let hasEncrypted = registry.workspaces.contains { $0.link?.sealed == true }
        let state: KennelVaultSection.State
        switch vaultState {
        case .none?:
            guard hasEncrypted else { return nil }
            state = .none
        case .needsKey?: state = .locked
        case .ready?: state = .open
        case .unknown?, .failed?, nil: return nil
        }
        return KennelVaultSection(
            state: state, setUp: { show(.setUp) }, open: { show(.open) }, addDevice: { show(.addDevice) },
            lock: { Task { await self.lockVault() } })
    }
}
