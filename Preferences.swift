import AppKit
import ServiceManagement

@MainActor final class ShortcutRecorder:NSControl {
    var shortcut:Shortcut?,changed:((Shortcut?)->Void)?,recordingChanged:((Bool)->Void)?
    var recording=false
    override var acceptsFirstResponder:Bool{true}
    override func draw(_ rect:NSRect){NSColor(calibratedWhite:0.18,alpha:1).setFill();let p=NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:6,yRadius:6);p.fill();(recording ? NSColor.systemBlue:NSColor.lightGray).setStroke();p.lineWidth=recording ? 2:1;p.stroke();let text=recording ? "按下快捷键，Esc 取消":shortcut?.display ?? "点击设置快捷键";let a:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:15,weight:.medium),.foregroundColor:textWhite];let size=(text as NSString).size(withAttributes:a);(text as NSString).draw(at:NSPoint(x:(bounds.width-size.width)/2,y:(bounds.height-size.height)/2),withAttributes:a)}
    override func mouseDown(with event:NSEvent){window?.makeFirstResponder(self);recording=true;recordingChanged?(true);needsDisplay=true}
    override func keyDown(with event:NSEvent){guard recording else{return};if event.keyCode==53{stop();return};if [51,117].contains(event.keyCode){shortcut=nil;changed?(nil);stop();return};let flags=event.modifierFlags.intersection([.command,.shift,.option,.control]);guard !flags.intersection([.command,.option,.control]).isEmpty else{NSSound.beep();return};let combo=Shortcut(code:UInt32(event.keyCode),flags:flags.rawValue,key:event.charactersIgnoringModifiers?.uppercased() ?? "?");shortcut=combo;changed?(combo);stop()}
    override func performKeyEquivalent(with event:NSEvent)->Bool{if recording{keyDown(with:event);return true};return super.performKeyEquivalent(with:event)}
    override func resignFirstResponder()->Bool{if recording{stop()};return true}
    func stop(){recording=false;recordingChanged?(false);needsDisplay=true}
    func clear(){shortcut=nil;changed?(nil);stop()}
}
@MainActor final class PreferenceTab:NSControl {
    let page:String,imageView=NSImageView(),caption=label("",size:12)
    init(page:String,title:String,symbol:String){self.page=page;super.init(frame:NSRect(x:0,y:0,width:88,height:76));wantsLayer=true;layer?.cornerRadius=7;imageView.image=NSImage(systemSymbolName:symbol,accessibilityDescription:nil);imageView.symbolConfiguration=NSImage.SymbolConfiguration(pointSize:31,weight:.regular);imageView.frame=NSRect(x:23,y:26,width:42,height:42);caption.stringValue=title;caption.alignment = .center;caption.frame=NSRect(x:0,y:6,width:88,height:20);addSubview(imageView);addSubview(caption);setAccessibilityElement(true);setAccessibilityRole(.button);setAccessibilityLabel(title)}
    required init?(coder:NSCoder){fatalError()}
    func select(_ selected:Bool){layer?.backgroundColor=(selected ? NSColor(srgbRed:0.30,green:0.30,blue:0.29,alpha:1):NSColor.clear).cgColor;let color=selected ? NSColor.systemBlue:NSColor(calibratedWhite:0.75,alpha:1);imageView.contentTintColor=color;caption.textColor=color}
    override func mouseDown(with event:NSEvent){sendAction(action,to:target)}
    override func accessibilityPerformPress()->Bool{sendAction(action,to:target);return true}
}
@MainActor final class PreferencesController:NSObject,NSWindowDelegate {
    let state:TextState
    let window:NSWindow
    var onIcon:((Int)->Void)?,onHotkeys:(()->Void)?,onRecording:((Bool)->Void)?
    let host=NSView(),preferenceRoot=NSView(),header=NSView(),footer=NSView(),bodyScroll=NSScrollView(),titleLabel=label("通用",size:15,bold:true)
    var tabs:[PreferenceTab]=[]
    var selected="general",fields:[NSSecureTextField]=[],freeSwitch=NSButton(),usageLabel=label("",size:12)
    var captureRecorder:ShortcutRecorder?,resultsRecorder:ShortcutRecorder?
    init(state:TextState){self.state=state;window=NSWindow(contentRect:NSRect(x:0,y:0,width:270,height:203),styleMask:[.titled,.closable,.resizable,.fullSizeContentView],backing:.buffered,defer:false);super.init();window.delegate=self;window.minSize=NSSize(width:240,height:180);window.title="通用";window.titlebarAppearsTransparent=true;window.appearance=NSAppearance(named:.darkAqua);window.backgroundColor=panelGray;window.isReleasedWhenClosed=false;window.standardWindowButton(.miniaturizeButton)?.isHidden=true;window.standardWindowButton(.zoomButton)?.isHidden=true;window.toolbarStyle = .preference;window.titleVisibility = .hidden;window.contentView=preferenceRoot;bodyScroll.drawsBackground=false;bodyScroll.hasVerticalScroller=true;bodyScroll.autohidesScrollers=true;bodyScroll.borderType = .noBorder;bodyScroll.documentView=host;preferenceRoot.addSubview(bodyScroll);preferenceRoot.addSubview(footer);preferenceRoot.addSubview(header);header.wantsLayer=true;header.layer?.backgroundColor=NSColor(calibratedWhite:0.30,alpha:1).cgColor;titleLabel.alignment = .center;header.addSubview(titleLabel)
        for (index,info) in [("general","通用","iphone"),("account","账户","person.fill"),("shortcuts","快捷键","command")].enumerated(){let tab=PreferenceTab(page:info.0,title:info.1,symbol:info.2);tab.target=self;tab.action=#selector(tabClicked(_:));tabs.append(tab);header.addSubview(tab);tab.frame=NSRect(x:131+index*96,y:10,width:88,height:76)}
        window.center();select("general")}
    func show(_ page:String?=nil){if let page{select(page)};NSApp.activate(ignoringOtherApps:true);window.makeKeyAndOrderFront(nil)}
    @objc func tabClicked(_ sender:PreferenceTab){select(sender.page)}
    func select(_ id:String){
        selected=id;host.subviews.forEach{$0.removeFromSuperview()};footer.subviews.forEach{$0.removeFromSuperview()}
        window.title=["general":"通用","account":"账户","shortcuts":"快捷键"][id] ?? "偏好设置";titleLabel.stringValue=window.title
        layoutWindow()
        if id=="general"{general()}else if id=="account"{account()}else{shortcuts()}
        host.scrollToVisible(NSRect(x:0,y:host.bounds.height-1,width:1,height:1))
    }
    func windowDidResize(_ notification:Notification){layoutWindow()}
    func layoutWindow(){
        let width=preferenceRoot.bounds.width,height=preferenceRoot.bounds.height,headerHeight:CGFloat=64,footerHeight:CGFloat=selected=="account" ? 26:0
        header.frame=NSRect(x:0,y:height-headerHeight,width:width,height:headerHeight);footer.isHidden=footerHeight==0;footer.frame=NSRect(x:0,y:0,width:width,height:footerHeight)
        bodyScroll.frame=NSRect(x:0,y:footerHeight,width:width,height:max(1,height-headerHeight-footerHeight))
        let minimum:CGFloat=selected=="account" ? 166:selected=="general" ? 165:175
        host.frame=NSRect(x:0,y:0,width:bodyScroll.contentSize.width,height:max(minimum,bodyScroll.contentSize.height))
        let tabWidth:CGFloat=60,gap:CGFloat=8,start=(width-(tabWidth*3+gap*2))/2
        for (index,tab) in tabs.enumerated(){tab.frame=NSRect(x:start+CGFloat(index)*(tabWidth+gap),y:0,width:tabWidth,height:41);tab.imageView.frame=NSRect(x:16,y:15,width:28,height:26);tab.imageView.symbolConfiguration=NSImage.SymbolConfiguration(pointSize:22,weight:.regular);tab.caption.frame=NSRect(x:0,y:0,width:tabWidth,height:16);tab.caption.font=NSFont.systemFont(ofSize:10);tab.select(tab.page==selected)}
        titleLabel.frame=NSRect(x:width/2-100,y:41,width:200,height:20);titleLabel.font=NSFont.systemFont(ofSize:12,weight:.semibold)
    }
    func add(_ view:NSView,_ rect:NSRect,mask:NSView.AutoresizingMask=[.minYMargin]){view.frame=rect;view.autoresizingMask=mask;host.addSubview(view)}
    func general(){
        let w=host.bounds.width,top=host.bounds.height
        let start=NSButton(checkboxWithTitle:"开机自启动",target:self,action:#selector(startup(_:)));start.state=SMAppService.mainApp.status == .enabled ? .on:.off;start.font=NSFont.systemFont(ofSize:12,weight:.medium);add(start,NSRect(x:12,y:top-32,width:w-24,height:24),mask:[.width,.minYMargin]);start.toolTip="登录 Mac 后仅显示菜单栏图标"
        for style in 0...1 {let b=NSButton();b.target=self;b.action=#selector(iconChanged(_:));b.tag=style;b.isBordered=false;b.image=AppArtwork.icon(style:style,size:64);b.imageScaling = .scaleProportionallyUpOrDown;b.wantsLayer=true;b.layer?.borderWidth=state.prefs.iconStyle==style ? 2:0;b.layer?.borderColor=NSColor.systemBlue.cgColor;add(b,NSRect(x:(w-178)/2+CGFloat(style)*114,y:top-108,width:64,height:64),mask:[.minXMargin,.maxXMargin,.minYMargin]);b.setAccessibilityLabel(style==0 ? "圆形程序图标":"圆角方形程序图标")}
        let title=label("程序图标",size:12,bold:true);title.alignment = .center;add(title,NSRect(x:12,y:top-133,width:w-24,height:20),mask:[.width,.minYMargin]);let version=label("版本：1.0.7 · 个人自用版",size:10);version.textColor = .secondaryLabelColor;add(version,NSRect(x:12,y:10,width:w-24,height:18),mask:[.width,.maxYMargin])
    }
    @objc func startup(_ sender:NSButton){do{if sender.state == .on{try SMAppService.mainApp.register();if SMAppService.mainApp.status == .requiresApproval{let alert=NSAlert();alert.messageText="请在系统设置中允许 Text 登录时启动";alert.addButton(withTitle:"打开系统设置");alert.addButton(withTitle:"稍后");if alert.runModal() == .alertFirstButtonReturn{SMAppService.openSystemSettingsLoginItems()}}}else{try SMAppService.mainApp.unregister()}}catch{sender.state=SMAppService.mainApp.status == .enabled ? .on:.off;alert("无法更改开机启动",error.localizedDescription+"\n请先将 Text 安装到“应用程序”文件夹后重试。")}}
    @objc func iconChanged(_ sender:NSButton){state.prefs.iconStyle=sender.tag;state.savePreferences();onIcon?(sender.tag);select("general")}
    func account(){
        fields=[];let w=host.bounds.width,top=host.bounds.height
        let logo=NSImageView();logo.image=AppArtwork.icon(style:state.prefs.iconStyle,size:24);add(logo,NSRect(x:w/2-12,y:top-24,width:24,height:24),mask:[.minXMargin,.maxXMargin,.minYMargin])
        let heading=label("Text · 服务账户",size:12,bold:true);heading.alignment = .center;add(heading,NSRect(x:12,y:top-44,width:w-24,height:16),mask:[.width,.minYMargin])
        let names=["百度 OCR API Key","百度 OCR Secret","百度翻译 APP ID","百度翻译密钥"],values=[state.keys.baiduOCR,state.keys.baiduOCRSecret,state.keys.baiduAppID,state.keys.baiduTranslationSecret]
        for i in 0..<4{let y=top-68-CGFloat(i)*22;add(label(names[i],size:9.5),NSRect(x:12,y:y,width:116,height:20));let field=NSSecureTextField();field.stringValue=values[i];field.placeholderString="尚未配置";field.font=NSFont.systemFont(ofSize:10.5);field.setAccessibilityLabel(names[i]);fields.append(field);add(field,NSRect(x:134,y:y,width:w-146,height:20),mask:[.width,.minYMargin])}
        usageLabel=label("",size:9.5);add(usageLabel,NSRect(x:12,y:0,width:w-24,height:30),mask:[.width,.maxYMargin]);refreshStatus()
        freeSwitch=NSButton(checkboxWithTitle:"启用预设免费用量保护",target:self,action:#selector(guardChanged));freeSwitch.state=state.prefs.freeGuard ? .on:.off;freeSwitch.font=NSFont.systemFont(ofSize:9.5);freeSwitch.frame=NSRect(x:12,y:1,width:preferenceRoot.bounds.width-116,height:24);freeSwitch.autoresizingMask=[.width];footer.addSubview(freeSwitch)
        let save=button("保存密钥",target:self,action:#selector(save(_:)));save.font=NSFont.systemFont(ofSize:11);save.frame=NSRect(x:preferenceRoot.bounds.width-92,y:0,width:80,height:24);save.autoresizingMask=[.minXMargin];footer.addSubview(save)
    }
    func refreshStatus(){guard selected=="account" else{return};state.usage.refresh();let u=state.usage
        usageLabel.stringValue="本月 Text 用量（\(u.month)）\n百度识字：\(u.baiduOCR) 次　百度翻译：\(u.baiduTranslationCalls) 次\(u.baiduTranslationPartial ? "（更新后）":"")"
    }
    func editedKeys()->Credentials?{let values=fields.map{$0.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)};guard values.count==4 else{return nil};var keys=state.keys;keys.baiduOCR=values[0];keys.baiduOCRSecret=values[1];keys.baiduAppID=values[2];keys.baiduTranslationSecret=values[3];return keys}
    @objc func save(_ sender:NSButton){guard let keys=editedKeys() else{return};guard state.saveKeys(keys) else{alert("密钥保存失败",state.detail);return};sender.title="已保存";Task{@MainActor [weak sender] in try? await Task.sleep(nanoseconds:1_500_000_000);sender?.title="保存密钥"}}
    @objc func guardChanged(){if freeSwitch.state == .off{let a=NSAlert();a.messageText="关闭本机用量保护？";a.informativeText="关闭后，Text 不再按预设上限暂停调用，超出服务商免费额度可能产生费用。";a.addButton(withTitle:"保持开启");a.addButton(withTitle:"关闭保护");if a.runModal() != .alertSecondButtonReturn{freeSwitch.state = .on;return}};state.prefs.freeGuard=freeSwitch.state == .on;state.savePreferences()}
    func shortcuts(){
        let w=host.bounds.width,top=host.bounds.height
        add(label("截图识字：",size:12,bold:true),NSRect(x:12,y:top-29,width:w-24,height:20),mask:[.width,.minYMargin]);let capture=ShortcutRecorder(frame:NSRect(x:12,y:top-65,width:w-58,height:30));capture.autoresizingMask=[.width,.minYMargin];capture.shortcut=state.prefs.capture;capture.setAccessibilityLabel("截图识字快捷键");captureRecorder=capture;host.addSubview(capture)
        let clear1=button("×",target:self,action:#selector(clearCapture));clear1.font=NSFont.systemFont(ofSize:21);add(clear1,NSRect(x:w-42,y:top-65,width:30,height:30),mask:[.minXMargin,.minYMargin])
        add(label("显示识别结果：",size:12,bold:true),NSRect(x:12,y:top-107,width:w-24,height:20),mask:[.width,.minYMargin]);let results=ShortcutRecorder(frame:NSRect(x:12,y:top-143,width:w-58,height:30));results.autoresizingMask=[.width,.minYMargin];results.shortcut=state.prefs.results;results.setAccessibilityLabel("显示识别结果快捷键");resultsRecorder=results;host.addSubview(results)
        let clear2=button("×",target:self,action:#selector(clearResults));clear2.font=NSFont.systemFont(ofSize:21);add(clear2,NSRect(x:w-42,y:top-143,width:30,height:30),mask:[.minXMargin,.minYMargin])
        capture.recordingChanged={[weak self] in self?.onRecording?($0)};results.recordingChanged={[weak self] in self?.onRecording?($0)}
        capture.changed={[weak self] combo in guard let self else{return};if let combo,combo==self.state.prefs.results{self.alert("快捷键冲突","此组合已用于显示识别结果");capture.shortcut=self.state.prefs.capture;return};self.state.prefs.capture=combo;self.state.savePreferences();self.onHotkeys?()}
        results.changed={[weak self] combo in guard let self else{return};if let combo,combo==self.state.prefs.capture{self.alert("快捷键冲突","此组合已用于截图识字");results.shortcut=self.state.prefs.results;return};self.state.prefs.results=combo;self.state.savePreferences();self.onHotkeys?()}
        let hint=label("点击快捷键框录入组合；Esc 取消，× 清除。",size:10);hint.textColor = .secondaryLabelColor;add(hint,NSRect(x:12,y:8,width:host.bounds.width-24,height:18),mask:[.width,.maxYMargin])
    }
    @objc func clearCapture(){captureRecorder?.clear()}
    @objc func clearResults(){resultsRecorder?.clear()}
    func alert(_ title:String,_ text:String){let a=NSAlert();a.messageText=title;a.informativeText=text;a.runModal()}
}
@MainActor final class GuideWindow:NSObject {
    static let shared=GuideWindow();var window:NSWindow?,editor:NSTextView?
    func makeWindow(kind:String)->NSWindow{let feedback=kind=="意见反馈"
        let w=NSWindow(contentRect:NSRect(x:0,y:0,width:270,height:203),styleMask:[.titled,.closable,.resizable,.fullSizeContentView],backing:.buffered,defer:false);w.title="Text · "+kind;w.titlebarAppearsTransparent=true;w.backgroundColor=panelGray;w.minSize=NSSize(width:240,height:180);w.appearance=NSAppearance(named:.darkAqua);w.isReleasedWhenClosed=false
        let root=NSView();w.contentView=root;let scroll=NSScrollView(frame:NSRect(x:12,y:feedback ? 44:12,width:246,height:feedback ? 127:159));scroll.autoresizingMask=[.width,.height];scroll.hasVerticalScroller=true;let text=NSTextView(frame:scroll.bounds);text.isEditable=feedback;text.isRichText=false;text.isVerticallyResizable=true;text.isHorizontallyResizable=false;text.minSize=NSSize(width:0,height:scroll.contentSize.height);text.maxSize=NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude);text.textContainer?.containerSize=NSSize(width:scroll.contentSize.width,height:CGFloat.greatestFiniteMagnitude);text.font=NSFont.systemFont(ofSize:11);text.textColor=textWhite;text.backgroundColor=panelGray;text.textContainerInset=NSSize(width:10,height:10);text.autoresizingMask=[.width];text.textContainer?.widthTracksTextView=true;scroll.documentView=text;root.addSubview(scroll)
        if feedback{text.string="Text 意见反馈（本地保存，不会自动发送）\n\n问题描述：\n\n复现步骤：\n\n期望效果：\n\n版本：1.0.7\n系统：\(ProcessInfo.processInfo.operatingSystemVersionString)\n\n请勿填写 API 密钥。";let save=button("保存反馈文件…",target:self,action:#selector(exportFeedback));save.frame=NSRect(x:124,y:8,width:134,height:28);save.autoresizingMask=[.minXMargin,.maxYMargin];root.addSubview(save)}
        else{let name=kind=="配置指南" ? "配置指南":"使用说明";if let url=Bundle.main.url(forResource:name,withExtension:"txt"),let s=try? String(contentsOf:url,encoding:.utf8){text.string=s}else{text.string="Text\n\n点击菜单栏 T 图标开始截图识字或选择文件。\n\n首次使用，请先在偏好设置 → 账户中填写 Google / 百度服务密钥。\n\n结果面板支持编辑原文和译文，按 ⌘ C 复制。\n\n截图快捷键默认 ⌘1，显示结果默认 ⇧⌘R，可在快捷键页修改。"}}
        editor=text;window=w;return w
    }
    func show(kind:String){let w=makeWindow(kind:kind);w.center();NSApp.activate(ignoringOtherApps:true);w.makeKeyAndOrderFront(nil)
    }
    @objc func exportFeedback(){let panel=NSSavePanel();panel.allowedContentTypes=[.plainText];panel.nameFieldStringValue="Text-意见反馈.txt";guard panel.runModal() == .OK,let url=panel.url,let text=editor?.string else{return};do{try text.write(to:url,atomically:true,encoding:.utf8)}catch{let a=NSAlert();a.messageText="保存失败";a.informativeText=error.localizedDescription;a.runModal()}}
}
