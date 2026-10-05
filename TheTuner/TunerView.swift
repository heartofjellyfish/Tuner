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
            VStack(spacing: 8) {
                header
                if model.instrument == .chromatic {
                    inputActivity(expanded: true).padding(.top, 12)
                    Spacer(minLength: 16).frame(maxHeight: 64)
                    chromaticMeter
                    Spacer(minLength: 16)
                } else {
                    Spacer(minLength: 0)
                    meter(readoutHeight: min(142, geo.size.height * 0.17), arcHeight: min(132, geo.size.height * 0.17))
                    Group {
                        if model.lockedIndex != nil {
                            Button { model.automatic() } label: {
                                Label("AUTO", systemImage: "lock.open").technical(9)
                                    .frame(minWidth: 100, minHeight: 44).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("autoString")
                                .accessibilityLabel("Unlock string, return to automatic")
                        } else { Color.clear.frame(height: 44).accessibilityHidden(true) }
                    }
                    Headstock(instrument: model.instrument, notes: model.notes, selected: model.selectedIndex, locked: model.lockedIndex, inTune: model.inTune, completed: model.progress.completed,
                              lastCompleted: model.lastCompletedIndex, successCount: model.successCount, select: model.selectString)
                        .aspectRatio(model.notes.count > 6 ? 1.0 : 1.1, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 8).opacity(model.isHeld ? 0.55 : 1)
                }
            }
            .frame(maxWidth: 480)
            .padding(.horizontal, 26).padding(.vertical, 12)
            .frame(width: geo.size.width, height: geo.size.height)
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
    @ViewBuilder private var header: some View {
        if model.instrument == .chromatic {
            ZStack {
                Button { instruments = true } label: {
                    HStack(spacing: 10) {
                        Text("Chromatic").font(.system(size: 23))
                        Image(systemName: "chevron.down").font(.system(size: 12, weight: .medium))
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("instrumentMenu")
                    .accessibilityLabel("Instrument, Chromatic")
                HStack {
                    Spacer()
                    Button { settings = true } label: {
                        Image(systemName: "gearshape").font(.system(size: 23)).frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel("Settings").accessibilityIdentifier("settings")
                }
            }
        } else {
            HStack(alignment: .top) {
                selectors
                Spacer()
                inputActivity().padding(.top, 10)
                Button { settings = true } label: {
                    Image(systemName: "gearshape").font(.system(size: 23, weight: .regular)).frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Settings").accessibilityIdentifier("settings")
            }.padding(.horizontal, 5)
        }
    }
    private func inputActivity(expanded: Bool = false) -> some View {
        InputActivity(level: model.level, enabled: (model.listening || model.demo) && !model.permissionDenied && !model.tone,
                      status: model.inputStatus, envelope: model.inputEnvelope, expanded: expanded)
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
            ForEach(Instrument.allCases.filter { $0 != .chromatic } + [.chromatic]) { value in
                InstrumentPickerRow(instrument: value, selected: model.instrument == value) {
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
    private func meter(readoutHeight: CGFloat, arcHeight: CGFloat) -> some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                Group {
                    if let note = model.displayNote {
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text(PitchMath.name(note)).font(.system(size: 94, weight: .medium)).tracking(-3)
                            Text("\(PitchMath.octave(note))").font(.system(size: 34, weight: .medium))
                        }.lineLimit(1).minimumScaleFactor(0.6)
                            .foregroundStyle(model.inTune ? style.tunedInk : style.ink)
                    } else {
                        Text(idlePrompt).font(.system(size: 18)).foregroundStyle(style.muted)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                Group {
                    if model.isHeld { Text("Last reading") }
                    else if model.allStringsTuned { Text("All tuned").foregroundStyle(style.tuned) }
                    else if showCents, model.frequency != nil {
                        Text(abs(model.visualCents) < 0.5 ? "0 ct" : String(format: "%+.0f ct", model.visualCents))
                    }
                }.font(.system(size: 11, design: .monospaced)).monospacedDigit()
                    .foregroundStyle(style.muted).accessibilityIdentifier("centsDetail")
            }.frame(height: readoutHeight)
            PitchArc(note: model.displayNote, cents: model.visualCents, active: model.frequency != nil, inTune: model.inTune)
                .frame(height: arcHeight)
        }
        .opacity(model.isHeld ? 0.5 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: model.isHeld)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("pitchDisplay")
        .accessibilityLabel(model.displayNote.map(PitchMath.label) ?? "\(model.instrument.rawValue) tuner")
        .accessibilityValue((model.frequency == nil ? idlePrompt : "\(String(format: "%.1f", model.cents)) cents, \(model.status)") + (model.allStringsTuned ? ", ALL STRINGS TUNED" : ""))
    }
    private var chromaticMeter: some View {
        ZStack {
            ChromaticRing(note: model.displayNote, cents: model.visualCents,
                          active: model.frequency != nil, inTune: model.inTune && !model.isHeld)
            VStack(spacing: 10) {
                if let note = model.displayNote {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(PitchMath.name(note)).font(.system(size: 72, weight: .medium)).tracking(-2)
                        Text("\(PitchMath.octave(note))").font(.system(size: 28, weight: .medium))
                    }.lineLimit(1).minimumScaleFactor(0.6)
                        .scaleEffect(!reduceMotion && model.inTune && !model.isHeld ? 1.18 : 1)
                        .animation(reduceMotion ? nil : .easeOut(duration: model.inTune && !model.isHeld ? 1.2 : 0.2),
                                   value: model.inTune && !model.isHeld)
                        .foregroundStyle(model.inTune && !model.isHeld ? style.tunedInk : style.ink)
                    if model.inTune && !model.isHeld {
                        Circle().fill(style.tuned).frame(width: 9, height: 9)
                            .shadow(color: style.tuned.opacity(0.3), radius: 6)
                    }
                    if model.isHeld {
                        Text("Last reading").font(.system(size: 11)).foregroundStyle(style.muted)
                    } else if showCents, model.frequency != nil {
                        Text(String(format: "%+.0f ct", model.visualCents))
                            .font(.system(size: 11, design: .monospaced)).monospacedDigit()
                            .foregroundStyle(style.muted).accessibilityIdentifier("centsDetail")
                    }
                    if model.lockedPitch != nil {
                        Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(style.muted)
                    }
                } else {
                    Text("Play a note").font(.system(size: 18)).foregroundStyle(style.muted)
                }
            }.frame(maxWidth: 170)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .opacity(model.isHeld ? 0.5 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: model.isHeld)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("pitchDisplay")
        .accessibilityLabel(model.displayNote.map(PitchMath.label) ?? "Chromatic tuner")
        .accessibilityValue(model.frequency == nil ? "Play a note" : "\(String(format: "%.1f", model.cents)) cents, \(model.status)")
    }
    private var holdPitchControl: some View {
        CleanRow(title: model.lockedPitch == nil ? "Hold note" : "Release note", symbol: model.lockedPitch == nil ? "lock.open" : "lock.fill") {
            model.holdPitch()
        }.disabled(model.displayNote == nil)
            .accessibilityIdentifier("holdPitch")
            .accessibilityLabel(model.lockedPitch == nil ? "Hold current pitch" : "Release held pitch")
    }
    private var settingsSheet: some View {
        CleanPanel(title: "Settings") {
            if let error = model.error {
                Text(error).font(.system(size: 13)).foregroundStyle(style.muted).frame(maxWidth: .infinity, alignment: .leading)
                if model.permissionDenied {
                    CleanRow(title: "Open Settings", symbol: "mic") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                }
            }
            if model.instrument == .chromatic { holdPitchControl }
            if model.instrument == .chromatic {
                CleanRow(title: "Pitch response", detail: model.chromaticResponse == .voice ? "Voice · ±8 ct" : "Fine · ±3 ct", symbol: "waveform") {
                    model.chromaticResponse = model.chromaticResponse == .voice ? .fine : .voice
                }.accessibilityIdentifier("pitchResponse")
                    .accessibilityValue(model.chromaticResponse == .voice ? "Voice, ±8 cents" : "Fine, ±3 cents")
            }
            CleanRow(title: model.listening ? "Pause microphone" : "Resume microphone", detail: model.inputStatus.capitalized, symbol: "mic") {
                if model.listening { model.stop() } else { model.start() }
            }.accessibilityIdentifier("microphoneToggle")
            CleanRow(title: model.tone ? "Stop reference tone" : "Play A4 reference tone", symbol: model.tone ? "stop" : "speaker.wave.2") { model.toggleTone() }
                .accessibilityIdentifier("referenceTone")
            CleanRow(title: "Concert A", detail: "A4 · \(Int(model.reference)) Hz", symbol: "tuningfork") { calibration = true }
                .accessibilityIdentifier("reference").accessibilityLabel("Concert A, \(Int(model.reference)) hertz")
            if model.instrument != .chromatic {
                CleanRow(title: "Tuning sounds", detail: model.successSoundEnabled ? "On" : "Off", selected: model.successSoundEnabled, symbol: "speaker.wave.2") {
                    model.successSoundEnabled.toggle()
                }.accessibilityIdentifier("successSound")
                CleanRow(title: "Reset tuning progress", symbol: "arrow.counterclockwise") { model.resetProgress() }
                    .accessibilityIdentifier("resetProgress")
            }
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
            Text(model.instrument == .chromatic && model.chromaticResponse == .voice
                 ? "Voice: green when the short-term average settles within ±8 cents."
                 : "Settles green within ±3 cents")
                .font(.system(size: 12)).foregroundStyle(style.muted).padding(.top, 16)
            Text("Tap a string to lock it. Tap AUTO to release. In Chromatic, use Hold note to keep a target.")
                .font(.system(size: 13)).foregroundStyle(style.muted).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            Text("Audio stays on your device.").font(.system(size: 12)).foregroundStyle(style.muted)
        }.transaction { $0.animation = nil; $0.disablesAnimations = true }.presentationDetents([.large])
            .sheet(isPresented: $calibration) { calibrationSheet }
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
