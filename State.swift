import AppKit
import NaturalLanguage

@MainActor final class TextState {
    let disk:DiskStore
    var prefs:Preferences
    var result:LastResult
    var usage:MonthUsage
    var keys:Credentials
    var api=CloudAPI()
    var busy=false,translating=false
    private(set) var recognitionProgress:Double=0
    func advanceRecognition(_ value:Double){recognitionProgress=max(recognitionProgress,min(1,max(0,value)));changed()}
    var message:String?,detail="",connected:Set<String>=[]
    var preview:NSImage?,previewIndex=0,previewPages:[(URL,Int)]=[]
    var onChange:(()->Void)?,onShow:(()->Void)?,onSettings:(()->Void)?
    private var job:Task<Void,Never>?,translationJob:Task<Void,Never>?,saveJob:Task<Void,Never>?
    private var generation=UUID()
    init(disk:DiskStore,loadKeys:Bool=true) {
        self.disk=disk;prefs=disk.read("preferences.json",as:Preferences.self) ?? Preferences();result=disk.read("last-result.json",as:LastResult.self) ?? LastResult();usage=disk.read("usage.json",as:MonthUsage.self) ?? MonthUsage();usage.refresh();keys=loadKeys ? SecretStore.load():Credentials()
        prefs.ocrEngine="baidu";prefs.translationEngine="baidu"
        if prefs.translationEngine=="baidu",Languages.baidu[prefs.target]==nil{prefs.target="zh-CN"}
        if prefs.uniformWindowSizeVersion != 3{prefs.width=270;prefs.height=203;prefs.previewWidth=270;prefs.previewHeight=203;prefs.uniformWindowSizeVersion=3;try? disk.write(prefs,name:"preferences.json")}
        restorePreview()
    }
    func changed(){onChange?()}
    func savePreferences(){do{try disk.write(prefs,name:"preferences.json")}catch{detail="设置保存失败：\(error.localizedDescription)"};changed()}
    func saveResult(){do{try disk.write(result,name:"last-result.json")}catch{detail="最近结果保存失败：\(error.localizedDescription)"};changed()}
    func saveUsage()throws{try disk.write(usage,name:"usage.json");changed()}
    func status(_ message:String,detail:String=""){self.message=message;self.detail=detail;changed();onShow?()}
    func closeMessage(){message=nil;changed()}
    func editedSource(_ text:String){generation=UUID();translationJob?.cancel();translating=false;result.source=text;debounceSave()}
    func editedTranslation(_ text:String){generation=UUID();translationJob?.cancel();translating=false;result.translation=text;debounceSave()}
    private func debounceSave(){saveJob?.cancel();saveJob=Task{try? await Task.sleep(nanoseconds:300_000_000);if !Task.isCancelled{saveResult()}}}
    @discardableResult func saveKeys(_ keys:Credentials)->Bool{do{try SecretStore.saveAll(keys,previous:self.keys);self.keys=keys;connected=[];detail="配置已保存到 macOS 钥匙串";changed();return true}catch{detail=error.localizedDescription;changed();return false}}
    func toggle(_ key:WritableKeyPath<Preferences,Bool>){prefs[keyPath:key].toggle();if key == \Preferences.autoFormat,prefs.autoFormat{result.source=Paragraphs.format(result.source);saveResult()};savePreferences()}
    func swap(){guard !translating,!result.translation.isEmpty else{return};generation=UUID();let old=result.source;result.source=result.translation;result.translation=old;let target=result.sourceLanguage == "auto" ? detect(old):result.sourceLanguage;result.sourceLanguage=prefs.target;prefs.target=Languages.codes.contains(target) ? target:"en";result.target=prefs.target;savePreferences();saveResult()}
    func selectTarget(_ code:String){prefs.target=code;savePreferences();if prefs.translationEnabled,!result.source.isEmpty{translate()}}
    func detect(_ text:String)->String {let recognizer=NLLanguageRecognizer();recognizer.processString(text);let code=recognizer.dominantLanguage?.rawValue ?? "en";return code=="zh-Hans" ? "zh-CN":code=="zh-Hant" ? "zh-TW":code}
    func chooseFiles(){guard !busy else{return};let panel=NSOpenPanel();panel.allowedContentTypes=[.image,.pdf];panel.allowsMultipleSelection=true;panel.canChooseDirectories=false;panel.title="选择图片文件或 PDF";panel.prompt="识别";NSApp.activate(ignoringOtherApps:true);panel.begin{[weak self] response in if response == .OK{self?.recognize(panel.urls)}}}
    func capture(){guard !busy else{return};if !CGPreflightScreenCaptureAccess(),!CGRequestScreenCaptureAccess(){status("需要截图权限",detail:"请在系统设置 → 隐私与安全性 → 屏幕与系统音频录制中允许 Text，然后退出并重新打开。按 Esc 可取消截图。");return}
        onChange?();NSApp.windows.filter{$0 is ResultsPanel}.forEach{$0.orderOut(nil)}
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("text-capture-"+UUID().uuidString,isDirectory:true);try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);let file=folder.appendingPathComponent("截图.png")
        DispatchQueue.main.asyncAfter(deadline:.now()+0.2){[weak self] in
            let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/sbin/screencapture");process.arguments=["-i","-x",file.path];process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice
            process.terminationHandler={_ in Task{@MainActor [weak self] in guard let self else{return};if FileManager.default.fileExists(atPath:file.path){self.recognize([file],removeAfter:folder)}else{try? FileManager.default.removeItem(at:folder)}}}
            do{try process.run()}catch{try? FileManager.default.removeItem(at:folder);self?.status("截图失败",detail:error.localizedDescription)}
        }
    }
    func recognize(_ urls:[URL],removeAfter:URL?=nil){
        guard !busy else{return}
        guard keys.readyOCR(prefs.ocrEngine) else{if let removeAfter{try? FileManager.default.removeItem(at:removeAfter)};status("尚未配置服务",detail:"请在“更多 → 偏好设置 → 账户”中配置 \(prefs.ocrEngine=="google" ? "Google":"百度") 识字服务。");return}
        guard !urls.isEmpty,urls.count<=20 else{status("文件数量过多",detail:"每次最多选择 20 个文件");return}
        generation=UUID();translationJob?.cancel();translating=false;busy=true;recognitionProgress=0;let engine=prefs.ocrEngine,keys=keys
        message=nil;detail="";changed()
        job=Task{
            defer{busy=false;if let removeAfter{try? FileManager.default.removeItem(at:removeAfter)};changed()}
            do{
                var pages:[(URL,Int)]=[]
                for url in urls {let info=try url.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey]);guard info.isRegularFile==true,(info.fileSize ?? 0)<=50*1024*1024 else{throw TextError(message:"单个文件不能超过 50 MB")}
                    if url.pathExtension.lowercased()=="pdf"{guard let doc=CGPDFDocument(url as CFURL),!doc.isEncrypted || doc.isUnlocked,doc.numberOfPages>0 else{throw TextError(message:"PDF 无法打开或尚未解锁")};guard doc.numberOfPages<=100 else{throw TextError(message:"单个 PDF 最多 100 页，请拆分后重试")};for n in 1...doc.numberOfPages{pages.append((url,n))}}
                    else{pages.append((url,0))}
                }
                advanceRecognition(0.03)
                var textParts:[String]=[],first:CGImage?
                for (index,page) in pages.enumerated(){try Task.checkCancellation()
                    let image=try await Task.detached(priority:.userInitiated){try Self.imageFor(page)}.value
                    if first==nil{first=image};let data=try Imaging.jpeg(image)
                    advanceRecognition(0.03+0.87*(Double(index)+0.2)/Double(pages.count))
                    usage.refresh();if prefs.freeGuard && !usage.allowed(engine:engine){throw TextError(message:"本月预设免费用量已达上限")};usage.add(engine:engine);try saveUsage()
                    let text=try await api.recognize(data,engine:engine,keys:keys);try Task.checkCancellation();connected.insert("ocr-"+engine);if !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty{textParts.append(text.trimmingCharacters(in:.whitespacesAndNewlines))};advanceRecognition(0.03+0.87*Double(index+1)/Double(pages.count))
                }
                guard !textParts.isEmpty else{throw TextError(message:"图片中没有检测到文字")}
                advanceRecognition(0.94)
                let originals=try disk.saveOriginals(urls)
                let source=textParts.joined(separator:"\n\n"),old=result.originals
                let incoming=LastResult(source:prefs.autoFormat ? Paragraphs.format(source):source,translation:"",sourceLanguage:detect(source),target:prefs.target,name:urls.first?.lastPathComponent ?? "图片",originals:originals)
                do{try disk.write(incoming,name:"last-result.json")}catch{disk.prune(keeping:old);throw error}
                result=incoming
                disk.prune(keeping:originals);preview=first.map{NSImage(cgImage:$0,size:.zero)};rebuildPreviewPages();previewIndex=0;message=nil;detail="";recognitionProgress=1;busy=false;changed();onShow?();if prefs.translationEnabled{translate()}
            }catch{busy=false;let unconfigured=(error as? TextError)?.message=="尚未配置服务";status(unconfigured ? "尚未配置服务":(error is CancellationError ? "已取消识别":"识别失败"),detail:error.localizedDescription)}
        }
    }
    nonisolated static func imageFor(_ page:(URL,Int))throws->CGImage{if page.1>0{guard let doc=CGPDFDocument(page.0 as CFURL),let p=doc.page(at:page.1) else{throw TextError(message:"PDF 页面无法读取")};return try Imaging.render(p)};return try Imaging.cgImage(Data(contentsOf:page.0))}
    func translate(){
        guard !busy,!translating,!result.source.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return}
        prefs.translationEnabled=true;savePreferences();message=nil;changed()
        let engine=prefs.translationEngine,keys=keys,target=prefs.target,text=result.source
        guard keys.readyTranslation(engine) else{detail="尚未配置服务：请在账户页配置 \(engine=="google" ? "Google":"百度") 翻译密钥。";changed();return}
        if engine=="baidu",Languages.baidu[target]==nil{detail="当前目标语言请使用 Google 翻译，或选择百度支持的语言";changed();return}
        translating=true;let id=UUID();generation=id;changed()
        translationJob=Task{
            do{var outputs:[String]=[],language="auto";for chunk in CloudAPI.chunks(text,maxBytes:engine=="baidu" ? 900:4500){try Task.checkCancellation();usage.refresh();let n=chunk.unicodeScalars.count;if prefs.freeGuard && !usage.allowed(engine:engine,characters:n){throw TextError(message:"本月预设免费用量已达上限")};usage.add(engine:engine,characters:n);try saveUsage();let answer=try await api.translate(chunk,target:target,engine:engine,keys:keys);outputs.append(answer.text);if answer.language != "auto"{language=answer.language}}
                guard !Task.isCancelled,generation==id,result.source==text else{return};result.translation=outputs.joined(separator:"\n");result.sourceLanguage=language=="auto" ? detect(text):language;result.target=target;translating=false;detail="";connected.insert("translation-"+engine);saveResult()
            }catch{guard generation==id,!Task.isCancelled else{return};translating=false;detail=(error as? TextError)?.message=="尚未配置服务" ? "尚未配置服务":"翻译失败：\(error.localizedDescription)";changed()}
        }
    }
    func rebuildPreviewPages(){previewPages=[];for name in result.originals{let url=disk.root.appendingPathComponent(name);if url.pathExtension=="pdf",let doc=CGPDFDocument(url as CFURL),doc.numberOfPages>0{for n in 1...doc.numberOfPages{previewPages.append((url,n))}}else{previewPages.append((url,0))}}}
    func restorePreview(){rebuildPreviewPages();if let first=previewPages.first,let cg=try? Self.imageFor(first){preview=NSImage(cgImage:cg,size:.zero)}}
    func movePreview(_ step:Int){guard !previewPages.isEmpty else{return};previewIndex=min(previewPages.count-1,max(0,previewIndex+step));if let cg=try? Self.imageFor(previewPages[previewIndex]){preview=NSImage(cgImage:cg,size:.zero)};changed()}
}
