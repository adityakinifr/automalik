import SwiftUI

struct KeyScalePicker: View {
    @Binding var selectedRoot: NoteName
    @Binding var selectedScale: ScaleType

    var body: some View {
        VStack(spacing: 12) {
            Text("Musical Key")
                .font(.headline)

            HStack(spacing: 16) {
                // Root note picker
                VStack(spacing: 4) {
                    Text("Root Note")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Root", selection: $selectedRoot) {
                        ForEach(NoteName.allCases) { note in
                            Text(note.displayName).tag(note)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 80)
                }

                // Scale picker
                VStack(spacing: 4) {
                    Text("Scale")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Scale", selection: $selectedScale) {
                        ForEach(ScaleType.allCases) { scale in
                            Text(scale.rawValue).tag(scale)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 160)
                }
            }

            // Show notes in key
            let key = MusicalKey(root: selectedRoot, scale: selectedScale)
            let noteNames = selectedScale.intervals.map { interval -> String in
                let semitone = (selectedRoot.rawValue + interval) % 12
                return NoteName(rawValue: semitone)?.displayName ?? "?"
            }
            Text("Notes: \(noteNames.joined(separator: " - "))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}
