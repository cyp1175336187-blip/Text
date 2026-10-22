import AppKit
import Carbon

@MainActor enum AppArtwork {
    static func icon(style:Int,size:CGFloat)->NSImage {
        NSImage(size:NSSize(width:size,height:size),flipped:false){rect in
            let r=rect.insetBy(dx:size*0.07,dy:size*0.07),path=style==0 ? NSBezierPath(ovalIn:r):NSBezierPath(roundedRect:r,xRadius:size*0.19,yRadius:size*0.19)
            NSColor.white.setFill();path.fill()
            NSColor(srgbRed:0.88,green:0.90,blue:0.89,alpha:1).setStroke();path.lineWidth=size*0.012;path.stroke()
            let attrs:[NSAttributedString.Key:Any]=[.font:NSFont(name:"TimesNewRomanPS-BoldMT",size:size*0.66) ?? NSFont.systemFont(ofSize:size*0.66,weight:.bold),.foregroundColor:NSColor(srgbRed:0.05,green:0.58,blue:0.25,alpha:1)]
            let t="T" as NSString,s=t.size(withAttributes:attrs);t.draw(at:NSPoint(x:(size-s.width)/2,y:(size-s.height)/2+size*0.018),withAttributes:attrs);return true
        }
    }
    static func menuMonogram()->NSImage {
        let image=NSImage(size:NSSize(width:20,height:20),flipped:false){_ in
            let text="T" as NSString,attrs:[NSAttributedString.Key:Any]=[.font:NSFont(name:"TimesNewRomanPSMT",size:21) ?? NSFont.systemFont(ofSize:21),.foregroundColor:NSColor.black]
            let size=text.size(withAttributes:attrs);text.draw(at:NSPoint(x:(20-size.width)/2,y:(20-size.height)/2+1),withAttributes:attrs);return true
        };image.isTemplate=true;return image
    }
    static func recognitionDisc(progress:Double)->NSImage {
        let fraction=min(1,max(0,progress))
        let image=NSImage(size:NSSize(width:18,height:18),flipped:false){_ in
            NSColor.black.setStroke();NSColor.black.setFill()
            let circle=NSBezierPath(ovalIn:NSRect(x:1.5,y:1.5,width:15,height:15));circle.lineWidth=1.1;circle.stroke()
            if fraction>=1{NSBezierPath(ovalIn:NSRect(x:2,y:2,width:14,height:14)).fill()}
            else if fraction>0{let wedge=NSBezierPath();wedge.move(to:NSPoint(x:9,y:9));wedge.appendArc(withCenter:NSPoint(x:9,y:9),radius:7,startAngle:90,endAngle:CGFloat(90-fraction*360),clockwise:true);wedge.close();wedge.fill()};return true
        };image.isTemplate=true;return image
    }
    static func makeIcons(_ folder:URL)throws {
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        for style in 0...1{let dir=folder.appendingPathComponent(style==0 ? "Circle.iconset":"Square.iconset");try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
            for size in [16,32,64,128,256,512,1024]{let image=icon(style:style,size:CGFloat(size));guard let tiff=image.tiffRepresentation,let rep=NSBitmapImageRep(data:tiff),let data=rep.representation(using:.png,properties:[:]) else{continue};var names:[String]=[]
                switch size{case 16:names=["icon_16x16.png"];case 32:names=["icon_16x16@2x.png","icon_32x32.png"];case 64:names=["icon_32x32@2x.png"];case 128:names=["icon_128x128.png"];case 256:names=["icon_128x128@2x.png","icon_256x256.png"];case 512:names=["icon_256x256@2x.png","icon_512x512.png"];default:names=["icon_512x512@2x.png"]}
                for name in names{try data.write(to:dir.appendingPathComponent(name))}
            }
        }
    }
}
@MainActor final class StatusDropTarget:NSView {
    weak var owner:TextApp?
    var highlighted=false
    override init(frame:NSRect){super.init(frame:frame);registerForDraggedTypes([.fileURL,.png,.tiff]);toolTip="Text · 截图识字、翻译；可拖入图片或 PDF";setAccessibilityElement(true);setAccessibilityRole(.button);setAccessibilityLabel("Text 菜单栏")}
    required init?(coder:NSCoder){fatalError()}
    override func draw(_ rect:NSRect){if highlighted{NSColor.systemBlue.withAlphaComponent(0.3).setFill();NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:4,yRadius:4).fill()}}
    override func mouseDown(with event:NSEvent){owner?.showMenu()}
    override func rightMouseDown(with event:NSEvent){owner?.showMenu()}
    override func accessibilityPerformPress()->Bool{owner?.showMenu();return true}
    override func draggingEntered(_ sender:NSDraggingInfo)->NSDragOperation{guard owner?.state.busy==false else{return []};highlighted=true;needsDisplay=true;return .copy}
    override func draggingExited(_ sender:NSDraggingInfo?){highlighted=false;needsDisplay=true}
    override func performDragOperation(_ sender:NSDraggingInfo)->Bool{highlighted=false;needsDisplay=true;let pb=sender.draggingPasteboard;if let urls=pb.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL],!urls.isEmpty{owner?.state.recognize(urls);return true};if let image=NSImage(pasteboard:pb),let tiff=image.tiffRepresentation{let folder=FileManager.default.temporaryDirectory.appendingPathComponent("text-drop-"+UUID().uuidString,isDirectory:true);do{try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);let file=folder.appendingPathComponent("拖入图片.tiff");try tiff.write(to:file);owner?.state.recognize([file],removeAfter:folder);return true}catch{return false}};return false}
}
@MainActor final class TextApp:NSObject,NSApplicationDelegate {
    static weak var current:TextApp?
    let state:TextState
    var statusItem:NSStatusItem!,results:ResultsController!,preferences:PreferencesController!
    var recognitionTimer:Timer?,recognitionDisplayed:Double=0,recognitionCompletedAt:Date?
    var hotkeys:[EventHotKeyRef]=[],handler:EventHandlerRef?,recording=false
    init(state:TextState){self.state=state;super.init()}
    func applicationDidFinishLaunching(_ notification:Notification){Self.current=self;NSApp.setActivationPolicy(.accessory);NSApp.appearance=NSAppearance(named:.darkAqua);NSApp.applicationIconImage=AppArtwork.icon(style:state.prefs.iconStyle,size:256)
        buildEditingMenu();statusItem=NSStatusBar.system.statusItem(withLength:30);if let b=statusItem.button{b.title="";b.image=AppArtwork.menuMonogram();b.toolTip="Text";let drop=StatusDropTarget(frame:b.bounds);drop.autoresizingMask=[.width,.height];drop.owner=self;b.addSubview(drop)}
        results=ResultsController(state:state);results.anchor={[weak self] in guard let b=self?.statusItem.button,let w=b.window else{return .zero};return w.convertToScreen(b.convert(b.bounds,to:nil))}
        preferences=PreferencesController(state:state);preferences.onIcon={style in NSApp.applicationIconImage=AppArtwork.icon(style:style,size:256)};preferences.onHotkeys={[weak self] in self?.registerHotkeys()};preferences.onRecording={[weak self] active in self?.recording=active;self?.registerHotkeys()}
        state.onChange={[weak self] in self?.updateRecognitionIcon();self?.results.refresh();self?.preferences.refreshStatus()};state.onShow={[weak self] in self?.results.show()};state.onSettings={[weak self] in self?.preferences.show("account")};registerHotkeys()
        if Bundle.main.bundleIdentifier?.hasSuffix(".uitest")==true{preferences.show()}else if CommandLine.arguments.contains("--show"){results.show()}
    }
    func restoreMenuIcon(){recognitionTimer?.invalidate();recognitionTimer=nil;recognitionCompletedAt=nil;recognitionDisplayed=0;statusItem?.button?.title="";statusItem?.button?.image=AppArtwork.menuMonogram()}
    func updateRecognitionIcon(){
        guard let b=statusItem?.button else{return}
        if state.busy {
            if state.recognitionProgress==0{recognitionDisplayed=0;recognitionCompletedAt=nil}
            b.title="";b.image=AppArtwork.recognitionDisc(progress:recognitionDisplayed)
            if recognitionTimer==nil{let timer=Timer(timeInterval:1.0/30,repeats:true){[weak self] _ in Task{@MainActor in self?.advanceRecognitionIcon()}};recognitionTimer=timer;RunLoop.main.add(timer,forMode:.common)}
        }else if recognitionTimer==nil || state.recognitionProgress<1{restoreMenuIcon()}
    }
    func advanceRecognitionIcon(){
        guard state.busy || state.recognitionProgress>=1 else{restoreMenuIcon();return}
        let target=state.recognitionProgress
        recognitionDisplayed=min(target,recognitionDisplayed+max(0.015,(target-recognitionDisplayed)*0.3))
        statusItem.button?.image=AppArtwork.recognitionDisc(progress:recognitionDisplayed)
        if !state.busy && recognitionDisplayed>=1{if let completed=recognitionCompletedAt{if Date().timeIntervalSince(completed)>=0.15{restoreMenuIcon()}}else{recognitionCompletedAt=Date()}}
    }
    func buildEditingMenu(){let menu=NSMenu();let app=NSMenuItem();app.submenu=NSMenu(title:"Text");app.submenu?.addItem(withTitle:"退出 Text",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q");let pref=NSMenuItem(title:"偏好设置…",action:#selector(showPreferences),keyEquivalent:",");pref.target=self;app.submenu?.insertItem(pref,at:0)
        if Bundle.main.bundleIdentifier?.hasSuffix(".uitest")==true{let inspect=NSMenuItem(title:"检查菜单",action:#selector(inspectMenu),keyEquivalent:"m");inspect.keyEquivalentModifierMask=[.command,.shift];inspect.target=self;app.submenu?.addItem(inspect)}
        menu.addItem(app);let file=NSMenuItem();file.submenu=NSMenu(title:"文件");let open=NSMenuItem(title:"选择图片文件",action:#selector(choose),keyEquivalent:"o");open.target=self;file.submenu?.addItem(open);menu.addItem(file);let edit=NSMenuItem();let m=NSMenu(title:"编辑");edit.submenu=m;for (name,action,key) in [("撤销",Selector(("undo:")),"z"),("剪切",#selector(NSText.cut(_:)),"x"),("复制",#selector(NSText.copy(_:)),"c"),("粘贴",#selector(NSText.paste(_:)),"v"),("全选",#selector(NSText.selectAll(_:)),"a")]{m.addItem(withTitle:name,action:action,keyEquivalent:key)};menu.addItem(edit);NSApp.mainMenu=menu}
    @objc func inspectMenu(){showMenu()}
    func showMenu(){let menu=NSMenu();menu.autoenablesItems=false;menu.font=NSFont.systemFont(ofSize:14,weight:.semibold)
        for (title,key,action) in [("截图识字","c",#selector(capture)),("选择图片文件","s",#selector(choose))]{let item=NSMenuItem(title:title,action:action,keyEquivalent:key);item.keyEquivalentModifierMask=[];item.target=self;item.isEnabled = !state.busy;menu.addItem(item)}
        menu.addItem(.separator());let result=NSMenuItem(title:"识别结果",action:#selector(showResults),keyEquivalent:"r");result.keyEquivalentModifierMask=[];result.target=self;result.isEnabled = !state.busy;menu.addItem(result)
        let more=NSMenuItem(title:"更多",action:nil,keyEquivalent:"");more.submenu=NSMenu();for (title,action) in [("偏好设置…",#selector(showPreferences)),("使用教程",#selector(tutorial)),("意见反馈",#selector(feedback)),("退出软件",#selector(quit))]{let item=NSMenuItem(title:title,action:action,keyEquivalent:"");item.target=self;more.submenu?.addItem(item)};menu.addItem(more)
        if let b=statusItem.button{menu.popUp(positioning:nil,at:NSPoint(x:0,y:-3),in:b)}
    }
    @objc func capture(){state.capture()}
    @objc func choose(){state.chooseFiles()}
    @objc func showResults(){state.message=nil;results.show()}
    @objc func showPreferences(){preferences.show()}
    @objc func tutorial(){GuideWindow.shared.show(kind:"使用教程")}
    @objc func feedback(){GuideWindow.shared.show(kind:"意见反馈")}
    @objc func quit(){NSApp.terminate(nil)}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{false}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool{showResults();return true}
    func application(_ sender:NSApplication,openFiles filenames:[String]){state.recognize(filenames.map{URL(fileURLWithPath:$0)});sender.reply(toOpenOrPrint:.success)}
    func applicationWillTerminate(_ notification:Notification){recognitionTimer?.invalidate();state.saveResult();unregister()}
    func unregister(){for key in hotkeys{UnregisterEventHotKey(key)};hotkeys=[];if let handler{RemoveEventHandler(handler);self.handler=nil}}
    func registerHotkeys(){unregister();guard !recording else{return};var spec=EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(),{_,event,_ in guard let event else{return OSStatus(eventNotHandledErr)};var id=EventHotKeyID();GetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),nil,MemoryLayout<EventHotKeyID>.size,nil,&id);let code=id.id;Task{@MainActor in guard let app=TextApp.current else{return};if code==1{app.state.capture()}else{app.showResults()}};return noErr},1,&spec,nil,&handler)
        for (i,combo) in [(UInt32(1),state.prefs.capture),(UInt32(2),state.prefs.results)]{guard let combo else{continue};let flags=NSEvent.ModifierFlags(rawValue:combo.flags);var carbon:UInt32=0;if flags.contains(.command){carbon|=UInt32(cmdKey)};if flags.contains(.option){carbon|=UInt32(optionKey)};if flags.contains(.control){carbon|=UInt32(controlKey)};if flags.contains(.shift){carbon|=UInt32(shiftKey)};var ref:EventHotKeyRef?;let result=RegisterEventHotKey(combo.code,carbon,EventHotKeyID(signature:0x54585431,id:i),GetApplicationEventTarget(),0,&ref);if result==noErr,let ref{hotkeys.append(ref)}else{state.detail="快捷键 \(combo.display) 已被占用，请在偏好设置 → 快捷键中修改"}}
    }
}
