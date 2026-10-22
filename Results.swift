import AppKit

let panelGray=NSColor(srgbRed:0.32,green:0.32,blue:0.32,alpha:1)
let textWhite=NSColor(calibratedWhite:0.93,alpha:1)
func label(_ text:String,size:CGFloat=14,bold:Bool=false)->NSTextField {let field=NSTextField(labelWithString:text);field.font=NSFont.systemFont(ofSize:size,weight:bold ? .semibold:.regular);field.textColor=textWhite;field.lineBreakMode = .byWordWrapping;field.maximumNumberOfLines=0;return field}
func button(_ title:String,target:AnyObject?,action:Selector)->NSButton {let b=NSButton(title:title,target:target,action:action);b.bezelStyle = .rounded;return b}

final class ResultsPanel:NSPanel {
    override var canBecomeKey:Bool{true}
    override var canBecomeMain:Bool{true}
    override func performKeyEquivalent(with event:NSEvent)->Bool{if let content=contentView as? ResultContent,content.performKeyEquivalent(with:event){return true};return super.performKeyEquivalent(with:event)}
}
@MainActor final class ResultsController:NSObject,NSWindowDelegate {
    let state:TextState,panel:ResultsPanel,root:ResultContent
    var anchor:(()->NSRect)?,suppressResize=false
    private var outside:Any?,localOutside:Any?
    init(state:TextState){self.state=state;panel=ResultsPanel(contentRect:NSRect(x:0,y:0,width:state.prefs.width,height:state.prefs.height),styleMask:[.borderless,.resizable,.nonactivatingPanel],backing:.buffered,defer:false);root=ResultContent(state:state);super.init()
        panel.title="Text · 识别结果";panel.identifier=NSUserInterfaceItemIdentifier("TextResults");panel.appearance=NSAppearance(named:.darkAqua);panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=true;panel.hidesOnDeactivate=false;panel.isFloatingPanel=false;panel.isReleasedWhenClosed=false;panel.minSize=NSSize(width:240,height:180);panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary];panel.contentView=root;panel.delegate=self;root.controller=self
        outside=NSEvent.addGlobalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown]){[weak self] _ in Task{@MainActor in self?.autoHide()}}
        localOutside=NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown]){[weak self] event in if event.window !== self?.panel{self?.autoHide()};return event}
    }
    func autoHide(){guard state.prefs.autoHide,panel.isVisible,!root.menuOpen else{return};panel.orderOut(nil)}
    func show(){guard !state.busy else{panel.orderOut(nil);return};refresh();suppressResize=true
        let compact=state.message != nil || state.result.source.isEmpty
        let size=compact ? NSSize(width:270,height:203):NSSize(width:state.prefs.showImage ? state.prefs.previewWidth:state.prefs.width,height:state.prefs.showImage ? state.prefs.previewHeight:state.prefs.height)
        let a=anchor?() ?? NSRect(x:NSScreen.main?.visibleFrame.midX ?? 500,y:NSScreen.main?.visibleFrame.maxY ?? 800,width:30,height:24)
        let screen=NSScreen.screens.first{$0.frame.intersects(a)} ?? NSScreen.main!
        let w=min(size.width,screen.visibleFrame.width-16),h=min(size.height,screen.visibleFrame.height-16)
        let x=max(screen.visibleFrame.minX+8,min(a.midX-w/2,screen.visibleFrame.maxX-w-8)),y=max(screen.visibleFrame.minY+8,a.minY-h-8)
        panel.setFrame(NSRect(x:x,y:y,width:w,height:h),display:true);suppressResize=false;NSApp.activate(ignoringOtherApps:true);panel.makeKeyAndOrderFront(nil)
    }
    func refresh(){if state.busy{panel.orderOut(nil);return};panel.level=state.prefs.onTop ? .floating:.normal;root.refresh();if panel.isVisible,root.wasCompact != (state.message != nil || state.result.source.isEmpty){show()}}
    func windowDidResize(_ notification:Notification){guard !suppressResize,state.message==nil,!state.result.source.isEmpty else{return};let s=panel.frame.size;if state.prefs.showImage{state.prefs.previewWidth=s.width;state.prefs.previewHeight=s.height}else{state.prefs.width=s.width;state.prefs.height=s.height};state.savePreferences()}
    func togglePreview(){state.prefs.showImage.toggle();state.savePreferences();show()}
}
final class CompactLanguagePicker:NSPopUpButton {
    var trackingChanged:((Bool)->Void)?
    static func menuName(_ code:String)->String {switch code{case "zh-CN":return "中文";case "zh-TW":return "中文（繁体）";case "wyw":return "中文（文言文）";case "yue":return "中文（粤语）";default:return Languages.name(code)}}
    static func menuOrder(_ codes:[String])->[String]{
        let common=["en","zh-CN","ko"].filter{codes.contains($0)},locale=Locale(identifier:"zh_Hans")
        return common+codes.filter{!common.contains($0)}.sorted{menuName($0).compare(menuName($1),options:.numeric,range:nil,locale:locale) == .orderedAscending}
    }
    func configure(_ supported:[String],selected:String){
        let ordered=Self.menuOrder(supported)
        if itemArray.compactMap({$0.representedObject as? String}) != ordered {
            let list=NSMenu();list.autoenablesItems=false;list.appearance=NSAppearance(named:.darkAqua);list.minimumWidth=120;list.font=NSFont.systemFont(ofSize:13,weight:.medium)
            let commonCount=["en","zh-CN","ko"].filter{supported.contains($0)}.count
            for (index,code) in ordered.enumerated(){
                if index==commonCount && commonCount>0{list.addItem(.separator())}
                let item=NSMenuItem(title:Self.menuName(code),action:#selector(pickMenuItem(_:)),keyEquivalent:"");item.target=self;item.representedObject=code
                let paragraph=NSMutableParagraphStyle();paragraph.minimumLineHeight=18;paragraph.maximumLineHeight=18
                item.attributedTitle=NSAttributedString(string:item.title,attributes:[.font:NSFont.systemFont(ofSize:13,weight:.medium),.paragraphStyle:paragraph]);list.addItem(item)
            };menu=list
        }
        if let item=itemArray.first(where:{$0.representedObject as? String==selected}){select(item)}
        for item in itemArray where !item.isSeparatorItem{item.state=item === selectedItem ? .on:.off}
    }
    override func mouseDown(with event:NSEvent){
        guard isEnabled,let list=menu else{return};trackingChanged?(true);defer{trackingChanged?(false)}
        for item in itemArray where !item.isSeparatorItem{item.target=self;item.action=#selector(pickMenuItem(_:));item.state=item === selectedItem ? .on:.off}
        list.popUp(positioning:selectedItem,at:NSPoint(x:0,y:bounds.midY+8),in:self)
    }
    @objc func pickMenuItem(_ item:NSMenuItem){select(item);for other in itemArray where !other.isSeparatorItem{other.state=other === item ? .on:.off};needsDisplay=true;sendAction(action,to:target)}
    override func draw(_ dirtyRect:NSRect){
        let text=(selectedItem?.representedObject as? String).map{Languages.name($0)} ?? titleOfSelectedItem ?? "",font=NSFont.systemFont(ofSize:13,weight:.medium),color=isEnabled ? textWhite:NSColor.disabledControlTextColor
        let attrs:[NSAttributedString.Key:Any]=[.font:font,.foregroundColor:color],size=(text as NSString).size(withAttributes:attrs)
        let x=(bounds.width-size.width-12)/2,y=(bounds.height-size.height)/2
        (text as NSString).draw(at:NSPoint(x:x,y:y),withAttributes:attrs)
        color.setStroke();let p=NSBezierPath();p.lineWidth=1.4;p.lineCapStyle = .round;p.lineJoinStyle = .round
        let ax=x+size.width+5,mid=bounds.midY
        p.move(to:NSPoint(x:ax,y:mid+2));p.line(to:NSPoint(x:ax+3,y:mid+5));p.line(to:NSPoint(x:ax+6,y:mid+2))
        p.move(to:NSPoint(x:ax,y:mid-2));p.line(to:NSPoint(x:ax+3,y:mid-5));p.line(to:NSPoint(x:ax+6,y:mid-2));p.stroke()
    }
}
@MainActor enum ResultArtwork {
    static func translate()->NSImage {
        let image=NSImage(size:NSSize(width:21,height:21),flipped:false){_ in
            ("文" as NSString).draw(at:NSPoint(x:0,y:0),withAttributes:[.font:NSFont.systemFont(ofSize:17,weight:.regular),.strokeWidth:2,.strokeColor:NSColor.black,.foregroundColor:NSColor.clear])
            ("A" as NSString).draw(at:NSPoint(x:13,y:0),withAttributes:[.font:NSFont.systemFont(ofSize:9,weight:.regular),.foregroundColor:NSColor.black]);return true
        };image.isTemplate=true;return image
    }
    static func swap()->NSImage {
        let image=NSImage(size:NSSize(width:26,height:22),flipped:false){_ in
            NSColor.black.setStroke();let p=NSBezierPath();p.lineWidth=0.65;p.lineJoinStyle = .round
            for points in [[NSPoint(x:8,y:19),NSPoint(x:19,y:19),NSPoint(x:21,y:17),NSPoint(x:21,y:9),NSPoint(x:25,y:9),NSPoint(x:19,y:3),NSPoint(x:13,y:9),NSPoint(x:17,y:9),NSPoint(x:17,y:15),NSPoint(x:8,y:15)],[NSPoint(x:18,y:3),NSPoint(x:7,y:3),NSPoint(x:5,y:5),NSPoint(x:5,y:13),NSPoint(x:1,y:13),NSPoint(x:7,y:19),NSPoint(x:13,y:13),NSPoint(x:9,y:13),NSPoint(x:9,y:7),NSPoint(x:18,y:7)]]{p.move(to:points[0]);for point in points.dropFirst(){p.line(to:point)}};p.stroke();return true
        };image.isTemplate=true;return image
    }
}
@MainActor final class ResultContent:NSView,NSTextViewDelegate,NSMenuDelegate {
    let state:TextState
    weak var controller:ResultsController?
    let original=NSTextView(),translated=NSTextView(),originalScroll=NSScrollView(),translatedScroll=NSScrollView(),previewView=NSImageView()
    let vertical=NSBox(),horizontal=NSBox(),messageLabel=label("尚无识别结果",size:17,bold:true),hint=label("",size:11)
    let translateButton=NSButton(),swapButton=NSButton(),moreButton=NSButton(),previous=NSButton(),next=NSButton(),pageLabel=label("",size:11)
    let language=CompactLanguagePicker()
    var menuOpen=false,wasCompact=true,rendering=false
    override var isFlipped:Bool{true}
    init(state:TextState){self.state=state;super.init(frame:.zero);wantsLayer=true;layer?.backgroundColor=panelGray.cgColor;layer?.cornerRadius=14;layer?.borderWidth=1;layer?.borderColor=NSColor.white.withAlphaComponent(0.38).cgColor;layer?.masksToBounds=true
        for (view,scroll) in [(original,originalScroll),(translated,translatedScroll)]{view.isRichText=false;view.isEditable=true;view.isSelectable=true;view.allowsUndo=true;view.drawsBackground=false;view.textColor=textWhite;view.insertionPointColor = .systemBlue;view.font=NSFont.systemFont(ofSize:16,weight:.medium);view.textContainerInset=NSSize(width:0,height:2);view.textContainer?.lineFragmentPadding=0;let paragraph=NSMutableParagraphStyle();paragraph.lineSpacing=4;view.defaultParagraphStyle=paragraph;view.typingAttributes=[.font:NSFont.systemFont(ofSize:13,weight:.medium),.foregroundColor:textWhite,.paragraphStyle:paragraph];view.isAutomaticQuoteSubstitutionEnabled=false;view.isAutomaticDashSubstitutionEnabled=false;view.isAutomaticSpellingCorrectionEnabled=false;view.delegate=self;view.isVerticallyResizable=true;view.isHorizontallyResizable=false;view.autoresizingMask=[.width];view.textContainer?.widthTracksTextView=true;scroll.documentView=view;scroll.hasVerticalScroller=true;scroll.drawsBackground=false;scroll.borderType = .noBorder;scroll.autohidesScrollers=true;addSubview(scroll)}
        original.setAccessibilityLabel("识别原文，可编辑");translated.setAccessibilityLabel("翻译译文，可编辑")
        for line in [vertical,horizontal]{line.boxType = .separator;addSubview(line)}
        previewView.imageScaling = .scaleProportionallyUpOrDown;previewView.imageAlignment = .alignTop;previewView.setAccessibilityLabel("原图预览");addSubview(previewView)
        messageLabel.alignment = .center;addSubview(messageLabel);hint.textColor=NSColor(calibratedWhite:0.84,alpha:1);hint.alignment = .center;addSubview(hint)
        setup(translateButton,"翻译或重新翻译",#selector(translateNow));translateButton.image=ResultArtwork.translate();translateButton.contentTintColor=NSColor(calibratedWhite:0.8,alpha:1)
        setup(swapButton,"交换原文和译文",#selector(swap));swapButton.image=ResultArtwork.swap();swapButton.contentTintColor=NSColor(calibratedWhite:0.8,alpha:1)
        setup(moreButton,"更多结果功能",#selector(more));moreButton.image=NSImage(size:NSSize(width:16,height:29),flipped:false){r in textWhite.setStroke();for y in [5,14,23]{let p=NSBezierPath(ovalIn:NSRect(x:5,y:y-3,width:6,height:6));p.lineWidth=0.8;p.stroke()};return true}
        setup(previous,"上一页原图",#selector(previousPage));previous.title="‹";setup(next,"下一页原图",#selector(nextPage));next.title="›";addSubview(pageLabel)
        language.isBordered=false;language.font=NSFont.systemFont(ofSize:15,weight:.semibold);language.contentTintColor=textWhite;language.target=self;language.action=#selector(targetChanged);language.setAccessibilityLabel("翻译目标语言");language.trackingChanged={[weak self] in self?.menuOpen=$0};addSubview(language)
        refresh()
    }
    override func draw(_ dirtyRect:NSRect){NSGradient(starting:NSColor(srgbRed:0.33,green:0.34,blue:0.34,alpha:1),ending:NSColor(srgbRed:0.24,green:0.25,blue:0.25,alpha:1))?.draw(in:bounds,angle:90)}
    required init?(coder:NSCoder){fatalError()}
    func setup(_ b:NSButton,_ title:String,_ action:Selector){b.isBordered=false;b.target=self;b.action=action;b.contentTintColor=textWhite;b.imageScaling = .scaleProportionallyUpOrDown;b.toolTip=title;b.setAccessibilityLabel(title);addSubview(b)}
    func refresh(){rendering=true;defer{rendering=false};wasCompact=state.message != nil || state.result.source.isEmpty
        if original.string != state.result.source{original.string=state.result.source};if translated.string != state.result.translation{translated.string=state.result.translation}
        messageLabel.stringValue=state.message ?? "尚无识别结果"
        hint.stringValue=state.translating ? "正在翻译…":state.detail
        previewView.image=state.preview
        let codes=state.prefs.translationEngine=="baidu" ? Languages.codes.filter{Languages.baidu[$0] != nil}+["yue","wyw"]:Languages.codes
        language.configure(codes,selected:state.prefs.target)
        swapButton.isEnabled = !state.translating && !state.result.translation.isEmpty;translateButton.isEnabled = !state.busy && !state.translating;language.isEnabled = !state.busy
        pageLabel.stringValue="\(state.previewIndex+1) / \(state.previewPages.count)";previous.isEnabled=state.previewIndex>0;next.isEnabled=state.previewIndex+1<state.previewPages.count
        needsLayout=true
    }
    override func layout(){super.layout();let compact=state.message != nil || state.result.source.isEmpty
        for v in subviews{v.isHidden=compact};messageLabel.isHidden = !compact
        if compact{messageLabel.frame=NSRect(x:16,y:bounds.height/2-12,width:bounds.width-32,height:28);return}
        let show=state.prefs.showImage,left=show ? bounds.width/2:0,right=NSRect(x:left+13,y:10,width:bounds.width-left-26,height:bounds.height-52)
        previewView.isHidden = !show;vertical.isHidden = !show
        let imageInset=max(CGFloat(12),left*0.10);previewView.frame=NSRect(x:imageInset,y:10,width:max(1,left-2*imageInset),height:bounds.height-46);vertical.frame=NSRect(x:left-1,y:0,width:1,height:bounds.height)
        let paged=show && state.previewPages.count>1
        for v in [previous,next,pageLabel]{v.isHidden = !paged}
        previous.frame=NSRect(x:left/2-60,y:bounds.height-39,width:22,height:24);pageLabel.frame=NSRect(x:left/2-30,y:bounds.height-34,width:60,height:18);pageLabel.alignment = .center;next.frame=NSRect(x:left/2+37,y:bounds.height-39,width:22,height:24)
        let translate=state.prefs.translationEnabled
        translatedScroll.isHidden = !translate;horizontal.isHidden = !translate;language.isHidden = !translate
        let hasHint = !state.detail.isEmpty || state.translating,contentBottom=translate ? bounds.height-67:bounds.height-37
        let height=max(30,contentBottom-right.minY-(hasHint ? 26:0))
        if translate{originalScroll.frame=NSRect(x:right.minX,y:right.minY,width:right.width,height:height/2-8);horizontal.frame=NSRect(x:right.minX,y:right.minY+height/2,width:right.width,height:1);translatedScroll.frame=NSRect(x:right.minX,y:right.minY+height/2+8,width:right.width,height:height/2-8)}else{originalScroll.frame=NSRect(x:right.minX,y:right.minY,width:right.width,height:height)}
        hint.isHidden = !hasHint;hint.frame=NSRect(x:right.minX,y:contentBottom-23,width:right.width,height:27)
        let controlsY=bounds.height-27;translateButton.frame=NSRect(x:left+10,y:controlsY,width:21,height:21);swapButton.frame=NSRect(x:left+(bounds.width-left)/2-11,y:controlsY,width:23,height:19);moreButton.frame=NSRect(x:bounds.width-22,y:controlsY-1,width:12,height:23)
        let languageWidth=min(max(1,bounds.width-left-24),max(100,(Languages.name(state.prefs.target) as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:12,weight:.medium)]).width+50));language.frame=NSRect(x:left+(bounds.width-left-languageWidth)/2,y:bounds.height-55,width:languageWidth,height:24)
        for scroll in [originalScroll,translatedScroll]{let width=scroll.contentSize.width;scroll.documentView?.setFrameSize(NSSize(width:width,height:max(30,scroll.documentView?.frame.height ?? 30)));(scroll.documentView as? NSTextView)?.textContainer?.containerSize=NSSize(width:width,height:CGFloat.greatestFiniteMagnitude)}
    }
    func textDidChange(_ notification:Notification){guard !rendering else{return};if notification.object as? NSTextView === original{state.editedSource(original.string)}else{state.editedTranslation(translated.string)}}
    @objc func translateNow(){state.translate()}
    @objc func swap(){state.swap()}
    @objc func targetChanged(){if let code=language.selectedItem?.representedObject as? String{state.selectTarget(code)}}
    @objc func previousPage(){state.movePreview(-1)}
    @objc func nextPage(){state.movePreview(1)}
    @objc func more(){let menu=NSMenu();menu.delegate=self;menu.autoenablesItems=false
        for (title,key,selector,checked) in [("显示图片","i",#selector(toggleImage),state.prefs.showImage),("自动隐藏","h",#selector(toggleHide),state.prefs.autoHide),("自动格式化","",#selector(toggleFormat),state.prefs.autoFormat),("总在最前","p",#selector(toggleTop),state.prefs.onTop)]{let item=NSMenuItem(title:title,action:selector,keyEquivalent:key);item.keyEquivalentModifierMask = .command;item.target=self;item.state=checked ? .on:.off;menu.addItem(item)}
        menuOpen=true;menu.popUp(positioning:nil,at:NSPoint(x:0,y:moreButton.bounds.height+3),in:moreButton);menuOpen=false
    }
    func menuWillOpen(_ menu:NSMenu){menuOpen=true}
    func menuDidClose(_ menu:NSMenu){menuOpen=false}
    @objc func toggleImage(){controller?.togglePreview()}
    @objc func toggleHide(){state.toggle(\Preferences.autoHide)}
    @objc func toggleFormat(){state.toggle(\Preferences.autoFormat)}
    @objc func toggleTop(){state.toggle(\Preferences.onTop)}
    override func performKeyEquivalent(with event:NSEvent)->Bool {if event.modifierFlags.intersection([.command,.option,.control,.shift]) == .command{switch event.charactersIgnoringModifiers?.lowercased(){case "i":toggleImage();return true;case "h":toggleHide();return true;case "p":toggleTop();return true;default:break}};return super.performKeyEquivalent(with:event)}
    override func mouseDown(with event:NSEvent){guard let window else{return};let start=convert(event.locationInWindow,from:nil),frame=window.frame,edge:CGFloat=9
        let left=start.x<edge,right=start.x>bounds.width-edge,top=start.y<edge,bottom=start.y>bounds.height-edge
        if !(left||right||top||bottom){window.performDrag(with:event);return}
        let screenStart=NSEvent.mouseLocation
        while let next=window.nextEvent(matching:[.leftMouseDragged,.leftMouseUp]){if next.type == .leftMouseUp{break};let mouse=NSEvent.mouseLocation,dx=mouse.x-screenStart.x,dy=mouse.y-screenStart.y;var f=frame
            if right{f.size.width=max(window.minSize.width,frame.width+dx)};if bottom{f.size.height=max(window.minSize.height,frame.height-dy);f.origin.y=frame.maxY-f.height};if left{f.size.width=max(window.minSize.width,frame.width-dx);f.origin.x=frame.maxX-f.width};if top{f.size.height=max(window.minSize.height,frame.height+dy)};window.setFrame(f,display:true)
        }
    }
    override func hitTest(_ point:NSPoint)->NSView?{let p=convert(point,from:superview);if p.x<8 || p.x>bounds.width-8 || p.y<8 || p.y>bounds.height-8{return self};return super.hitTest(point)}
}
