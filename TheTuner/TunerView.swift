import SwiftUI

struct TunerView: View {
    @AppStorage("color-theme") private var themeName = TunerTheme.blue.rawValue
    private var theme: TunerTheme { TunerTheme(rawValue: themeName) ?? .blue }
    private var style: CleanStyle { theme.style }
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
                VStack(spacing: 10) {
                    header
                    VStack(spacing: 0) {
                        selectors.padding(.bottom, 8)
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
                                .frame(height: max(model.notes.count > 6 ? 260 : 170, min(340, geo.size.height - 518)))
                                .padding(.horizontal, 8).opacity(model.isHeld ? 0.55 : 1)
                        }
                    }
                    footer
                }
                .frame(maxWidth: 480)
                .padding(.horizontal, 26).padding(.top, 8).padding(.bottom, 8)
                .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .top)
            }.scrollIndicators(.hidden)
                .background(style.shell.ignoresSafeArea())
        }
        .foregroundStyle(style.ink).tint(style.orange)
        .preferredColorScheme(theme == .chalk ? .light : .dark)
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
                Text(model.error ?? "").font(.system(size: 15)).foregroundStyle(style.muted)
                if model.permissionDenied {
                    CleanRow(title: "Open Settings", symbol: "mic") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                } else { CleanRow(title: "Retry", symbol: "arrow.clockwise") { model.error = nil; model.start() } }
                CleanRow(title: "Dismiss") { model.error = nil }
            }.presentationDetents([.medium])
        }
        .environment(\.tunerTheme, theme)
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
        VStack(alignment: .leading, spacing: 0) {
            Button { instruments = true } label: { selectorLabel(model.instrument.rawValue, size: 23) }
                .accessibilityIdentifier("instrumentMenu").accessibilityLabel("Instrument, \(model.instrument.rawValue)")
            if let tuning = model.tuning {
                Button { tunings = true } label: { selectorLabel(tuning.name, size: 17) }
                    .accessibilityIdentifier("tuningMenu").accessibilityLabel("Tuning, \(tuning.name)")
            }
        }.buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func selectorLabel(_ value: String, size: CGFloat) -> some View {
        HStack(spacing: 12) {
            Text(value).font(.system(size: size)).lineLimit(1).minimumScaleFactor(0.65)
            Image(systemName: "chevron.down").font(.system(size: 12, weight: .medium))
        }.frame(minHeight: 44).contentShape(Rectangle())
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
    private var idlePrompt: String {
        model.instrument == .chromatic || model.instrument.bowed ? "Play a note" : "Pluck a string"
    }
    private var meter: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                Group {
                    if let note = model.displayNote {
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text(PitchMath.name(note)).font(.system(size: 160, weight: .bold)).tracking(-7)
                            Text("\(PitchMath.octave(note))").font(.system(size: 43, weight: .semibold))
                        }.lineLimit(1).minimumScaleFactor(0.5)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(model.instrument.rawValue)
                            Text("Tuner")
                        }.font(.system(size: 46, weight: .semibold)).tracking(-1.5)
                            .lineLimit(1).minimumScaleFactor(0.45)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(style.silver).frame(width: 1, height: 80)
                VStack(alignment: .leading, spacing: 10) {
                    if model.frequency != nil {
                        Image(systemName: model.inTune ? "checkmark.circle" : abs(model.cents) <= 3 ? "circle.dotted" : model.cents < 0 ? "arrow.up" : "arrow.down")
                            .font(.system(size: 26, weight: .light))
                            .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? 0 : model.successCount)
                    }
                    if model.frequency == nil {
                        Image(systemName: "waveform").font(.system(size: 25, weight: .light))
                    }
                    Text(model.frequency == nil ? idlePrompt : model.inTune ? "In tune" : abs(model.cents) <= 3 ? "Settling" : model.cents < 0 ? "Tune up" : "Tune down")
                        .font(.system(size: 18, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                    Group {
                        if model.isHeld { Text("Last reading") }
                        else if showCents, model.frequency != nil {
                            Text(abs(model.visualCents) < 0.5 ? "0 ct" : String(format: "%+.0f ct", model.visualCents))
                        }
                    }.font(.system(size: 11, design: .monospaced)).monospacedDigit()
                        .foregroundStyle(style.muted).accessibilityIdentifier("centsDetail")
                }.foregroundStyle(model.inTune ? style.tunedInk : style.orange).frame(width: 102, alignment: .leading)
            }.frame(height: 166)
            PitchRuler(note: model.displayNote, cents: model.visualCents, active: model.frequency != nil, inTune: model.inTune)
        }
        .padding(.bottom, 0)
        .opacity(model.isHeld ? 0.5 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: model.isHeld)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("pitchDisplay")
        .accessibilityLabel(model.displayNote.map(PitchMath.label) ?? "\(model.instrument.rawValue) tuner")
        .accessibilityValue(model.frequency == nil ? idlePrompt : "\(String(format: "%.1f", model.cents)) cents, \(model.status)")
    }
    private var chromaticDetails: some View {
        VStack(spacing: 24) {
            Button { model.holdPitch() } label: {
                Label(model.lockedPitch == nil ? "Hold note" : "Release note", systemImage: model.lockedPitch == nil ? "lock.open" : "lock.fill")
                    .font(.system(size: 13)).frame(minHeight: 44)
            }.buttonStyle(.plain).disabled(model.displayNote == nil)
                .accessibilityIdentifier("holdPitch")
                .accessibilityLabel(model.lockedPitch == nil ? "Hold current pitch" : "Release held pitch")
        }.frame(maxWidth: .infinity, minHeight: 220)
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
        }.padding(.top, 8).overlay(alignment: .top) { Rectangle().fill(style.silver).frame(height: 0.5) }
    }
    private var settingsSheet: some View {
        CleanPanel(title: "Settings") {
            if let error = model.error {
                Text(error).font(.system(size: 13)).foregroundStyle(style.muted).frame(maxWidth: .infinity, alignment: .leading)
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
            Text("COLOR").technical(10).foregroundStyle(style.muted).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
            HStack(spacing: 10) {
                ForEach(TunerTheme.allCases) { color in
                    Button { themeName = color.rawValue } label: {
                        VStack(spacing: 9) {
                            Circle().fill(color.style.shell).frame(width: 28, height: 28)
                                .overlay(Circle().stroke(color.style.ink.opacity(0.6), lineWidth: 1))
                                .overlay { if theme == color { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(color.style.ink) } }
                            Text(color.title).font(.system(size: 11))
                        }.frame(maxWidth: .infinity, minHeight: 74).contentShape(Rectangle())
                            .background(style.ink.opacity(theme == color ? 0.09 : 0.025), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).accessibilityIdentifier("theme-\(color.rawValue)")
                        .accessibilityValue(theme == color ? "Selected" : "")
                }
            }
            Text("Settles green within ±3 cents").font(.system(size: 12)).foregroundStyle(style.muted).padding(.top, 16)
            Text("Tap a string to lock it. Tap AUTO to release. In Chromatic, use Hold note to keep a target.")
                .font(.system(size: 13)).foregroundStyle(style.muted).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            Text("Audio stays on your device.").font(.system(size: 12)).foregroundStyle(style.muted)
        }.transaction { $0.animation = nil; $0.disablesAnimations = true }.presentationDetents([.large])
    }
    private var calibrationSheet: some View {
        CleanPanel(title: "Concert A") {
            Text("\(Int(model.reference))").font(.system(size: 64, weight: .light)).monospacedDigit().padding(.top, 12)
            Text("Hz").technical(12).foregroundStyle(style.muted)
            HStack(spacing: 16) {
                Button { model.calibrate(-1) } label: { Image(systemName: "minus").frame(width: 44, height: 44).contentShape(Rectangle()) }.disabled(model.reference <= 420).accessibilityLabel("Lower reference")
                Slider(value: $model.reference, in: 420...460, step: 1).tint(style.orange).accessibilityLabel("Concert A frequency")
                Button { model.calibrate(1) } label: { Image(systemName: "plus").frame(width: 44, height: 44).contentShape(Rectangle()) }.disabled(model.reference >= 460).accessibilityLabel("Raise reference")
            }
            HStack(spacing: 10) {
                ForEach([432,440,442], id: \.self) { hz in
                    Button { model.reference = Double(hz) } label: {
                        Text("\(hz)").font(.system(size: 15, design: .monospaced)).frame(maxWidth: .infinity, minHeight: 48)
                            .background(model.reference == Double(hz) ? style.orange.opacity(0.16) : style.silver.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                    }.accessibilityIdentifier("reference-\(hz)")
                }
            }
        }.presentationDetents([.medium, .large])
    }
}
