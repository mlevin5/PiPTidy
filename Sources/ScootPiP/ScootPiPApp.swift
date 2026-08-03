import SwiftUI
import AppKit
import ScootPiPCore

@MainActor final class WindowStore: ObservableObject {
    @Published var windows:[WindowSnapshot]=[]; @Published var selectedID:String?; @Published var errors:[String]=[]; @Published var geometry=CGRect(x:100,y:100,width:480,height:270)
    let auth=SystemAuthorization(); let ax=SystemAXService(); let cg=SystemCGInventory(); let scorer=DefaultCandidateScorer()
    var selected:WindowSnapshot? { windows.first{$0.id==selectedID} }
    func refresh(){ do { let cgs=cg.enumerate(); windows=try ax.enumerate().map { a in let c=WindowCorrelator.match(a,cg:cgs); return WindowSnapshot(ax:a,cg:c,score:scorer.score(a,cg:c)) }.sorted { $0.score.total == $1.score.total ? $0.id<$1.id : $0.score.total>$1.score.total } } catch { errors.insert(String(describing:error),at:0) } }
    func apply(_ frame:CGRect){ guard let id=selectedID else{return}; do { try ax.setFrame(id:id,frame:frame); geometry=frame; refresh() } catch { errors.insert(String(describing:error),at:0) } }
    func corner(_ index:Int){ guard let s=selected?.ax.frame?.size else{return}; let screens=NSScreen.screens.map{$0.visibleFrame}; guard let v=screens.first else{return}; apply(CoordinateConverter.corner(index,size:s,visible:CoordinateConverter.appKitToGlobalTopLeft(v,desktop:NSScreen.screens.reduce(.null){$0.union($1.frame)}))) }
}

@main struct ScootPiPApp: App {
    @StateObject private var store=WindowStore()
    var body: some Scene {
        MenuBarExtra("ScootPiP",systemImage:"pip") { Text("Automation: Phase 1 manual only").foregroundStyle(.secondary); Text(store.auth.isTrusted ? "Accessibility: Granted":"Accessibility: Required"); Text("Selected: \(store.selected?.ax.owner ?? "None")"); Button("Request Accessibility Permission"){store.auth.request()}; Button("Refresh"){store.refresh()}; SettingsLink{Text("Debug Window")}; Divider(); Button("Quit"){NSApplication.shared.terminate(nil)} }.menuBarExtraStyle(.menu)
        Settings { DebugView().environmentObject(store).frame(minWidth:1050,minHeight:650) }
    }
}

struct DebugView:View {
    @EnvironmentObject var store:WindowStore
    var body:some View { VStack(alignment:.leading){ HStack{Button("Refresh"){store.refresh()}; Text("Global top-left coordinates in points"); Spacer(); Text("No automatic selection or movement")}.padding(); Table(store.windows,selection:$store.selectedID){ TableColumn("App"){Text($0.ax.owner)}; TableColumn("Title"){Text($0.ax.title ?? "—")}; TableColumn("Role"){Text([$0.ax.role,$0.ax.subrole].compactMap{$0}.joined(separator:" / "))}; TableColumn("Frame"){Text($0.ax.frame.map{NSStringFromRect($0)} ?? "—")}; TableColumn("Move/Resize"){Text("\($0.ax.capabilities.movable == true ? "Y":"N")/\($0.ax.capabilities.resizable == true ? "Y":"N")")}; TableColumn("CG") {Text($0.cg.map{"#\($0.id) L\($0.layer)"} ?? "ambiguous/unavailable")}; TableColumn("Score"){Text(String(format:"%.0f",$0.score.total)).help($0.score.components.map{"\($0.points): \($0.reason)"}.joined(separator:"\n"))} }.frame(minHeight:350); controls; Divider(); Text("Recent errors").font(.headline); ForEach(Array(store.errors.prefix(6).enumerated()),id:\.offset){Text($0.element).foregroundStyle(.red).textSelection(.enabled)} }.padding() }
    var controls:some View { HStack{ ForEach(0..<4){i in Button(["Top Left","Top Right","Bottom Left","Bottom Right"][i]){store.corner(i)}}; Divider(); field("x",\.origin.x); field("y",\.origin.y); field("width",\.size.width); field("height",\.size.height); Button("Apply exact geometry"){store.apply(store.geometry)} }.disabled(store.selectedID == nil) }
    func field(_ label:String,_ key:WritableKeyPath<CGRect,CGFloat>)->some View { HStack(spacing:3){Text(label);TextField(label,value:Binding<Double>(get:{Double(store.geometry[keyPath:key])},set:{store.geometry[keyPath:key]=CGFloat($0)}),format:.number).frame(width:70)} }
}
