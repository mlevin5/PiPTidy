import AppKit
import CoreGraphics
import PiPTidyCore
import ServiceManagement
import SwiftUI

struct SystemScreenCaptureAuthorization {
    var isGranted: Bool { CGPreflightScreenCaptureAccess() }
    func request() -> Bool { CGRequestScreenCaptureAccess() }
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
    @Published var isRefreshing = false
    @Published var debugWindowVisible = false
    @Published var livePlacementEnabled = false
    @Published var selectionWasAutoDetected = false
    @Published var statusMessage = "Ready"
    @Published var minimumPiPWidth = UserDefaults.standard.object(forKey: "minimumPiPWidth") as? Double ?? 240
    @Published var maximumScreenFraction = UserDefaults.standard.object(forKey: "maximumScreenFraction") as? Double ?? 0.55
    @Published var launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    @Published private(set) var accessibilityGranted = AXIsProcessTrusted()
    @Published private(set) var screenRecordingGranted = CGPreflightScreenCaptureAccess()

    private var liveTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var permissionTask: Task<Void, Never>?
    private var didStartAutomatically = false
    private var waitingToStartAutomatically = false
    private var selectedDetectedAt: Date?
    private var temporalState: TemporalStalenessState?
    private var observedMaximumPiPSize: CGSize?
    private var lastBrowserConstrainedProposal: CGRect?
    let auth = SystemAuthorization()
    let screenAuth = SystemScreenCaptureAuthorization()
    let ax = SystemAXService()
    let cg = SystemCGInventory()
    let scorer = DefaultCandidateScorer()

    init() {
        permissionTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshPermissionState()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            self?.startAutomatically()
        }
    }

    var selected: WindowSnapshot? { windows.first { $0.id == selectedID } }

    private nonisolated static func makeInventory(ax:SystemAXService,cg:SystemCGInventory,scorer:DefaultCandidateScorer) throws -> [WindowSnapshot] {
        try autoreleasepool {
            let cgWindows=cg.enumerate()
            var snapshots:[WindowSnapshot]=[]
            for axWindow in try ax.enumerate() {
                let match=WindowCorrelator.match(axWindow,cg:cgWindows)
                snapshots.append(.init(ax:axWindow,cg:match,score:scorer.score(axWindow,cg:match)))
            }
            return snapshots.sorted{$0.score.total == $1.score.total ? $0.id < $1.id : $0.score.total > $1.score.total}
        }
    }

    func refresh() { Task { await refreshInventory() } }

    private func refreshInventory() async {
        guard !isRefreshing else { return }
        isRefreshing=true
        defer { isRefreshing=false }
        do {
            let ax=ax,cg=cg,scorer=scorer
            let task:Task<[WindowSnapshot],Error>=Task.detached(priority:.utility) {try Self.makeInventory(ax:ax,cg:cg,scorer:scorer)}
            let inventory=try await task.value
            guard !Task.isCancelled else { return }
            windows=inventory
            if let detected = PiPDetector.detect(in: windows) {
                if selectedID != detected.id { selectedID=detected.id; selectedDetectedAt=Date(); temporalState=nil; observedMaximumPiPSize=nil; lastBrowserConstrainedProposal=nil; syncGeometryFields() }
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

    func apply(_ frame: CGRect, automatic: Bool = false) {
        guard let id = selectedID else { record("Open a Picture-in-Picture window first."); return }
        do {
            try ax.setFrame(id: id, frame: frame)
            setGeometryFields(frame)
            updateCachedFrame(id: id, frame: frame)
            statusMessage = "PiP placed at \(Int(frame.minX)), \(Int(frame.minY)) · \(Int(frame.width))×\(Int(frame.height))"
        } catch let AccessibilityError.verification(_,actual) where automatic && actual.map({$0.width>0 && $0.height>0}) == true {
            let accepted=actual!
            if accepted.width < frame.width-2 || accepted.height < frame.height-2 {
                observedMaximumPiPSize=accepted.size
            }
            lastBrowserConstrainedProposal=frame
            setGeometryFields(accepted);updateCachedFrame(id:id,frame:accepted)
            statusMessage="PiP placed · browser adjusted to \(Int(accepted.width))×\(Int(accepted.height))"
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
        guard screenRecordingGranted else { record("Screen Recording permission is required for placement analysis."); return }
        analysisTask = Task { await analyzeOnce(placeWhenReady: placeWhenReady); analysisTask = nil }
    }

    private func analyzeOnce(placeWhenReady: Bool) async {
        guard !isAnalyzing, let selected, let frame = selected.ax.frame else { return }
        if placeWhenReady,let selectedDetectedAt,Date().timeIntervalSince(selectedDetectedAt)<2.0 {statusMessage="Picture-in-Picture detected · letting it settle…";return}
        isAnalyzing = true
        statusMessage = "Analyzing screen…"
        defer { isAnalyzing = false }
        do {
            let capture = try await Phase2Capture.captureMap(excluding:selected.cg?.id,temporalState:temporalState)
            temporalState=capture.temporalState
            let map=capture.map
            guard !Task.isCancelled else { return }
            let ratio = frame.width / frame.height
            let minimumWidth = CGFloat(minimumPiPWidth)
            let maximumFraction = CGFloat(maximumScreenFraction)
            let configuredMaximum=CGSize(width:map.bounds.width*maximumFraction,height:map.bounds.height*maximumFraction)
            let maximumSize=observedMaximumPiPSize.map { CGSize(width:min(configuredMaximum.width,$0.width),height:min(configuredMaximum.height,$0.height)) } ?? configuredMaximum
            let result = await Task.detached(priority:.utility) { PlacementOptimizer.best(map:map,aspectRatio:ratio,minSize:CGSize(width:minimumWidth,height:minimumWidth/ratio),maxSize:maximumSize,costBudget:0.24,highCostThreshold:0.38,maxHighCostFraction:0.025) }.value
            if let result { proposedPlacement = result.frame }
            else if !placeWhenReady { proposedPlacement = nil }
            heatmap = debugWindowVisible ? ScoringMapGenerator.heatmap(map,placement:result?.frame).map{NSImage(cgImage:$0,size:.zero)} : nil
            if let result {
                setGeometryFields(result.frame)
                statusMessage = "Placement ready · \(Int(result.frame.width))×\(Int(result.frame.height))"
                if placeWhenReady {
                    let repeatsRejectedGeometry=lastBrowserConstrainedProposal.map { !PlacementStability.shouldMove(from:$0,to:result.frame,minimumOriginDelta:4,minimumSizeDelta:4) } == true
                    if repeatsRejectedGeometry { statusMessage = "PiP is in the closest position Firefox allows" }
                    else if PlacementStability.shouldMove(from: frame, to: result.frame) { apply(result.frame,automatic:true) }
                    else { statusMessage = "PiP is already in a good spot" }
                }
            } else if placeWhenReady { statusMessage = "No safe placement in this frame · keeping PiP where it is" }
            else { record("No placement satisfied the scoring-map cost budget.") }
        } catch { record("Screen analysis failed: \(error)") }
    }

    func applyProposedPlacement() { guard let proposedPlacement else { return }; apply(proposedPlacement) }
    private func startAutomatically() {
        guard !didStartAutomatically else { return }
        didStartAutomatically = true
        guard accessibilityGranted else { waitingToStartAutomatically = true; statusMessage = "Grant Accessibility to start automatic placement"; return }
        guard screenRecordingGranted else { waitingToStartAutomatically = true; statusMessage = "Grant Screen Recording to start automatic placement"; return }
        statusMessage = "Looking for Picture-in-Picture…"
        setLivePlacement(true)
    }
    func setLivePlacement(_ enabled: Bool) {
        livePlacementEnabled = enabled
        liveTask?.cancel()
        liveTask = nil
        guard enabled else { statusMessage = "Live placement off"; return }
        guard accessibilityGranted else { livePlacementEnabled = false; record("Accessibility permission is required for live placement."); return }
        guard screenRecordingGranted else { livePlacementEnabled = false; record("Screen Recording permission is required for live placement."); return }
        statusMessage = "Live placement on"
        liveTask = Task {
            while !Task.isCancelled {
                await refreshInventory()
                await analyzeOnce(placeWhenReady: true)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func record(_ error: Error) { record(String(describing: error)) }
    func record(_ message: String) { errors.insert(message, at: 0); if errors.count > 25 { errors.removeLast(errors.count - 25) }; statusMessage = message }
    func requestAccessibility() {
        auth.request()
        openPrivacySettings(anchor: "Privacy_Accessibility")
        refreshPermissionState()
    }
    func requestScreenRecording() {
        _ = screenAuth.request()
        openPrivacySettings(anchor: "Privacy_ScreenCapture")
        refreshPermissionState()
    }
    private func openPrivacySettings(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"), NSWorkspace.shared.open(url) else {
            record("Could not open Privacy & Security settings.")
            return
        }
    }
    private func refreshPermissionState() {
        accessibilityGranted = auth.isTrusted
        screenRecordingGranted = screenAuth.isGranted
        if waitingToStartAutomatically, accessibilityGranted, screenRecordingGranted {
            waitingToStartAutomatically = false
            statusMessage = "Permissions granted · looking for Picture-in-Picture…"
            setLivePlacement(true)
        }
    }
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
        let value = "PiP Tidy 0.2.0-beta\nAccessibility: \(accessibilityGranted)\nScreen Recording: \(screenRecordingGranted)\nSelected: \(selection)\nStatus: \(statusMessage)\nRecent errors:\n\(errors.prefix(6).joined(separator: "\n"))"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    deinit { liveTask?.cancel(); analysisTask?.cancel(); permissionTask?.cancel() }
}

@main struct PiPTidyApp: App {
    @StateObject private var store = WindowStore()
    var body: some Scene {
        MenuBarExtra("PiP Tidy", systemImage: "pip") {
            Text(store.statusMessage)
            Divider()
            Label(store.accessibilityGranted ? "Accessibility granted" : "Accessibility required", systemImage: store.accessibilityGranted ? "checkmark.circle" : "exclamationmark.triangle")
            Label(store.screenRecordingGranted ? "Screen Recording granted" : "Screen Recording required", systemImage: store.screenRecordingGranted ? "checkmark.circle" : "exclamationmark.triangle")
            if !store.accessibilityGranted { Button("Grant Accessibility…") { store.requestAccessibility() } }
            if !store.screenRecordingGranted { Button("Grant Screen Recording…") { store.requestScreenRecording() } }
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
        Settings { DebugView().environmentObject(store).frame(minWidth: 760, minHeight: 560) }
            .windowResizability(.contentMinSize)
    }
}

struct DebugView: View {
    @EnvironmentObject var store: WindowStore
    @AppStorage("completedOnboarding") private var completedOnboarding = false
    @State private var showAllWindows = false
    private var displayedWindows: [WindowSnapshot] { showAllWindows ? store.windows : store.windows.filter(PiPDetector.isCandidate) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                if !completedOnboarding { welcomeCard }
                permissionBanner
                HStack { Button("Refresh") { store.refresh() }; Toggle("Show all windows",isOn:$showAllWindows).toggleStyle(.checkbox); Spacer(); Text("0.2.0 Beta") }.padding(.horizontal)
                if displayedWindows.isEmpty { Text("No Picture-in-Picture windows detected.").foregroundStyle(.secondary).frame(maxWidth:.infinity,minHeight:80) }
                else {
                    Table(displayedWindows, selection: $store.selectedID) {
                        TableColumn("App") { Text($0.ax.owner) }
                        TableColumn("Title") { Text($0.ax.title ?? "—") }
                        TableColumn("Role") { Text([$0.ax.role, $0.ax.subrole].compactMap { $0 }.joined(separator: " / ")) }
                        TableColumn("Frame") { Text($0.ax.frame.map { NSStringFromRect($0) } ?? "—") }
                        TableColumn("Move/Resize") { Text("\($0.ax.capabilities.movable == true ? "Y" : "N")/\($0.ax.capabilities.resizable == true ? "Y" : "N")") }
                        TableColumn("CG") { Text($0.cg.map { "#\($0.id) L\($0.layer)" } ?? "ambiguous/unavailable") }
                        TableColumn("Score") { Text(String(format: "%.0f", $0.score.total)).help($0.score.components.map { "\($0.points): \($0.reason)" }.joined(separator: "\n")) }
                    }.frame(height:showAllWindows ? 300 : 105)
                }
                controls
                phase2
                Divider()
                Text("Recent errors").font(.headline)
                ForEach(Array(store.errors.prefix(6).enumerated()), id: \.offset) { Text($0.element).foregroundStyle(.red).textSelection(.enabled) }
            }.padding()
        }.background(FloatingSettingsWindow()).onChange(of: store.selectedID) { store.syncGeometryFields() }.onAppear { store.debugWindowVisible=true }.onDisappear { store.debugWindowVisible=false;store.heatmap=nil }
    }

    var permissionBanner: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) { Text("Setup").font(.headline); Text("Accessibility moves PiP; Screen Recording calculates placements. Screen images stay on this Mac.").foregroundStyle(.secondary) }
            Spacer()
            if !store.accessibilityGranted { Button("Grant Accessibility") { store.requestAccessibility() } }
            if !store.screenRecordingGranted { Button("Grant Screen Recording") { store.requestScreenRecording() } }
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Quick placement").font(.headline)
                ForEach(0..<4) { index in Button(["Top Left", "Top Right", "Bottom Left", "Bottom Right"][index]) { store.corner(index) } }
                Spacer()
            }
            HStack(spacing: 12) {
                Text("Exact geometry").font(.headline)
                field("x", $store.xText); field("y", $store.yText)
                field("width", Binding(get: { store.widthText }, set: { store.setWidthText($0) }))
                field("height", Binding(get: { store.heightText }, set: { store.setHeightText($0) }))
                Button("Apply exact geometry") { store.applyFields() }.fixedSize()
                Spacer()
            }
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

private struct FloatingSettingsWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.level = .floating }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { view.window?.level = .floating }
    }
}
