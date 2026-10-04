import SwiftUI

struct TunerView: View {
    @StateObject private var model = TunerModel()
    @Environment(\.scenePhase) private var phase
    @State private var settings = false
    @State private var calibration = false
    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 18) {
                    header
                    VStack(spacing: 0) {
                        selectors.padding(.horizontal, 20)
                        Divider().padding(.horizontal, 20)
                        meter
                        if model.instrument == .chromatic { chromaticDetails }
                        else {
                            Button { model.automatic() } label: {
                                HStack(spacing: 7) {
                                    if model.lockedIndex != nil { Image(systemName: "lock.fill").font(.system(size: 9)) }
                                    Text(model.lockedIndex == nil ? "AUTO" : "STRING \(model.notes.count - model.lockedIndex!) · LOCKED").technical(10)
                                }.frame(minWidth: 100, minHeight: 44)
                            }.buttonStyle(.plain).accessibilityIdentifier("autoString")
                                .accessibilityLabel(model.lockedIndex == nil ? "Automatic string detection" : "Unlock string, return to automatic")
                            Headstock(notes: model.notes, selected: model.selectedIndex, locked: model.lockedIndex, select: model.selectString)
                                .frame(height: max(158, min(310, geo.size.height - 510)))
                                .padding(.horizontal, 8)
                        }
                    }.modifier(Surface())
                    footer
                }
                .frame(maxWidth: 480)
                .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 16)
                .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .top)
            }.scrollIndicators(.hidden)
                .background(LinearGradient(colors: [.white, CleanStyle.shell, Color(hex: 0xE3E6E2)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea())
        }
        .foregroundStyle(CleanStyle.ink).tint(CleanStyle.orange)
        .preferredColorScheme(.light)
        .task { model.begin() }
        .onChange(of: phase) { _, new in
            if new == .background { model.background() }
            else if new == .active { model.foreground() }
        }
        .sheet(isPresented: $settings) { settingsSheet }
        .sheet(isPresented: $calibration) { calibrationSheet }
        .alert("Microphone", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            if model.permissionDenied {
                Button("Open Settings") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
            } else {
                Button("Retry") { model.error = nil; model.start() }
            }
            Button("Dismiss", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
    private var header: some View {
        HStack {
            Text("CLEAN TUNER").technical(14, spacing: 3.2)
            Spacer()
            Button { settings = true } label: {
                Image(systemName: "gearshape").font(.system(size: 23, weight: .regular)).frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel("Settings").accessibilityIdentifier("settings")
        }.padding(.horizontal, 5)
    }
    private var selectors: some View {
        HStack {
            Menu {
                ForEach(Instrument.allCases) { item in
                    Button { model.selectInstrument(item) } label: {
                        if item == model.instrument { Label(item.rawValue, systemImage: "checkmark") }
                        else { Text(item.rawValue) }
                    }
                }
            } label: { selectorLabel(model.instrument.rawValue) }
                .accessibilityIdentifier("instrumentMenu").accessibilityLabel("Instrument, \(model.instrument.rawValue)")
            Spacer(minLength: 4)
            if let tuning = model.tuning {
                Rectangle().fill(CleanStyle.silver).frame(width: 1, height: 18)
                Spacer(minLength: 4)
                Menu {
                    ForEach(model.instrument.tunings) { item in
                        Button { model.selectTuning(item) } label: {
                            if tuning == item { Label(item.name, systemImage: "checkmark") }
                            else { Text(item.name) }
                        }
                    }
                } label: { selectorLabel(tuning.name) }
                    .accessibilityIdentifier("tuningMenu").accessibilityLabel("Tuning, \(tuning.name)")
            } else { Text("12 NOTES").technical(9, spacing: 1).foregroundStyle(CleanStyle.muted) }
        }.frame(height: 52)
    }
    private func selectorLabel(_ value: String) -> some View {
        HStack(spacing: 8) { Text(value).font(.system(size: 15, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7); Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)) }
            .frame(minHeight: 44).foregroundStyle(CleanStyle.ink)
    }
    private var meter: some View {
        VStack(spacing: 0) {
            PitchArc(note: model.displayNote, cents: model.cents, active: model.frequency != nil)
                .frame(height: 156).padding(.horizontal, 24).padding(.top, 26)
            HStack(alignment: .firstTextBaseline) {
                Text("LOW").technical(10, spacing: 1.7).foregroundStyle(CleanStyle.muted)
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(model.frequency == nil ? "—" : (abs(model.cents) < 0.5 ? "0" : String(format: "%+.0f", model.cents)))
                        .font(.system(size: 43, weight: .regular, design: .rounded)).monospacedDigit()
                    Text("ct").font(.system(size: 23))
                }.lineLimit(1).minimumScaleFactor(0.65)
                Spacer(minLength: 0)
                Text("HIGH").technical(10, spacing: 1.7).foregroundStyle(CleanStyle.muted)
            }.padding(.horizontal, 18)
            Text(model.status).technical(11, spacing: 2.1).padding(.top, 4).padding(.bottom, 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("pitchDisplay")
        .accessibilityLabel(model.displayNote.map(PitchMath.label) ?? "No pitch")
        .accessibilityValue(model.frequency == nil ? "Play a note" : "\(String(format: "%.1f", model.cents)) cents, \(model.status)")
    }
    private var chromaticDetails: some View {
        VStack(spacing: 24) {
            Button { model.holdPitch() } label: {
                Text(model.displayNote.map(PitchMath.label) ?? "—")
                    .font(.system(size: 72, weight: .ultraLight))
            }.buttonStyle(.plain).disabled(model.displayNote == nil)
                .accessibilityIdentifier("holdPitch")
                .accessibilityLabel(model.lockedPitch == nil ? "Hold current pitch" : "Release held pitch")
            Text(model.lockedPitch == nil ? "AUTO · TAP NOTE TO HOLD" : "HELD · TAP NOTE TO RELEASE")
                .technical(9, spacing: 1).foregroundStyle(CleanStyle.muted)
            Text(model.frequency.map { String(format: "%.2f Hz", $0) } ?? "— Hz")
                .font(.system(size: 17, design: .monospaced)).foregroundStyle(CleanStyle.muted)
            HStack(spacing: 5) {
                ForEach(0..<12) { pc in
                    Capsule().fill(model.note.map { $0 % 12 == pc } == true ? CleanStyle.orange : CleanStyle.silver)
                        .frame(width: 4, height: 12)
                }
            }.accessibilityHidden(true)
            Text("ONE NOTE AT A TIME").technical(9, spacing: 1.6).foregroundStyle(CleanStyle.muted)
        }.frame(maxWidth: .infinity).padding(.vertical, 32)
    }
    private var footer: some View {
        HStack(spacing: 10) {
            StatusLight(on: model.listening || model.tone || model.demo)
            Text(model.inputStatus).technical(9, spacing: 1.5).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            Button { calibration = true } label: {
                Text("A4  \(Int(model.reference)) Hz").technical(10, spacing: 1.5).frame(minHeight: 44)
            }.buttonStyle(.plain).accessibilityIdentifier("reference")
                .accessibilityLabel("Concert A, \(Int(model.reference)) hertz")
        }.padding(.horizontal, 4)
    }
    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("Audio") {
                    HStack { Text("Microphone"); Spacer(); Text(model.inputStatus.capitalized).foregroundStyle(.secondary) }
                    Button(model.listening ? "Pause microphone" : "Resume microphone") {
                        if model.listening { model.stop() } else { model.start() }
                    }.foregroundStyle(CleanStyle.ink)
                    Button(model.tone ? "Stop reference tone" : "Play A4 reference tone") { model.toggleTone() }
                        .foregroundStyle(CleanStyle.ink).accessibilityIdentifier("referenceTone")
                }
                Section("Tuning") {
                    Text("Equal temperament · A4 = \(Int(model.reference)) Hz")
                    Text("The marker moves left when flat and right when sharp. Each note occupies a region; its center is the exact pitch. In tune means within ±3 cents.").font(.subheadline).foregroundStyle(.secondary)
                    Text("Tap a string to lock its target. Tap it again, or tap AUTO, to return to automatic detection. Use a lock when replacing a string or tuning far from its target.").font(.subheadline).foregroundStyle(.secondary)
                }
                Section("Clean / 03") {
                    Text("Play one sustained note in a quiet space. Let the attack settle before adjusting. Working range: 40–1500 Hz.").font(.subheadline).foregroundStyle(.secondary)
                    Text("Audio stays on your device. No recordings, accounts, or analytics.").font(.subheadline).foregroundStyle(.secondary)
                }
            }.navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { settings = false } } }
        }.tint(CleanStyle.ink)
    }
    private var calibrationSheet: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Text("CONCERT A").technical(11).foregroundStyle(CleanStyle.muted)
                Text("\(Int(model.reference)) Hz").font(.system(size: 52, weight: .light)).monospacedDigit()
                HStack(spacing: 20) {
                    Button { model.calibrate(-1) } label: { Image(systemName: "minus").frame(width: 44, height: 44) }.accessibilityLabel("Lower reference")
                    Slider(value: $model.reference, in: 420...460, step: 1).accessibilityLabel("Concert A frequency")
                    Button { model.calibrate(1) } label: { Image(systemName: "plus").frame(width: 44, height: 44) }.accessibilityLabel("Raise reference")
                }
                HStack(spacing: 12) {
                    ForEach([432,440,442], id: \.self) { hz in
                        Button { model.reference = Double(hz) } label: {
                            Text("\(hz)").frame(maxWidth: .infinity).padding(.vertical, 15)
                                .background(model.reference == Double(hz) ? CleanStyle.orange.opacity(0.2) : CleanStyle.silver.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                        }.accessibilityIdentifier("reference-\(hz)")
                    }
                }
                Text("420–460 Hz · Applies to every note").font(.footnote).foregroundStyle(CleanStyle.muted)
                Spacer()
            }.padding(28).background(CleanStyle.face)
                .navigationTitle("Reference").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { calibration = false } } }
        }.presentationDetents([.medium, .large]).tint(CleanStyle.ink)
    }
}
