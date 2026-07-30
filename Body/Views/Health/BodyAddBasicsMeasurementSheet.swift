//
//  BodyAddBasicsMeasurementSheet.swift
//  Body
//

import SwiftUI

/// Manual entry for body measurements, presented from the Basics detail screen's
/// "+" button. Weight and body fat are both chosen on one page with wheel
/// pickers (the same selection style as the date/time), then saved to Apple
/// Health via `HealthKitWorkoutStore.saveBodyComposition`. The wheels seed from
/// the user's latest known values so they start somewhere meaningful. Each
/// measurement has an include switch, so the user can log just weight, just body
/// fat, or both — only the enabled values are written.
struct BodyAddBasicsMeasurementSheet: View {
    let accentColor: Color
    /// Latest known weight in kilograms, used to seed the weight wheel.
    let initialWeightKilograms: Double?
    /// Latest known body-fat percentage (0–100), used to seed the body-fat wheel.
    let initialBodyFatPercent: Double?

    @EnvironmentObject private var workoutStore: HealthKitWorkoutStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage(BodyAppearancePreference.followsSystemUnitsKey) private var followsSystemUnits = true
    @AppStorage(BodyAppearancePreference.selectedWeightUnitKey) private var selectedWeightUnitRawValue = BodyValueFormat.WeightUnitPreference.defaultValue.rawValue

    // Wheel selections are kept as integer tenths of the displayed unit so the
    // `Picker` tags match exactly — binding a `Double` produced by a 0.1 stride
    // would hit floating-point mismatches and lose the selection.
    @State private var weightTenths = 700
    @State private var bodyFatTenths = 200
    @State private var includeWeight = true
    @State private var includeBodyFat = true
    @State private var date = Date()
    @State private var didSeed = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private static let wheelHeight: CGFloat = 130

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    measurementCard(title: "Weight", isOn: $includeWeight) {
                        Picker("Weight", selection: $weightTenths) {
                            ForEach(weightRange, id: \.self) { tenths in
                                Text(label(forTenths: tenths, unit: weightUnit.unitLabel)).tag(tenths)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: Self.wheelHeight)
                        .clipped()
                    }

                    measurementCard(title: "Body Fat", isOn: $includeBodyFat) {
                        Picker("Body Fat", selection: $bodyFatTenths) {
                            ForEach(bodyFatRange, id: \.self) { tenths in
                                Text(label(forTenths: tenths, unit: "%")).tag(tenths)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: Self.wheelHeight)
                        .clipped()
                    }
                }

                dateCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .bodySheetBackground()
            .navigationTitle("Add Measurement")
            .navigationBarTitleDisplayMode(.inline)
            .tint(accentColor)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save", action: save)
                            .fontWeight(.semibold)
                            .disabled(!includeWeight && !includeBodyFat)
                    }
                }
            }
            .alert("Couldn't Save", isPresented: errorAlertBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.height(370)])
        .presentationDragIndicator(.visible)
        .onAppear(perform: seedIfNeeded)
    }

    private func measurementCard<Content: View>(
        title: LocalizedStringKey,
        isOn: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 8) {
            Button {
                isOn.wrappedValue.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isOn.wrappedValue ? accentColor : Color.secondary.opacity(0.5))

                    Text(title)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(isOn.wrappedValue ? .primary : Color.secondary.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            content()
                .disabled(!isOn.wrappedValue)
                .opacity(isOn.wrappedValue ? 1 : 0.35)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .bodyCardBackground(translucent: true)
    }

    private var dateCard: some View {
        DatePicker(
            "Date & Time",
            selection: $date,
            in: ...Date(),
            displayedComponents: [.date, .hourAndMinute]
        )
        .datePickerStyle(.compact)
        .font(.system(.headline, design: .rounded))
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground(translucent: true)
    }

    private var weightUnit: BodyValueFormat.WeightUnitPreference {
        followsSystemUnits
            ? BodyValueFormat.WeightUnitPreference.systemValue(locale: .current)
            : BodyValueFormat.WeightUnitPreference.storedValue(from: selectedWeightUnitRawValue)
    }

    // Sensible bounds (in tenths of the displayed unit) for the wheels.
    private var weightRange: [Int] {
        switch weightUnit {
        case .kilograms:
            return Array(300...2500)   // 30.0–250.0 kg
        case .pounds:
            return Array(660...5500)   // 66.0–550.0 lb
        }
    }

    private let bodyFatRange = Array(10...700)   // 1.0–70.0 %

    private func label(forTenths tenths: Int, unit: String) -> String {
        let value = (Double(tenths) / 10).formatted(.number.precision(.fractionLength(1)))
        return "\(value) \(unit)"
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func seedIfNeeded() {
        guard !didSeed else {
            return
        }
        didSeed = true

        if let kilograms = initialWeightKilograms, kilograms > 0 {
            let displayValue: Double
            switch weightUnit {
            case .kilograms:
                displayValue = kilograms
            case .pounds:
                displayValue = Measurement(value: kilograms, unit: UnitMass.kilograms)
                    .converted(to: .pounds)
                    .value
            }
            weightTenths = clamp(Int((displayValue * 10).rounded()), to: weightRange)
        }

        if let percent = initialBodyFatPercent, percent > 0 {
            bodyFatTenths = clamp(Int((percent * 10).rounded()), to: bodyFatRange)
        }
    }

    private func clamp(_ value: Int, to range: [Int]) -> Int {
        guard let first = range.first, let last = range.last else {
            return value
        }
        return min(max(value, first), last)
    }

    private func save() {
        isSaving = true

        let weightKilograms: Double? = includeWeight ? weightKilogramsValue() : nil
        let bodyFatPercent: Double? = includeBodyFat ? Double(bodyFatTenths) / 10 : nil
        let savedDate = date

        Task {
            do {
                try await workoutStore.saveBodyComposition(
                    weightKilograms: weightKilograms,
                    bodyFatPercent: bodyFatPercent,
                    date: savedDate
                )
                dismiss()
            } catch {
                isSaving = false
                errorMessage = String(localized: "Body couldn't save to Apple Health. Make sure Body is allowed to update Weight and Body Fat in Settings › Health › Data Access & Devices.")
            }
        }
    }

    private func weightKilogramsValue() -> Double {
        let weightDisplay = Double(weightTenths) / 10
        switch weightUnit {
        case .kilograms:
            return weightDisplay
        case .pounds:
            return Measurement(value: weightDisplay, unit: UnitMass.pounds)
                .converted(to: .kilograms)
                .value
        }
    }
}
