import SwiftUI
import AppKit
import ScootPiPCore

@MainActor final class WindowStore: ObservableObject {
    @Published var windows:[WindowSnapshot]=[]; @Published var selectedID:String?; @Published var errors:[String]=[]
    @Published var xText="100"; @Published var yText="100"; @Published var widthText="480"; @Published var heightText="270"
    @Published var heatmap:NSImage?; @Published var proposedPlacement:CGRect?; @Published var isAnalyzing=false
    @Published var livePlacementEnabled=false
    private var liveTask:Task<Void,Never>?
    let auth=SystemAuthorization(); let ax=SystemAXService(); let cg=SystemCGInventory(); let scorer=DefaultCandidateScorer()
    var selected:WindowSnapshot? { windows.first{$0.id==selectedID} }
    func refresh(){ do { let cgs=cg.enumerate(); windows=try ax.enumerate().map { a in let c=WindowCorrelator.match(a,cg:cgs); return WindowSnapshot(ax:a,cg:c,score:scorer.score(a,cg:c)) }.sorted { $0.score.total == $1.score.total ? $0.id<$1.id : $0.score.total>$1.score.total } } catch { errors.insert(String(describing:error),at:0) } }
    func syncGeometryFields() { guard let frame=selected?.ax.frame else{return}; setGeometryFields(frame) }
    func setWidthText(_ value:String) { widthText=value; guard let width=Double(value),width>0,let ratio=selectedAspectRatio else{return}; heightText=format(CGFloat(width)/ratio) }
    func setHeightText(_ value:String) { heightText=value; guard let height=Double(value),height>0,let ratio=selectedAspectRatio else{return}; widthText=format(CGFloat(height)*ratio) }
    private var selectedAspectRatio:CGFloat? { guard let size=selected?.ax.frame?.size,size.width>0,size.height>0 else{return nil}; return size.width/size.height }
    func applyFields() { guard let x=Double(xText),let y=Double(yText),let width=Double(widthText),let height=Double(heightText),width>0,height>0 else { errors.insert("Geometry requires four numbers; width and height must be positive.",at:0); return }; apply(CGRect(x:x,y:y,width:width,height:height)) }
    func apply(_ frame:CGRect){ guard let id=selectedID else{return}; do { try ax.setFrame(id:id,frame:frame); setGeometryFields(frame); updateCachedFrame(id:id,frame:frame) } catch { errors.insert(String(describing:error),at:0) } }
    private func setGeometryFields(_ frame:CGRect) { xText=format(frame.minX); yText=format(frame.minY); widthText=format(frame.width); heightText=format(frame.height) }
    private func format(_ value:CGFloat)->String { value.rounded() == value ? String(Int(value)) : String(format:"%.2f",value) }
    private func updateCachedFrame(id:String,frame:CGRect) { guard let index=windows.firstIndex(where:{$0.id==id}) else{return}; let old=windows[index]; let updated=AXWindowSnapshot(id:old.ax.id,pid:old.ax.pid,owner:old.ax.owner,title:old.ax.title,role:old.ax.role,subrole:old.ax.subrole,frame:frame,capabilities:old.ax.capabilities); windows[index]=WindowSnapshot(ax:updated,cg:old.cg,score:scorer.score(updated,cg:old.cg)) }
    func corner(_ index:Int){ guard let s=selected?.ax.frame?.size else{return}; let screens=NSScreen.screens.map{$0.visibleFrame}; guard let v=screens.first else{return}; apply(CoordinateConverter.corner(index,size:s,visible:CoordinateConverter.appKitToGlobalTopLeft(v,desktop:NSScreen.screens.reduce(.null){$0.union($1.frame)}))) }
    func analyze(placeWhenReady:Bool=false) { guard !isAnalyzing,let selected,let frame=selected.ax.frame else{return}; isAnalyzing=true; Task { do { let map=try await Phase2Capture.captureMap(excluding:selected.cg?.id); let ratio=frame.width/frame.height; let result=PlacementOptimizer.best(map:map,aspectRatio:ratio,minSize:CGSize(width:240,height:240/ratio),maxSize:CGSize(width:map.bounds.width*0.55,height:map.bounds.height*0.55),costBudget:0.24,highCostThreshold:0.38,maxHighCostFraction:0.025); proposedPlacement=result?.frame; heatmap=ScoringMapGenerator.heatmap(map,placement:result?.frame).map{NSImage(cgImage:$0,size:.zero)}; if let result { setGeometryFields(result.frame); if placeWhenReady { apply(result.frame) } } else { errors.insert("No placement satisfied the scoring-map cost budget.",at:0) } } catch { errors.insert("Screen analysis failed: \(error)",at:0) }; isAnalyzing=false } }
    func applyProposedPlacement(){guard let proposedPlacement else{return};apply(proposedPlacement)}
    func setLivePlacement(_ enabled:Bool){livePlacementEnabled=enabled;liveTask?.cancel();liveTask=nil;guard enabled else{return};liveTask=Task { while !Task.isCancelled { refresh(); analyze(placeWhenReady:true); try? await Task.sleep(for:.seconds(3)) } } }
}

@main struct ScootPiPApp: App {
    @StateObject private var store=WindowStore()
    var body: some Scene {
        MenuBarExtra("ScootPiP",systemImage:"pip") { Text(store.auth.isTrusted ? "Accessibility: Granted":"Accessibility: Required"); Text("Selected: \(store.selected?.ax.owner ?? "None")"); Button("Request Accessibility Permission"){store.auth.request()}; Divider(); Button("Refresh Windows"){store.refresh()}; Button(store.isAnalyzing ? "Analyzing…":"Analyze Screen"){store.analyze()}.disabled(store.selectedID == nil || store.isAnalyzing); Button("Place Proposed Geometry"){store.applyProposedPlacement()}.disabled(store.proposedPlacement == nil); Toggle("Live Optimal Placement",isOn:Binding(get:{store.livePlacementEnabled},set:{store.setLivePlacement($0)})); Divider(); SettingsLink{Text("Debug Window")}; Button("Quit"){NSApplication.shared.terminate(nil)} }.menuBarExtraStyle(.menu)
        Settings { DebugView().environmentObject(store).frame(minWidth:1050,minHeight:650) }
    }
}

struct DebugView:View {
    @EnvironmentObject var store:WindowStore
    var body:some View { VStack(alignment:.leading){ HStack{Button("Refresh"){store.refresh()}; Text("Global top-left coordinates in points"); Spacer(); Text("Phase 2 placement remains user-triggered")}.padding(); Table(store.windows,selection:$store.selectedID){ TableColumn("App"){Text($0.ax.owner)}; TableColumn("Title"){Text($0.ax.title ?? "—")}; TableColumn("Role"){Text([$0.ax.role,$0.ax.subrole].compactMap{$0}.joined(separator:" / "))}; TableColumn("Frame"){Text($0.ax.frame.map{NSStringFromRect($0)} ?? "—")}; TableColumn("Move/Resize"){Text("\($0.ax.capabilities.movable == true ? "Y":"N")/\($0.ax.capabilities.resizable == true ? "Y":"N")")}; TableColumn("CG") {Text($0.cg.map{"#\($0.id) L\($0.layer)"} ?? "ambiguous/unavailable")}; TableColumn("Score"){Text(String(format:"%.0f",$0.score.total)).help($0.score.components.map{"\($0.points): \($0.reason)"}.joined(separator:"\n"))} }.frame(minHeight:300); controls; phase2; Divider(); Text("Recent errors").font(.headline); ForEach(Array(store.errors.prefix(6).enumerated()),id:\.offset){Text($0.element).foregroundStyle(.red).textSelection(.enabled)} }.padding().onChange(of:store.selectedID){store.syncGeometryFields()} }
    var controls:some View { HStack{ ForEach(0..<4){i in Button(["Top Left","Top Right","Bottom Left","Bottom Right"][i]){store.corner(i)}}; Divider(); field("x",$store.xText); field("y",$store.yText); field("width",Binding(get:{store.widthText},set:{store.setWidthText($0)})); field("height",Binding(get:{store.heightText},set:{store.setHeightText($0)})); Button("Apply exact geometry"){store.applyFields()} }.disabled(store.selectedID == nil) }
    func field(_ label:String,_ value:Binding<String>)->some View { HStack(spacing:3){Text(label);TextField(label,text:value).frame(width:70).textFieldStyle(.roundedBorder)} }
    var phase2:some View { HStack(alignment:.top){ VStack(alignment:.leading){Text("Scoring-map placement").font(.headline); HStack{Button(store.isAnalyzing ? "Analyzing…":"Analyze Screen"){store.analyze()}.disabled(store.selectedID == nil || store.isAnalyzing); Button("Place Optimally"){store.applyProposedPlacement()}.disabled(store.proposedPlacement == nil); Toggle("Live",isOn:Binding(get:{store.livePlacementEnabled},set:{store.setLivePlacement($0)}))}; Text(store.proposedPlacement.map{"Proposed: \(NSStringFromRect($0))"} ?? "Analyze to calculate the largest low-cost placement.").foregroundStyle(.secondary) }; Spacer(); if let image=store.heatmap { Image(nsImage:image).resizable().interpolation(.none).scaledToFit().frame(width:280,height:160).border(.secondary); Text("black outline = proposed PiP") } }.padding(.vertical,8) }
}
