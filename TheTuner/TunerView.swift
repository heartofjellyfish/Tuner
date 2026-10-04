import SwiftUI

struct TunerView: View {
    @StateObject private var model = TunerModel()
    @AppStorage("show-cents") private var showCents = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @State private var settings = false
    @State private var instruments = false
    @State private var tunings = false
    @State private var calibration = false
    @State private var editingTuning: Tuning?
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
                                    Text(model.lockedIndex == nil ? "AUTO" : "\(model.notes.count - model.lockedIndex!)").technical(9)
                                }.frame(minWidth: 100, minHeight: 44).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("autoString")
                                .accessibilityLabel(model.lockedIndex == nil ? "Automatic string detection" : "Unlock string, return to automatic")
                            Headstock(instrument: model.instrument, notes: model.notes, selected: model.selectedIndex, locked: model.lockedIndex, inTune: model.inTune, select: model.selectString)
                                .frame(height: max(model.notes.count > 6 ? 270 : 190, min(310, geo.size.height - 480)))
                                .padding(.horizontal, 8).opacity(model.isHeld ? 0.55 : 1)
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
        .sensoryFeedback(.success, trigger: model.successCount)
        .onChange(of: phase) { _, new in
            if new == .background { model.background() }
            else if new == .active { model.foreground() }
        }
        .sheet(isPresented: $settings) { settingsSheet }
        .sheet(isPresented: $calibration) { calibrationSheet }
        .sheet(isPresented: $instruments) { instrumentPanel }
        .sheet(isPresented: $tunings) { tuningPanel }
        .sheet(isPresented: Binding(get: { model.error != nil && !settings && !calibration && !instruments && !tunings }, set: { if !$0 { model.error = nil } })) {
            CleanPanel(title: "Microphone") {
                Text(model.error ?? "").font(.system(size: 15)).foregroundStyle(CleanStyle.muted)
                if model.permissionDenied {
                    CleanRow(title: "Open Settings", symbol: "mic") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                } else { CleanRow(title: "Retry", symbol: "arrow.clockwise") { model.error = nil; model.start() } }
                CleanRow(title: "Dismiss") { model.error = nil }
            }.presentationDetents([.medium])
        }
    }
    private var header: some View {
        HStack {
            Text("CLEAN TUNER").technical(14, spacing: 3.2)
            Spacer()
            Button { settings = true } label: {
                Image(systemName: "gearshape").font(.system(size: 23, weight: .regular)).frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Settings").accessibilityIdentifier("settings")
        }.padding(.horizontal, 5)
    }
    private var selectors: some View {
        HStack(spacing: 0) {
            Button { instruments = true } label: { selectorLabel(model.instrument.rawValue) }
                .accessibilityIdentifier("instrumentMenu").accessibilityLabel("Instrument, \(model.instrument.rawValue)")
            if let tuning = model.tuning {
                Rectangle().fill(CleanStyle.silver).frame(width: 1, height: 18)
                Button { tunings = true } label: { selectorLabel(tuning.name) }
                    .accessibilityIdentifier("tuningMenu").accessibilityLabel("Tuning, \(tuning.name)")
            }
        }.buttonStyle(.plain).frame(height: 56)
    }
    private func selectorLabel(_ value: String) -> some View {
        HStack(spacing: 8) {
            Text(value).font(.system(size: 14, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .medium)).foregroundStyle(CleanStyle.muted)
        }.padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 52).contentShape(Rectangle())
    }
    private var instrumentPanel: some View {
        CleanPanel(title: "Instrument") {
            ForEach(Instrument.allCases) { value in
                CleanRow(title: value.rawValue, selected: model.instrument == value) {
                    model.selectInstrument(value); instruments = false
                }.accessibilityIdentifier("instrument-\(value.rawValue)")
            }
        }
    }
    private var tuningPanel: some View {
        CleanPanel(title: "Tuning", subtitle: model.instrument.rawValue.uppercased()) {
            if let current = model.tuning {
                CleanRow(title: "Custom tuning", symbol: "plus") { editingTuning = Tuning(id: "draft-" + UUID().uuidString, name: "", notes: current.notes) }
                    .accessibilityIdentifier("newCustom")
                if current.isCustom {
                    CleanRow(title: "Edit tuning", symbol: "slider.horizontal.3") { editingTuning = current }
                        .accessibilityIdentifier("editCustom")
                }
            }
            ForEach(model.availableTunings) { value in
                CleanRow(title: value.name, detail: value.notes.map(PitchMath.label).joined(separator: "  "), selected: model.tuning?.id == value.id) {
                    model.selectTuning(value); tunings = false
                }.accessibilityIdentifier("tuning-\(value.id)")
            }
        }
        .sheet(item: $editingTuning) { value in
            TuningEditor(instrument: model.instrument, original: value, editing: value.isCustom,
                         save: model.saveCustom, delete: model.deleteCustom)
        }
    }
    private var meter: some View {
        VStack(spacing: 0) {
            PitchArc(note: model.displayNote, cents: model.visualCents, active: model.frequency != nil, inTune: model.inTune)
                .frame(height: 156).padding(.horizontal, 24).padding(.top, 26)
            HStack {
                Text("−").technical(17, spacing: 0).foregroundStyle(CleanStyle.muted)
                Spacer()
                HStack(spacing: 9) {
                    if model.frequency != nil {
                        Image(systemName: model.inTune ? "checkmark.circle.fill" : abs(model.cents) <= 3 ? "circle.dotted" : model.cents < 0 ? "arrow.up.right" : "arrow.down.left")
                            .font(.system(size: model.inTune ? 26 : 18, weight: .medium))
                            .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? 0 : model.successCount)
                    }
                    Text(model.frequency == nil ? "Play a note" : model.inTune ? "In tune" : abs(model.cents) <= 3 ? "Settling" : model.cents < 0 ? "Tune up" : "Tune down")
                        .font(.system(size: 20, weight: .medium))
                }.foregroundStyle(model.inTune ? CleanStyle.tunedInk : CleanStyle.ink)
                Spacer()
                Text("+").technical(17, spacing: 0).foregroundStyle(CleanStyle.muted)
            }.frame(height: 52).padding(.horizontal, 18)
            Group {
                if model.isHeld { Text("Last reading") }
                else if showCents, model.frequency != nil {
                    Text(abs(model.visualCents) < 0.5 ? "0 ct" : String(format: "%+.0f ct", model.visualCents))
                } else { Text(" ") }
            }.font(.system(size: 12, design: .monospaced)).monospacedDigit()
                .foregroundStyle(CleanStyle.muted).padding(.top, 4).padding(.bottom, 6)
                .accessibilityIdentifier("centsDetail")
        }
        .opacity(model.isHeld ? 0.5 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: model.isHeld)
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
            Image(systemName: model.lockedPitch == nil ? "lock.open" : "lock.fill")
                .font(.system(size: 12)).foregroundStyle(CleanStyle.muted).accessibilityHidden(true)

        }.frame(maxWidth: .infinity).padding(.vertical, 32)
    }
    private var footer: some View {
        HStack(spacing: 10) {
            StatusLight(on: model.listening || model.tone || model.demo)
                .accessibilityHidden(false).accessibilityLabel(model.inputStatus).accessibilityIdentifier("inputStatus")
            if model.demo || model.permissionDenied || (!model.listening && !model.tone) {
                Text(model.inputStatus).technical(9, spacing: 1).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 4)
            Button { calibration = true } label: {
                Text("A4  \(Int(model.reference)) Hz").technical(10, spacing: 1.5).frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("reference")
                .accessibilityLabel("Concert A, \(Int(model.reference)) hertz")
        }.padding(.horizontal, 4)
    }
    private var settingsSheet: some View {
        CleanPanel(title: "Settings") {
            if let error = model.error {
                Text(error).font(.system(size: 13)).foregroundStyle(CleanStyle.muted).frame(maxWidth: .infinity, alignment: .leading)
                if model.permissionDenied {
                    CleanRow(title: "Open Settings", symbol: "mic") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                }
            }
            CleanRow(title: model.listening ? "Pause microphone" : "Resume microphone", detail: model.inputStatus.capitalized, symbol: "mic") {
                if model.listening { model.stop() } else { model.start() }
            }.accessibilityIdentifier("microphoneToggle")
            CleanRow(title: model.tone ? "Stop reference tone" : "Play A4 reference tone", symbol: model.tone ? "stop" : "speaker.wave.2") { model.toggleTone() }
                .accessibilityIdentifier("referenceTone")
            CleanRow(title: "Show cents", detail: showCents ? "On" : "Off", selected: showCents, symbol: "number") { showCents.toggle() }
                .accessibilityIdentifier("showCents")
            Text("Settles green within ±3 cents").font(.system(size: 12)).foregroundStyle(CleanStyle.muted).padding(.top, 16)
            Text("Tap a string to lock it. Tap AUTO to release. In Chromatic, tap the note to hold it.")
                .font(.system(size: 13)).foregroundStyle(CleanStyle.muted).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            Text("Audio stays on your device.").font(.system(size: 12)).foregroundStyle(CleanStyle.muted)
        }.transaction { $0.animation = nil; $0.disablesAnimations = true }.presentationDetents([.medium, .large])
    }
    private var calibrationSheet: some View {
        CleanPanel(title: "Concert A") {
            Text("\(Int(model.reference))").font(.system(size: 64, weight: .light)).monospacedDigit().padding(.top, 12)
            Text("Hz").technical(12).foregroundStyle(CleanStyle.muted)
            HStack(spacing: 16) {
                Button { model.calibrate(-1) } label: { Image(systemName: "minus").frame(width: 44, height: 44).contentShape(Rectangle()) }.disabled(model.reference <= 420).accessibilityLabel("Lower reference")
                Slider(value: $model.reference, in: 420...460, step: 1).tint(CleanStyle.orange).accessibilityLabel("Concert A frequency")
                Button { model.calibrate(1) } label: { Image(systemName: "plus").frame(width: 44, height: 44).contentShape(Rectangle()) }.disabled(model.reference >= 460).accessibilityLabel("Raise reference")
            }
            HStack(spacing: 10) {
                ForEach([432,440,442], id: \.self) { hz in
                    Button { model.reference = Double(hz) } label: {
                        Text("\(hz)").font(.system(size: 15, design: .monospaced)).frame(maxWidth: .infinity, minHeight: 48)
                            .background(model.reference == Double(hz) ? CleanStyle.orange.opacity(0.16) : CleanStyle.silver.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                    }.accessibilityIdentifier("reference-\(hz)")
                }
            }
        }.presentationDetents([.medium, .large])
    }
}
