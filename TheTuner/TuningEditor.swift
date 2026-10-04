import SwiftUI

struct TuningEditor: View {
    @Environment(\.tunerTheme) private var theme
    private var style: CleanStyle { theme.style }
    let instrument: Instrument
    let original: Tuning
    let editing: Bool
    let save: (String?, String, [Int]) -> Void
    let delete: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var notes: [Int]
    @State private var confirmDelete = false

    init(instrument: Instrument, original: Tuning, editing: Bool,
         save: @escaping (String?, String, [Int]) -> Void, delete: @escaping (String) -> Void) {
        self.instrument = instrument; self.original = original; self.editing = editing
        self.save = save; self.delete = delete
        _name = State(initialValue: editing ? original.name : "")
        _notes = State(initialValue: original.notes)
    }
    private var valid: Bool { Tuning(id: "custom-draft", name: name, notes: notes).isValid }
    @State private var selectedString: Int?
    @FocusState private var nameFocused: Bool
    var body: some View {
        CleanPanel(title: editing ? "Edit tuning" : "Custom tuning", subtitle: instrument.rawValue.uppercased()) {
            TextField("Tuning name", text: $name).font(.system(size: 17)).padding(18)
                .background(style.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(style.silver, lineWidth: 1))
                .accessibilityIdentifier("tuningName").focused($nameFocused).submitLabel(.done).onSubmit { nameFocused = false }
                .onChange(of: name) { _, value in if value.count > 32 { name = String(value.prefix(32)) } }
            HStack {
                Text("\(notes.count) \(instrument == .mandolin ? "courses" : "strings")").font(.system(size: 15))
                Spacer()
                Button { selectedString = nil; notes.removeFirst() } label: { Image(systemName: "minus").frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .disabled(notes.count <= 4).accessibilityLabel("Remove string")
                Button { selectedString = nil; notes.insert(notes.first ?? 40, at: 0) } label: { Image(systemName: "plus").frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .disabled(notes.count >= 8).accessibilityLabel("Add string")
            }.padding(.horizontal, 12)
            ForEach(notes.indices, id: \.self) { i in
                CleanRow(title: "\(instrument == .mandolin ? "Course" : "String") \(notes.count - i)", detail: PitchMath.label(notes[i]), selected: selectedString == i) {
                    selectedString = selectedString == i ? nil : i
                }.accessibilityIdentifier("edit-string-\(notes.count - i)")
                if selectedString == i {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                        ForEach(0..<12) { pc in
                            let target = (notes[i] / 12) * 12 + pc
                            Button { notes[i] = target } label: {
                                Text(PitchMath.names[pc]).font(.system(size: 15)).frame(maxWidth: .infinity, minHeight: 44)
                                    .background(notes[i] % 12 == pc ? style.orange.opacity(0.2) : style.silver.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                            }.disabled(!(21...89).contains(target)).accessibilityIdentifier("pitch-class-\(pc)")
                        }
                    }
                    HStack {
                        Text("Octave").font(.system(size: 13)).foregroundStyle(style.muted)
                        Spacer()
                        Button { notes[i] -= 12 } label: { Image(systemName: "minus").frame(width: 44, height: 44).contentShape(Rectangle()) }
                            .disabled(notes[i] - 12 < 21).accessibilityLabel("Lower octave")
                        Text("\(PitchMath.octave(notes[i]))").monospacedDigit().frame(width: 20)
                        Button { notes[i] += 12 } label: { Image(systemName: "plus").frame(width: 44, height: 44).contentShape(Rectangle()) }
                            .disabled(notes[i] + 12 > 89).accessibilityLabel("Raise octave")
                    }.padding(.horizontal, 12)
                }
            }
            Button { save(editing ? original.id : nil, name, notes); dismiss() } label: {
                Text("Save tuning").font(.system(size: 16, weight: .medium)).frame(maxWidth: .infinity, minHeight: 54)
                    .foregroundStyle(valid ? style.face : style.muted)
                    .background(valid ? style.orange : style.silver, in: RoundedRectangle(cornerRadius: 12))
            }.disabled(!valid).accessibilityIdentifier("saveTuning")
            if editing {
                if confirmDelete {
                    CleanRow(title: "Confirm delete", symbol: "trash") { delete(original.id); dismiss() }.accessibilityIdentifier("confirmDelete")
                } else {
                    CleanRow(title: "Delete tuning", symbol: "trash") { confirmDelete = true }.accessibilityIdentifier("deleteTuning")
                }
            }
            Text("Targets include the octave. Choose pitches suited to your instrument and strings.")
                .font(.system(size: 12)).foregroundStyle(style.muted).padding(.top, 8)
        }.scrollDismissesKeyboard(.interactively)
    }
}
