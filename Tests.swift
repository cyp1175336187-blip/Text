import AppKit
import ImageIO

final class FixtureProtocol:URLProtocol {
    static var replies:[Data]=[],requests:[URLRequest]=[]
    override class func canInit(with request:URLRequest)->Bool{true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest{request}
    override func startLoading(){Self.requests.append(request);guard !Self.replies.isEmpty else{client?.urlProtocol(self,didFailWithError:TextError(message:"没有测试响应"));return};let data=Self.replies.removeFirst();let response=HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!;client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed);client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)}
    override func stopLoading(){}
}
@MainActor enum SelfTests {
    static func render(_ root:URL)throws {
        let app=NSApplication.shared;app.appearance=NSAppearance(named:.darkAqua)
        let output=root.appendingPathComponent("原生界面预览",isDirectory:true);try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let state=TextState(disk:try DiskStore(root:root.appendingPathComponent("preview-state")),loadKeys:false)
        let doc=NSImage(size:NSSize(width:640,height:390));doc.lockFocus();NSColor.white.setFill();NSRect(x:0,y:0,width:640,height:390).fill();("The art of\nslowing down." as NSString).draw(in:NSRect(x:30,y:40,width:580,height:310),withAttributes:[.font:NSFont(name:"Georgia-Bold",size:62) ?? NSFont.boldSystemFont(ofSize:62),.foregroundColor:NSColor(calibratedRed:0.19,green:0.23,blue:0.17,alpha:1)]);doc.unlockFocus();state.preview=doc
        state.result=LastResult(source:"The art of slowing down.\n\nTake a walk without a destination.\nNotice the light through the trees.",translation:"慢下来的艺术。\n\n漫无目的地散散步。\n留意穿过树梢的光。",sourceLanguage:"en",target:"zh-CN",name:"界面验证示例")
        func save(_ view:NSView,_ name:String)throws {view.layoutSubtreeIfNeeded();view.displayIfNeeded();guard let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds) else{throw TextError(message:"视图无法渲染")};view.cacheDisplay(in:view.bounds,to:rep);guard let png=rep.representation(using:.png,properties:[:]) else{throw TextError(message:"视图 PNG 无法编码")};try png.write(to:output.appendingPathComponent(name+".png"));print(name)}
        let result=ResultContent(state:state);result.frame=NSRect(x:0,y:0,width:270,height:203);result.refresh();try save(result,"01-仅原文")
        state.prefs.translationEnabled=true;result.refresh();try save(result,"02-原文与译文")
        state.prefs.showImage=true;result.frame=NSRect(x:0,y:0,width:270,height:203);result.refresh();try save(result,"03-原图对照")
        state.message="尚未配置服务";result.frame=NSRect(x:0,y:0,width:270,height:203);result.refresh();try save(result,"04-未配置提示")
        let preferences=PreferencesController(state:state)
        for (id,name) in [("general","05-通用"),("account","06-账户"),("shortcuts","07-快捷键")]{preferences.select(id);let view=preferences.window.contentView?.superview ?? preferences.host;try save(view,name)}
        for (kind,name) in [("使用教程","08-使用教程"),("意见反馈","09-意见反馈")]{let w=GuideWindow.shared.makeWindow(kind:kind);try save(w.contentView?.superview ?? w.contentView!,name)}
        for (page,width,height,name) in [("account",240,180,"10-账户最小窗口"),("account",520,430,"11-账户放大窗口"),("shortcuts",240,180,"12-快捷键最小窗口"),("general",520,430,"13-通用放大窗口")]{preferences.select(page);preferences.window.setContentSize(NSSize(width:width,height:height));preferences.layoutWindow();try save(preferences.window.contentView?.superview ?? preferences.host,name)}
        state.message=nil;state.detail="";state.prefs.showImage=false;state.prefs.translationEnabled=false;state.result.source="开发者中心\n开发者信息\nAPI Key 管理\n财务中心\n财务总览\n我的发票\n开票信息管理";result.frame=NSRect(x:0,y:0,width:270,height:203);result.refresh();try save(result,"14-参考样式对照")
        let disc=NSImageView(frame:NSRect(x:0,y:0,width:54,height:26));disc.wantsLayer=true;disc.layer?.backgroundColor=NSColor(srgbRed:0.29,green:0.55,blue:0.63,alpha:1).cgColor;disc.image=AppArtwork.recognitionDisc(progress:0.2);disc.contentTintColor = .white;disc.imageScaling = .scaleNone;try save(disc,"15-识别圆盘图标")
        for (progress,name) in [(0.0,"16-进度0"),(0.25,"17-进度25"),(0.5,"18-进度50"),(0.75,"19-进度75"),(1.0,"20-进度100")]{disc.image=AppArtwork.recognitionDisc(progress:progress);try save(disc,name)}
        disc.image=AppArtwork.menuMonogram();try save(disc,"21-菜单栏T")
        print("原生视图渲染完成，仅使用界面验证文字，不是云服务识别结果。")
    }
    static func run(_ root:URL)async->Int32 {
        var count=0
        func check(_ condition:@autoclosure()throws->Bool,_ name:String)throws{guard try condition() else{throw TextError(message:"测试失败："+name)};count+=1;print("通过："+name)}
        func reply(_ objects:[[String:Any]])throws{FixtureProtocol.replies=try objects.map{try JSONSerialization.data(withJSONObject:$0)};FixtureProtocol.requests=[]}
        do {
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            let disk=try DiskStore(root:root.appendingPathComponent("state")),state=TextState(disk:disk,loadKeys:false)
            try check(state.prefs.ocrEngine=="baidu" && state.prefs.translationEngine=="baidu","账户精简后默认使用百度识字与翻译")
            try check(state.prefs.autoHide && !state.prefs.onTop && !state.prefs.autoFormat,"默认窗口选项")
            try check(state.prefs.capture == .capture && state.prefs.results == .results,"默认全局快捷键")
            try check(Shortcut.capture.display=="⌘1" && Shortcut.results.display=="⇧⌘R","快捷键显示")
            state.recognize([root.appendingPathComponent("missing.png")]);try check(state.message=="尚未配置服务" && !state.busy,"未配置时不发起识别请求")
            state.result=LastResult(source:"Test original",translation:"测试译文",sourceLanguage:"en",target:"zh-CN",name:"测试图片")
            state.prefs.width=620;state.prefs.height=430;state.prefs.translationEnabled=true;state.savePreferences();state.saveResult()
            let restored=TextState(disk:disk,loadKeys:false);try check(restored.result.source=="Test original" && restored.result.translation=="测试译文","退出后恢复最近原文和译文")
            try check(restored.prefs.width==620 && restored.prefs.translationEnabled,"恢复窗口大小及翻译状态")
            restored.editedSource("Edited source");try check(restored.result.translation=="测试译文","修改原文保留译文，不自动翻译")
            restored.swap();try check(restored.result.source=="测试译文" && restored.result.translation=="Edited source" && restored.prefs.target=="en","交换原文译文与翻译方向")
            try check(Paragraphs.format("Hello\nworld\n\nAnother   line")=="Hello world\n\nAnother line","合并段内换行并保留段落")
            try check(Paragraphs.format("中文\n内容")=="中文内容","中文合并不插入空格")
            var usage=MonthUsage(month:MonthUsage.currentMonth,googleOCR:900);try check(!usage.allowed(engine:"google"),"达到本机保护上限后停止调用")
            usage.month="2000-01";usage.refresh();try check(usage.googleOCR==0,"按月重置用量")
            let oldWindowDisk=try DiskStore(root:root.appendingPathComponent("legacy-window"))
            var oldPreferences=Preferences();oldPreferences.uniformWindowSizeVersion=nil;oldPreferences.width=620;oldPreferences.height=430;oldPreferences.showImage=true;oldPreferences.freeGuard=false
            try oldWindowDisk.write(oldPreferences,name:"preferences.json");let migrated=TextState(disk:oldWindowDisk,loadKeys:false)
            try check(migrated.prefs.width==270 && migrated.prefs.height==203 && migrated.prefs.previewWidth==270 && migrated.prefs.previewHeight==203 && migrated.prefs.uniformWindowSizeVersion==3 && migrated.prefs.showImage && !migrated.prefs.freeGuard,"统一旧窗口尺寸并保留其他偏好")
            let legacyData=try JSONSerialization.data(withJSONObject:["month":MonthUsage.currentMonth,"googleOCR":2,"googleCharacters":11,"baiduOCR":5,"baiduCharacters":27])
            var legacy=try JSONDecoder().decode(MonthUsage.self,from:legacyData)
            try check(legacy.baiduOCR==5 && legacy.baiduCharacters==27 && legacy.googleOCR==2 && legacy.baiduTranslationCalls==0 && legacy.baiduTranslationPartial,"旧版用量迁移保留既有计数，标注新增次数统计范围")
            legacy.add(engine:"baidu",characters:9);try check(legacy.baiduTranslationCalls==1 && legacy.baiduCharacters==36,"翻译请求计次且保留字符用量保护")
            let supported=Languages.codes.filter{Languages.baidu[$0] != nil}+["yue","wyw"]
            let picker=CompactLanguagePicker();picker.configure(supported,selected:"en")
            try check(Array(picker.itemArray.compactMap{$0.representedObject as? String}.prefix(3))==["en","zh-CN","ko"] && picker.itemArray[3].isSeparatorItem,"语言菜单仅将英中韩置顶并分组")
            try check(Set(picker.itemArray.compactMap{$0.representedObject as? String})==Set(supported) && picker.selectedItem?.representedObject as? String=="en","语言菜单分组后仍保留全部语言和当前选择")
            picker.configure(supported,selected:"ja");try check(picker.selectedItem?.representedObject as? String=="ja" && picker.itemArray.filter{$0.state == .on}.count==1,"非置顶语言仍可选中且勾选唯一")
            let chunks=CloudAPI.chunks(String(repeating:"你好🙂",count:500),maxBytes:900);try check(chunks.allSatisfy{$0.utf8.count<=900} && chunks.joined()==String(repeating:"你好🙂",count:500),"中文与 emoji 安全分块")
            let image=AppArtwork.icon(style:0,size:200),tiff=image.tiffRepresentation!,cg=try Imaging.cgImage(tiff),jpeg=try Imaging.jpeg(cg)
            try check(try Imaging.cgImage(jpeg).width>0,"图片归一化与 JPEG 编码")
            let decoded=try Imaging.cgImage(jpeg),pixel=CGContext(data:nil,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            pixel.draw(decoded,in:CGRect(x:0,y:0,width:decoded.width,height:decoded.height));let bytes=pixel.data!.assumingMemoryBound(to:UInt8.self)
            try check(bytes[0]>235 && bytes[1]>235 && bytes[2]>235,"透明图片转白底，避免识字背景变黑")
            let formats=CGImageSourceCopyTypeIdentifiers() as! [String]
            try check(["public.png","public.jpeg","public.heic","org.webmproject.webp"].allSatisfy{formats.contains($0)},"当前系统具备 PNG、JPG、HEIC、WebP 解码器")

            let imageURL=root.appendingPathComponent("test.jpg");try jpeg.write(to:imageURL)
            let names=try disk.saveOriginals([imageURL]);try check(names.count==1 && FileManager.default.fileExists(atPath:disk.root.appendingPathComponent(names[0]).path),"原图缓存")
            let pdfURL=root.appendingPathComponent("two-pages.pdf");var rect=CGRect(x:0,y:0,width:500,height:600);let pdf=CGContext(consumer:CGDataConsumer(url:pdfURL as CFURL)!,mediaBox:&rect,nil)!
            for _ in 1...2{pdf.beginPDFPage(nil);pdf.draw(cg,in:CGRect(x:40,y:350,width:200,height:200));pdf.endPDFPage()};pdf.closePDF()
            let doc=CGPDFDocument(pdfURL as CFURL)!;try check(doc.numberOfPages==2,"读取多页 PDF")
            try check(try Imaging.render(doc.page(at:2)!).width>0,"扫描 PDF 第二页渲染")
            let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[FixtureProtocol.self];let api=CloudAPI(session:URLSession(configuration:config))
            let keys=Credentials(googleOCR:"fixture",googleTranslation:"fixture",baiduOCR:"fixture",baiduOCRSecret:"fixture",baiduAppID:"fixture",baiduTranslationSecret:"fixture")
            let stored=try SecretStore.decoded(SecretStore.encoded(keys))
            try check(stored.baiduOCR==keys.baiduOCR && stored.baiduTranslationSecret==keys.baiduTranslationSecret && stored.googleOCR==keys.googleOCR,"专用凭据记录完整往返编码")
            do{_ = try SecretStore.decoded(JSONEncoder().encode(SecretStore.Record(version:99,credentials:keys)));throw TextError(message:"格式版本未检查")}catch{try check(error.localizedDescription=="不支持的凭据记录格式","拒绝未知版本且不覆盖凭据")}
            try check(SecretStore.pendingChanges(keys,previous:keys).isEmpty,"未修改密钥时不重复访问钥匙串保存")
            var changedKeys=keys;changedKeys.baiduTranslationSecret="changed"
            let pending=SecretStore.pendingChanges(changedKeys,previous:keys)
            try check(pending.count==1 && pending.first?.0=="baiduTranslationSecret","只更新发生变化的密钥条目")
            state.keys=keys;let account=PreferencesController(state:state);account.select("account")
            for (field,value) in zip(account.fields,["ocr-new","ocr-secret-new","app-id-new","translation-secret-new"]){field.stringValue=value}
            let edited=account.editedKeys()
            try check(edited?.baiduOCR=="ocr-new" && edited?.baiduOCRSecret=="ocr-secret-new" && edited?.baiduAppID=="app-id-new" && edited?.baiduTranslationSecret=="translation-secret-new" && edited?.googleOCR==keys.googleOCR && edited?.googleTranslation==keys.googleTranslation,"四项百度凭据映射正确且保留隐藏配置")
            let draft=account.fields.map{$0.stringValue}
            account.window.setContentSize(NSSize(width:240,height:180));account.layoutWindow()
            let narrowWidth=account.fields[0].frame.width
            account.window.setContentSize(NSSize(width:520,height:430));account.layoutWindow()
            try check(account.fields.map{$0.stringValue}==draft && account.fields[0].frame.width>narrowWidth && account.bodyScroll.hasVerticalScroller,"拉伸设置窗口保留未保存密钥并自适应字段宽度")
            let resizedSize=account.window.contentView!.bounds.size;account.select("shortcuts");account.select("account")
            try check(account.window.contentView!.bounds.size==resizedSize && account.window.styleMask.contains(.resizable),"切换设置页保留已调整尺寸且支持拉伸")
            try reply([["responses":[["fullTextAnnotation":["text":"Recognized text"]]]]])
            let recognized=try await api.recognize(jpeg,engine:"google",keys:keys);try check(recognized=="Recognized text","Google OCR 响应解析（隔离测试）")
            try check(FixtureProtocol.requests.first?.url?.host=="vision.googleapis.com","Google OCR 官方端点")
            try reply([["data":["translations":[["translatedText":"翻译文字","detectedSourceLanguage":"en"]]]]])
            let translated=try await api.translate("hello",target:"zh-CN",engine:"google",keys:keys);try check(translated.text=="翻译文字" && translated.language=="en","Google 翻译与语言检测解析（隔离测试）")
            try reply([["access_token":"fixture-token"],["words_result":[["words":"第一段"],["words":"第二段"]],"paragraphs_result":[["words_result_idx":[0]],["words_result_idx":[1]]]]])
            let baidu=try await api.recognize(jpeg,engine:"baidu",keys:keys);try check(baidu=="第一段\n\n第二段","百度授权、OCR 与段落解析（隔离测试）")
            try check(FixtureProtocol.requests.count==2 && FixtureProtocol.requests.last?.url?.host=="aip.baidubce.com" && FixtureProtocol.requests.last?.url?.path=="/rest/2.0/ocr/v1/general_basic","百度 OCR 使用通用文字识别标准版接口")
            try reply([["from":"en","to":"zh","trans_result":[["dst":"你好"]]]])
            let bt=try await api.translate("hello",target:"zh-CN",engine:"baidu",keys:keys);try check(bt.text=="你好","百度签名翻译响应解析（隔离测试）")
            try reply([["error":["message":"invalid key"]]])
            do{_ = try await api.recognize(jpeg,engine:"google",keys:keys);throw TextError(message:"未拒绝错误响应")}catch{try check(error.localizedDescription=="invalid key","云服务错误不会伪造识别结果")}
            try check(Languages.codes.count>100,"Google 超过 100 种目标语言")
            state.keys=keys;state.api=api;state.prefs.translationEnabled=false;state.prefs.ocrEngine="google";state.prefs.autoFormat=false
            try reply([["responses":[["fullTextAnnotation":["text":"Page one"]]]] ,["responses":[["fullTextAnnotation":["text":"Page two"]]]]])
            let panel=ResultsController(state:state)
            var samples:[Double]=[];state.onChange={samples.append(state.recognitionProgress)}
            var earlyShows=0;state.onShow={if state.busy{earlyShows+=1}}
            state.recognize([pdfURL]);panel.show()
            try check(state.busy && state.message==nil && !panel.panel.isVisible,"识别时不显示文字提示或结果面板")
            for _ in 0..<300{if !state.busy{break};try await Task.sleep(nanoseconds:10_000_000)}
            try check(!state.busy && state.result.source=="Page one\n\nPage two","整份 PDF 顺序识别并替换上一次内容")
            try check(samples.first==0 && samples.last==1 && zip(samples,samples.dropFirst()).allSatisfy{$0 <= $1},"识别进度从零单调推进并在保存成功后完成")
            try check(earlyShows==0,"识别过程不触发结果窗口显示")
            try check(state.previewPages.count==2 && state.usage.googleOCR==2,"PDF 每页计量并保留可翻页原图")
            let again=TextState(disk:disk,loadKeys:false);try check(again.result.source=="Page one\n\nPage two" && again.previewPages.count==2,"重启后恢复 PDF 原图与最近结果")

            print("全部 \(count) 项测试通过。网络响应使用 URLProtocol 隔离，未调用付费服务。")
            return 0
        }catch{print(error.localizedDescription);return 1}
    }
}
