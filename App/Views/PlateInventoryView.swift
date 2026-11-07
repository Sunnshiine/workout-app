import SwiftUI

struct PlateInventoryView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.themePalette) private var palette

    private var inventory: PlateInventory {
        settings.plateInventory
    }

    var body: some View {
        Form {
            Section {
                Picker("Bar", selection: barSelection) {
                    ForEach(Bar.allCases, id: \.self) { bar in
                        Text(bar.label)
                            .tag(bar)
                            .accessibilityIdentifier("settings-bar-\(bar.rawValue)")
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Bar").foregroundStyle(palette.textSecondary)
            }
            .listRowBackground(palette.surface)

            Section {
                ForEach(PlateDenomination.allCases, id: \.self) { plate in
                    Toggle("\(plate.label) lb", isOn: stocked(plate))
                        .tint(palette.actionFill)
                        .accessibilityIdentifier("settings-plate-\(plate.label)")
                }
            } header: {
                Text("Plates").foregroundStyle(palette.textSecondary)
            } footer: {
                if inventory.plates.isEmpty {
                    Text("With no plates on, the Bar alone is what loads.")
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .listRowBackground(palette.surface)
        }
        .scrollContentBackground(.hidden)
        .background(palette.paperBackground.ignoresSafeArea())
        .navigationTitle("Bar and Plates")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var barSelection: Binding<Bar> {
        Binding {
            inventory.bar
        } set: { bar in
            settings.setPlateInventory(inventory.withBar(bar))
        }
    }

    private func stocked(_ plate: PlateDenomination) -> Binding<Bool> {
        Binding {
            inventory.plates.contains(plate)
        } set: { isStocked in
            settings.setPlateInventory(inventory.with(plate, stocked: isStocked))
        }
    }
}
