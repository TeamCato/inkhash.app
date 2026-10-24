import InkhashCore
import KennelKit
import KennelKitUI
import SwiftUI

/// The vault's windows from KennelKitUI (Kennel ADR 0043, ADR 0082): set up, open (with „Schlüssel nicht mehr da?“), add
/// a device. The same windows and the same vault as in every teamCato app.
enum VaultSheet: String, Identifiable {
    case setUp
    case open
    case addDevice

    var id: String { rawValue }
}

struct VaultSheetView: View {
    @Environment(AppModel.self) private var model
    let sheet: VaultSheet
    /// After „Tresor zurücksetzen“ the same window goes on with „Tresor anlegen“.
    @State private var hasReset = false

    var body: some View {
        NavigationStack {
            switch hasReset ? .setUp : sheet {
            case .setUp:
                KennelVaultSetupView(what: "Notizen verschlüsselter Workspaces") { await model.createVault($0) }
            case .open:
                KennelVaultUnlockView(
                    isFromInkhash: model.vaultFromInkhash,
                    openWithKey: { await model.openVault($0) },
                    openWithCode: { await model.openVault(pairingCode: $0) },
                    reset: { password in
                        let failure = await model.resetVault(password: password)
                        if failure == nil { hasReset = true }
                        return failure
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
    /// The sheet that opens what the vault needs next: set it up without one, else open it.
    var vaultSheetToOpen: VaultSheet {
        if case .some(.none) = vaultState { return .setUp }
        return .open
    }

    /// The vault section of the Kennel page, neutral: only needed for end-to-end encrypted workspaces (ADR 0082).
    func vaultSection(_ show: @escaping @MainActor (VaultSheet) -> Void) -> KennelVaultSection? {
        let state: KennelVaultSection.State
        switch vaultState {
        case .none?: state = .none
        case .needsKey?: state = .locked
        case .ready?: state = .open
        case .unknown?, .failed?, nil: return nil
        }
        // Confirming people is for shared containers; inkhash's workspaces are each person's own.
        return KennelVaultSection(
            state: state, setUp: { show(.setUp) }, open: { show(.open) }, addDevice: { show(.addDevice) },
            confirmPeople: { show(.addDevice) })
    }
}
