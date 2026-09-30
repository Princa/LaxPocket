import SwiftUI
import LaxPocketCore

/// Logs a height and weight check, or edits one.
struct LogMeasurementView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// The entry being edited; nil for a new one.
    let measurement: BodyMeasurement?
    @State private var date: Date
    @State private var input: BodyInput
    @State private var note: String
    @State private var confirmDelete = false

    init(measurement: BodyMeasurement? = nil, units: BodyUnits) {
        self.measurement = measurement
        _date = State(initialValue: measurement?.date ?? Date())
        _input = State(initialValue: BodyInput(units: units, heightCm: measurement?.heightCm, weightKg: measurement?.weightKg))
        _note = State(initialValue: measurement?.note ?? "")
    }

    private var isNew: Bool { measurement == nil }
    private var canSave: Bool { !input.isBlank && !input.hasError }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                }
                BodyInputFields(input: $input, footer: footer)
                Section("Note") {
                    TextField("Optional, e.g. check-up at the doctor’s", text: $note)
                }
                if !isNew {
                    Section {
                        Button("Delete this entry", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "Log height & weight" : "Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.bold).disabled(!canSave)
                }
            }
            .confirmationDialog("Delete this entry?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let measurement { store.deleteBodyMeasurements([measurement.id]) }
                    dismiss()
                }
            }
        }
    }

    private var footer: String {
        guard isNew, let last = BodyTrends.summary(store.data.bodyMeasurements, units: input.units) else {
            return "Leave one blank if you only measured the other."
        }
        return "Last logged: \(last). Leave one blank if you only measured the other."
    }

    private func save() {
        var entry = input.applied(to: measurement ?? BodyMeasurement(date: date))
        entry.date = date
        entry.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        store.saveBodyMeasurement(entry)
        dismiss()
    }
}

/// Height and weight fields for a form, with a units switch. Switching units converts what's typed.
struct BodyInputFields: View {
    @Binding var input: BodyInput
    var footer: String = ""

    var body: some View {
        Section {
            Picker("Units", selection: unitsBinding) {
                ForEach(BodyUnits.allCases) { Text($0.shortTitle).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Height")
                Spacer()
                if input.units == .imperial {
                    numberField("5", text: $input.feet, label: "Height, feet")
                    Text("ft").foregroundStyle(AppTheme.caption)
                    numberField("4", text: $input.height, label: "Height, inches")
                    Text("in").foregroundStyle(AppTheme.caption)
                } else {
                    numberField("163", text: $input.height, label: "Height in centimetres", width: 72)
                    Text("cm").foregroundStyle(AppTheme.caption)
                }
            }

            HStack {
                Text("Weight")
                Spacer()
                numberField(input.units == .imperial ? "112" : "51", text: $input.weight,
                            label: input.units == .imperial ? "Weight in pounds" : "Weight in kilograms", width: 72)
                Text(input.units.weightUnit).foregroundStyle(AppTheme.caption)
            }
        } header: {
            Text("Height & weight")
        } footer: {
            Text(problem ?? footer)
        }
    }

    private var unitsBinding: Binding<BodyUnits> {
        Binding(get: { input.units }, set: { input = input.converted(to: $0) })
    }

    /// Why a typed value can't be saved, if it can't.
    private var problem: String? {
        let imperial = input.units == .imperial
        if input.heightCm == .invalid {
            return "That height doesn’t look right. Check it’s in \(imperial ? "feet and inches" : "centimetres")."
        }
        if input.weightKg == .invalid {
            return "That weight doesn’t look right. Check it’s in \(imperial ? "pounds" : "kilograms")."
        }
        return nil
    }

    private func numberField(_ prompt: String, text: Binding<String>, label: String, width: CGFloat = 48) -> some View {
        TextField(prompt, text: text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: width)
            .accessibilityLabel(label)
    }
}
