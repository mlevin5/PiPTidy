import SwiftUI
import AppKit
import ScootPiPCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // SwiftPM launches this executable from Terminal without an application bundle.
        // A regular activation policy is required for its debug window to receive keys.
        NSApplication.shared.setActivationPolicy(.regular)
    }
}

@MainActor final class WindowStore: ObservableObject {
    @Published var windows:[WindowSnapshot]=[]; @Published var selectedID:String?; @Published var errors:[String]=[]
    @Published var xText="100"; @Published var yText="100"; @Published var widthText="480"; @Published var heightText="270"
    let auth=SystemAuthorization(); let ax=SystemAXService(); let cg=SystemCGInventory(); let scorer=DefaultCandidateScorer()
    var selected:WindowSnapshot? { windows.first{$0.id==selectedID} }
    func refresh(){ do { let cgs=cg.enumerate(); windows=try ax.enumerate().map { a in let c=WindowCorrelator.match(a,cg:cgs); return WindowSnapshot(ax:a,cg:c,score:scorer.score(a,cg:c)) }.sorted { $0.score.total == $1.score.total ? $0.id<$1.id : $0.score.total>$1.score.total } } catch { errors.insert(String(describing:error),at:0) } }
    func syncGeometryFields() { guard let frame=selected?.ax.frame else{return}; setGeometryFields(frame) }
    func applyFields() { guard let x=Double(xText),let y=Double(yText),let width=Double(widthText),let height=Double(heightText),width>0,height>0 else { errors.insert("Geometry requires four numbers; width and height must be positive.",at:0); return }; apply(CGRect(x:x,y:y,width:width,height:height)) }
    func apply(_ frame:CGRect){ guard let id=selectedID else{return}; do { try ax.setFrame(id:id,frame:frame); setGeometryFields(frame); updateCachedFrame(id:id,frame:frame) } catch { errors.insert(String(describing:error),at:0) } }
    private func setGeometryFields(_ frame:CGRect) { xText=format(frame.minX); yText=format(frame.minY); widthText=format(frame.width); heightText=format(frame.height) }
    private func format(_ value:CGFloat)->String { value.rounded() == value ? String(Int(value)) : String(format:"%.2f",value) }
    private func updateCachedFrame(id:String,frame:CGRect) { guard let index=windows.firstIndex(where:{$0.id==id}) else{return}; let old=windows[index]; let updated=AXWindowSnapshot(id:old.ax.id,pid:old.ax.pid,owner:old.ax.owner,title:old.ax.title,role:old.ax.role,subrole:old.ax.subrole,frame:frame,capabilities:old.ax.capabilities); windows[index]=WindowSnapshot(ax:updated,cg:old.cg,score:scorer.score(updated,cg:old.cg)) }
    func corner(_ index:Int){ guard let s=selected?.ax.frame?.size else{return}; let screens=NSScreen.screens.map{$0.visibleFrame}; guard let v=screens.first else{return}; apply(CoordinateConverter.corner(index,size:s,visible:CoordinateConverter.appKitToGlobalTopLeft(v,desktop:NSScreen.screens.reduce(.null){$0.union($1.frame)}))) }
}

@main struct ScootPiPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store=WindowStore()
    var body: some Scene {
        MenuBarExtra("ScootPiP",systemImage:"pip") { Text("Automation: Phase 1 manual only").foregroundStyle(.secondary); Text(store.auth.isTrusted ? "Accessibility: Granted":"Accessibility: Required"); Text("Selected: \(store.selected?.ax.owner ?? "None")"); Button("Request Accessibility Permission"){store.auth.request()}; Button("Refresh"){store.refresh()}; SettingsLink{Text("Debug Window")}; Divider(); Button("Quit"){NSApplication.shared.terminate(nil)} }.menuBarExtraStyle(.menu)
        Settings { DebugView().environmentObject(store).frame(minWidth:1050,minHeight:650) }
    }
}

struct DebugView:View {
    @EnvironmentObject var store:WindowStore
    var body:some View { VStack(alignment:.leading){ HStack{Button("Refresh"){store.refresh()}; Text("Global top-left coordinates in points"); Spacer(); Text("No automatic selection or movement")}.padding(); Table(store.windows,selection:$store.selectedID){ TableColumn("App"){Text($0.ax.owner)}; TableColumn("Title"){Text($0.ax.title ?? "—")}; TableColumn("Role"){Text([$0.ax.role,$0.ax.subrole].compactMap{$0}.joined(separator:" / "))}; TableColumn("Frame"){Text($0.ax.frame.map{NSStringFromRect($0)} ?? "—")}; TableColumn("Move/Resize"){Text("\($0.ax.capabilities.movable == true ? "Y":"N")/\($0.ax.capabilities.resizable == true ? "Y":"N")")}; TableColumn("CG") {Text($0.cg.map{"#\($0.id) L\($0.layer)"} ?? "ambiguous/unavailable")}; TableColumn("Score"){Text(String(format:"%.0f",$0.score.total)).help($0.score.components.map{"\($0.points): \($0.reason)"}.joined(separator:"\n"))} }.frame(minHeight:350); controls; Divider(); Text("Recent errors").font(.headline); ForEach(Array(store.errors.prefix(6).enumerated()),id:\.offset){Text($0.element).foregroundStyle(.red).textSelection(.enabled)} }.padding().background(WindowActivator()).onChange(of:store.selectedID){store.syncGeometryFields()} }
    var controls:some View { HStack{ ForEach(0..<4){i in Button(["Top Left","Top Right","Bottom Left","Bottom Right"][i]){store.corner(i)}}; Divider(); field("x",$store.xText); field("y",$store.yText); field("width",$store.widthText); field("height",$store.heightText); Button("Apply exact geometry"){store.applyFields()} }.disabled(store.selectedID == nil) }
    func field(_ label:String,_ value:Binding<String>)->some View { HStack(spacing:3){Text(label);TextField(label,text:value).frame(width:70).textFieldStyle(.roundedBorder)} }
}

/// A menu-bar app can show a Settings window without automatically taking keyboard focus.
/// Promote this specific SwiftUI window to the key window once AppKit has attached it.
private struct WindowActivator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ActivatingView() }
    func updateNSView(_ view: NSView, context: Context) {}
}

private final class ActivatingView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
        window.makeMain()
        window.makeKeyAndOrderFront(nil)
    }
}
