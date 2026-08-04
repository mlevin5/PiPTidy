import AppKit
import CoreGraphics
import PiPTidyCore
import ServiceManagement
import SwiftUI

struct SystemScreenCaptureAuthorization {
    var isGranted: Bool { CGPreflightScreenCaptureAccess() }
    func request() { CGRequestScreenCaptureAccess() }
}

@MainActor final class WindowStore: ObservableObject {
    @Published var windows: [WindowSnapshot] = []
    @Published var selectedID: String?
    @Published var errors: [String] = []
    @Published var xText = "100"
    @Published var yText = "100"
    @Published var widthText = "480"
    @Published var heightText = "270"
    @Published var heatmap: NSImage?
    @Published var proposedPlacement: CGRect?
    @Published var isAnalyzing = false
    @Published var livePlacementEnabled = false
    @Published var selectionWasAutoDetected = false
    @Published var statusMessage = "Ready"
    @Published var minimumPiPWidth = UserDefaults.standard.object(forKey: "minimumPiPWidth") as? Double ?? 240
    @Published var maximumScreenFraction = UserDefaults.standard.object(forKey: "maximumScreenFraction") as? Double ?? 0.55
    @Published var launchAtLoginEnabled = SMAppService.mainApp.status == .enabled

    private var liveTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var didStartAutomatically = false
    let auth = SystemAuthorization()
    let screenAuth = SystemScreenCaptureAuthorization()
    let ax = SystemAXService()
    let cg = SystemCGInventory()
    let scorer = DefaultCandidateScorer()

    init() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            self?.startAutomatically()
        }
    }

    var selected: WindowSnapshot? { windows.first { $0.id == selectedID } }

    func refresh() {
        do {
            let cgWindows = cg.enumerate()
            windows = try ax.enumerate().map { axWindow in
                let match = WindowCorrelator.match(axWindow, cg: cgWindows)
                return WindowSnapshot(ax: axWindow, cg: match, score: scorer.score(axWindow, cg: match))
            }.sorted { $0.score.total == $1.score.total ? $0.id < $1.id : $0.score.total > $1.score.total }
            if let detected = PiPDetector.detect(in: windows) {
                if selectedID != detected.id { selectedID = detected.id; syncGeometryFields() }
                selectionWasAutoDetected = true
                statusMessage = "Picture-in-Picture detected"
            } else {
                if !windows.contains(where: { $0.id == selectedID }) { selectedID = nil }
                selectionWasAutoDetected = false
                statusMessage = "No Picture-in-Picture window detected"
            }
        } catch { record(error) }
    }

    func syncGeometryFields() { guard let frame = selected?.ax.frame else { return }; setGeometryFields(frame) }
    func setWidthText(_ value: String) { widthText = value; guard let width = Double(value), width > 0, let ratio = selectedAspectRatio else { return }; heightText = format(CGFloat(width) / ratio) }
    func setHeightText(_ value: String) { heightText = value; guard let height = Double(value), height > 0, let ratio = selectedAspectRatio else { return }; widthText = format(CGFloat(height) * ratio) }
    private var selectedAspectRatio: CGFloat? { guard let size = selected?.ax.frame?.size, size.width > 0, size.height > 0 else { return nil }; return size.width / size.height }

    func applyFields() {
        guard let x = Double(xText), let y = Double(yText), let width = Double(widthText), let height = Double(heightText), width > 0, height > 0 else { record("Geometry requires four numbers; width and height must be positive."); return }
        apply(CGRect(x: x, y: y, width: width, height: height))
    }

    func apply(_ frame: CGRect) {
        guard let id = selectedID else { record("Open a Picture-in-Picture window first."); return }
        do {
            try ax.setFrame(id: id, frame: frame)
            setGeometryFields(frame)
            updateCachedFrame(id: id, frame: frame)
            statusMessage = "PiP placed at \(Int(frame.minX)), \(Int(frame.minY)) · \(Int(frame.width))×\(Int(frame.height))"
        } catch { record(error) }
    }

    private func setGeometryFields(_ frame: CGRect) { xText = format(frame.minX); yText = format(frame.minY); widthText = format(frame.width); heightText = format(frame.height) }
    private func format(_ value: CGFloat) -> String { value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value) }
    private func updateCachedFrame(id: String, frame: CGRect) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        let old = windows[index]
        let updated = AXWindowSnapshot(id: old.ax.id, pid: old.ax.pid, owner: old.ax.owner, title: old.ax.title, role: old.ax.role, subrole: old.ax.subrole, frame: frame, capabilities: old.ax.capabilities)
        windows[index] = WindowSnapshot(ax: updated, cg: old.cg, score: scorer.score(updated, cg: old.cg))
    }

    func corner(_ index: Int) {
        guard let size = selected?.ax.frame?.size else { return }
        let screens = NSScreen.screens.map { $0.visibleFrame }
        guard let visible = screens.first else { return }
        let desktop = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        apply(CoordinateConverter.corner(index, size: size, visible: CoordinateConverter.appKitToGlobalTopLeft(visible, desktop: desktop)))
    }

    func analyze(placeWhenReady: Bool = false) {
        guard analysisTask == nil else { return }
        guard selected?.ax.frame != nil else { record("Open a Picture-in-Picture window, then try again."); return }
        guard screenAuth.isGranted else { record("Screen Recording permission is required for placement analysis."); return }
        analysisTask = Task { await analyzeOnce(placeWhenReady: placeWhenReady); analysisTask = nil }
    }

    private func analyzeOnce(placeWhenReady: Bool) async {
        guard !isAnalyzing, let selected, let frame = selected.ax.frame else { return }
        isAnalyzing = true
        statusMessage = "Analyzing screen…"
        defer { isAnalyzing = false }
        do {
            let map = try await Phase2Capture.captureMap(excluding: selected.cg?.id)
            guard !Task.isCancelled else { return }
            let ratio = frame.width / frame.height
            let minimumWidth = CGFloat(minimumPiPWidth)
            let maximumFraction = CGFloat(maximumScreenFraction)
            let result = PlacementOptimizer.best(map: map, aspectRatio: ratio, minSize: CGSize(width: minimumWidth, height: minimumWidth / ratio), maxSize: CGSize(width: map.bounds.width * maximumFraction, height: map.bounds.height * maximumFraction), costBudget: 0.24, highCostThreshold: 0.38, maxHighCostFraction: 0.025)
            proposedPlacement = result?.frame
            heatmap = ScoringMapGenerator.heatmap(map, placement: result?.frame).map { NSImage(cgImage: $0, size: .zero) }
            if let result {
                setGeometryFields(result.frame)
                statusMessage = "Placement ready · \(Int(result.frame.width))×\(Int(result.frame.height))"
                if placeWhenReady { apply(result.frame) }
            } else { record("No placement satisfied the scoring-map cost budget.") }
        } catch { record("Screen analysis failed: \(error)") }
    }

    func applyProposedPlacement() { guard let proposedPlacement else { return }; apply(proposedPlacement) }
    private func startAutomatically() {
        guard !didStartAutomatically else { return }
        didStartAutomatically = true
        guard auth.isTrusted else { statusMessage = "Grant Accessibility to start automatic placement"; return }
        guard screenAuth.isGranted else { statusMessage = "Grant Screen Recording to start automatic placement"; return }
        statusMessage = "Looking for Picture-in-Picture…"
        setLivePlacement(true)
    }
    func setLivePlacement(_ enabled: Bool) {
        livePlacementEnabled = enabled
        liveTask?.cancel()
        liveTask = nil
        guard enabled else { statusMessage = "Live placement off"; return }
        guard auth.isTrusted else { livePlacementEnabled = false; record("Accessibility permission is required for live placement."); return }
        guard screenAuth.isGranted else { livePlacementEnabled = false; record("Screen Recording permission is required for live placement."); return }
        statusMessage = "Live placement on"
        liveTask = Task {
            while !Task.isCancelled {
                refresh()
                await analyzeOnce(placeWhenReady: true)
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    func record(_ error: Error) { record(String(describing: error)) }
    func record(_ message: String) { errors.insert(message, at: 0); if errors.count > 25 { errors.removeLast(errors.count - 25) }; statusMessage = message }
    func setMinimumPiPWidth(_ value: Double) { minimumPiPWidth = value; UserDefaults.standard.set(value, forKey: "minimumPiPWidth") }
    func setMaximumScreenFraction(_ value: Double) { maximumScreenFraction = value; UserDefaults.standard.set(value, forKey: "maximumScreenFraction") }
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            statusMessage = launchAtLoginEnabled ? "PiP Tidy will launch at login" : "Launch at login disabled"
        } catch { launchAtLoginEnabled = SMAppService.mainApp.status == .enabled; record("Could not update launch at login: \(error.localizedDescription)") }
    }
    func openInfoURL(key: String) {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, let url = URL(string: value) else { record("This link has not been configured for this build."); return }
        NSWorkspace.shared.open(url)
    }
    func copyDiagnostics() {
        let selection = selected.map { "\($0.ax.owner) · \($0.ax.title ?? "Untitled") · \($0.ax.frame.map(NSStringFromRect) ?? "No frame")" } ?? "No PiP selected"
        let value = "PiP Tidy 0.2.0-beta\nAccessibility: \(auth.isTrusted)\nScreen Recording: \(screenAuth.isGranted)\nSelected: \(selection)\nStatus: \(statusMessage)\nRecent errors:\n\(errors.prefix(6).joined(separator: "\n"))"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    deinit { liveTask?.cancel(); analysisTask?.cancel() }
}

@main struct PiPTidyApp: App {
    @StateObject private var store = WindowStore()
    var body: some Scene {
        MenuBarExtra("PiP Tidy", systemImage: "pip") {
            Text(store.statusMessage)
            Divider()
            Label(store.auth.isTrusted ? "Accessibility granted" : "Accessibility required", systemImage: store.auth.isTrusted ? "checkmark.circle" : "exclamationmark.triangle")
            Label(store.screenAuth.isGranted ? "Screen Recording granted" : "Screen Recording required", systemImage: store.screenAuth.isGranted ? "checkmark.circle" : "exclamationmark.triangle")
            if !store.auth.isTrusted { Button("Grant Accessibility…") { store.auth.request() } }
            if !store.screenAuth.isGranted { Button("Grant Screen Recording…") { store.screenAuth.request() } }
            Divider()
            Text("PiP: \(store.selected?.ax.owner ?? "Not detected")")
            Toggle("Live Optimal Placement", isOn: Binding(get: { store.livePlacementEnabled }, set: { store.setLivePlacement($0) }))
            Button("Refresh now") { store.refresh() }
            Divider()
            SettingsLink { Text("Settings and Details…") }
            Button("Send Feedback…") { store.openInfoURL(key: "PiPTidyFeedbackURL") }
            Button("Check for Updates…") { store.openInfoURL(key: "PiPTidyReleasesURL") }
            Button("PiP Tidy Website…") { store.openInfoURL(key: "PiPTidyWebsiteURL") }
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }.menuBarExtraStyle(.menu)
        Settings { DebugView().environmentObject(store).frame(minWidth: 1050, minHeight: 650) }
    }
}

struct DebugView: View {
    @EnvironmentObject var store: WindowStore
    @AppStorage("completedOnboarding") private var completedOnboarding = false
    var body: some View {
        VStack(alignment: .leading) {
            if !completedOnboarding { welcomeCard }
            permissionBanner
            HStack { Button("Refresh") { store.refresh() }; Text("Global top-left coordinates in points"); Spacer(); Text("0.2.0 Beta") }.padding(.horizontal)
            Table(store.windows, selection: $store.selectedID) {
                TableColumn("App") { Text($0.ax.owner) }
                TableColumn("Title") { Text($0.ax.title ?? "—") }
                TableColumn("Role") { Text([$0.ax.role, $0.ax.subrole].compactMap { $0 }.joined(separator: " / ")) }
                TableColumn("Frame") { Text($0.ax.frame.map { NSStringFromRect($0) } ?? "—") }
                TableColumn("Move/Resize") { Text("\($0.ax.capabilities.movable == true ? "Y" : "N")/\($0.ax.capabilities.resizable == true ? "Y" : "N")") }
                TableColumn("CG") { Text($0.cg.map { "#\($0.id) L\($0.layer)" } ?? "ambiguous/unavailable") }
                TableColumn("Score") { Text(String(format: "%.0f", $0.score.total)).help($0.score.components.map { "\($0.points): \($0.reason)" }.joined(separator: "\n")) }
            }.frame(minHeight: 300)
            controls
            phase2
            Divider()
            Text("Recent errors").font(.headline)
            ForEach(Array(store.errors.prefix(6).enumerated()), id: \.offset) { Text($0.element).foregroundStyle(.red).textSelection(.enabled) }
        }.padding().onChange(of: store.selectedID) { store.syncGeometryFields() }
    }

    var permissionBanner: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) { Text("Setup").font(.headline); Text("Accessibility moves PiP; Screen Recording calculates placements. Screen images stay on this Mac.").foregroundStyle(.secondary) }
            Spacer()
            if !store.auth.isTrusted { Button("Grant Accessibility") { store.auth.request() } }
            if !store.screenAuth.isGranted { Button("Grant Screen Recording") { store.screenAuth.request() } }
        }.padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    var welcomeCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("Welcome to PiP Tidy").font(.title2.bold())
                Text("Grant both permissions, then open a browser PiP video. PiP Tidy detects it and starts Live Placement automatically.").foregroundStyle(.secondary)
            }
            Spacer()
            Button("Got it") { completedOnboarding = true }.buttonStyle(.borderedProminent)
        }.padding().background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    var controls: some View {
        HStack {
            ForEach(0..<4) { index in Button(["Top Left", "Top Right", "Bottom Left", "Bottom Right"][index]) { store.corner(index) } }
            Divider()
            field("x", $store.xText); field("y", $store.yText)
            field("width", Binding(get: { store.widthText }, set: { store.setWidthText($0) }))
            field("height", Binding(get: { store.heightText }, set: { store.setHeightText($0) }))
            Button("Apply exact geometry") { store.applyFields() }
        }.disabled(store.selectedID == nil)
    }

    func field(_ label: String, _ value: Binding<String>) -> some View { HStack(spacing: 3) { Text(label); TextField(label, text: value).frame(width: 70).textFieldStyle(.roundedBorder) } }
    var phase2: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading) {
                Text("Scoring-map placement").font(.headline)
                HStack { Button(store.isAnalyzing ? "Analyzing…" : "Analyze Screen") { store.analyze() }.disabled(store.selectedID == nil || store.isAnalyzing); Button("Place Optimally") { store.applyProposedPlacement() }.disabled(store.proposedPlacement == nil); Toggle("Live", isOn: Binding(get: { store.livePlacementEnabled }, set: { store.setLivePlacement($0) })) }
                Text(store.proposedPlacement.map { "Proposed: \(NSStringFromRect($0))" } ?? "Analyze to calculate the largest low-cost placement.").foregroundStyle(.secondary)
                Text(store.statusMessage).foregroundStyle(.secondary)
                Button("Copy diagnostics") { store.copyDiagnostics() }
                Divider()
                Text("Preferences").font(.headline)
                HStack { Text("Smallest PiP"); Slider(value: Binding(get: { store.minimumPiPWidth }, set: { store.setMinimumPiPWidth($0) }), in: 180...600, step: 20).frame(width: 180); Text("\(Int(store.minimumPiPWidth)) pt").monospacedDigit() }
                HStack { Text("Largest PiP"); Slider(value: Binding(get: { store.maximumScreenFraction }, set: { store.setMaximumScreenFraction($0) }), in: 0.30...0.75, step: 0.05).frame(width: 180); Text("\(Int(store.maximumScreenFraction * 100))% of display").monospacedDigit() }
                Toggle("Launch PiP Tidy at login", isOn: Binding(get: { store.launchAtLoginEnabled }, set: { store.setLaunchAtLogin($0) }))
                HStack { Button("Send Feedback…") { store.openInfoURL(key: "PiPTidyFeedbackURL") }; Button("Check for Updates…") { store.openInfoURL(key: "PiPTidyReleasesURL") }; Button("Website…") { store.openInfoURL(key: "PiPTidyWebsiteURL") } }
            }
            Spacer()
            if let image = store.heatmap { Image(nsImage: image).resizable().interpolation(.none).scaledToFit().frame(width: 280, height: 160).border(.secondary); Text("black outline = proposed PiP") }
        }.padding(.vertical, 8)
    }
}
