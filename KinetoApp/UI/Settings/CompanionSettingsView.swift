import CoreGraphics
import SwiftUI

struct CompanionSettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Floating companion") {
                Toggle("Show companion during active capture", isOn: $model.petModeEnabled)

                Text("Decorative only; it may appear in screen shares and screenshots.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if model.petModeEnabled {
                    Picker(
                        "Pet theme",
                        selection: Binding<FloatingCaptionPetAppearance>(
                            get: { model.petAppearance },
                            set: { appearance in
                                guard let theme = FloatingCaptionPetCatalog.builtInThemes.first(
                                    where: { $0.appearance == appearance }
                                ) else {
                                    return
                                }
                                model.selectPetTheme(theme)
                            }
                        )
                    ) {
                        ForEach(FloatingCaptionPetCatalog.builtInThemes) { theme in
                            Text(theme.title).tag(theme.appearance)
                        }
                    }
                    Picker("Size", selection: $model.petSize) {
                        ForEach(FloatingCaptionPetSize.allCases, id: \.self) { size in
                            Text(size.title).tag(size)
                        }
                    }
                    Picker("Motion", selection: $model.petMotion) {
                        ForEach(FloatingCaptionPetMotion.allCases, id: \.self) { motion in
                            Text(motion.title).tag(motion)
                        }
                    }
                    ColorPicker(
                        "Leaf accent",
                        selection: Binding<Color>(
                            get: { Color(cgColor: model.petAccent.cgColor) },
                            set: { color in
                                guard let cgColor = color.cgColor,
                                      let accent = FloatingCaptionPetAccent(cgColor: cgColor)
                                else {
                                    return
                                }
                                model.petAccent = accent
                            }
                        ),
                        supportsOpacity: false
                    )
                    Text("Accent color affects companion pixels only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 390)
        .padding(20)
    }
}
