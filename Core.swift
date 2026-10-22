import AppKit
import ImageIO
import UniformTypeIdentifiers
import CryptoKit
import Security

struct TextError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
    static let unconfigured = TextError(message:"尚未配置服务")
}
struct Credentials:Codable {
    var googleOCR = "", googleTranslation = "", baiduOCR = "", baiduOCRSecret = "", baiduAppID = "", baiduTranslationSecret = ""
    func readyOCR(_ engine:String)->Bool { engine == "google" ? !googleOCR.isEmpty : !baiduOCR.isEmpty && !baiduOCRSecret.isEmpty }
    func readyTranslation(_ engine:String)->Bool { engine == "google" ? !googleTranslation.isEmpty : !baiduAppID.isEmpty && !baiduTranslationSecret.isEmpty }
}
enum SecretStore {
    // 新记录与旧 local.text.menubar.keys 完全隔离，不自动读取或删除旧条目。
    static let service="local.text.menubar.credentials.v2",account="services"
    static var lastLoadStatus:OSStatus=errSecSuccess
    struct Record:Codable {let version:Int;let credentials:Credentials}
    static func encoded(_ credentials:Credentials)throws->Data {try JSONEncoder().encode(Record(version:1,credentials:credentials))}
    static func decoded(_ data:Data)throws->Credentials {let record=try JSONDecoder().decode(Record.self,from:data);guard record.version==1 else{throw TextError(message:"不支持的凭据记录格式")};return record.credentials}
    static func query(keychain:SecKeychain?)->[String:Any]{
        var q:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account,kSecMatchLimit as String:kSecMatchLimitOne,kSecUseAuthenticationUI as String:kSecUseAuthenticationUIFail]
        if let keychain{q[kSecMatchSearchList as String]=[keychain]};return q
    }
    static func load(keychain:SecKeychain?=nil)->Credentials {
        // 旧式钥匙串 ACL 不一定遵循查询级 UI 标志；仅在本次读取期间禁止当前进程交互。
        var interactionAllowed:DarwinBoolean=false
        let interactionStatus=SecKeychainGetUserInteractionAllowed(&interactionAllowed)
        guard interactionStatus==errSecSuccess else{lastLoadStatus=interactionStatus;return Credentials()}
        let disableStatus=SecKeychainSetUserInteractionAllowed(false)
        guard disableStatus==errSecSuccess else{lastLoadStatus=disableStatus;return Credentials()}
        defer{SecKeychainSetUserInteractionAllowed(interactionAllowed.boolValue)}
        var q=query(keychain:keychain);q[kSecReturnData as String]=true
        var result:CFTypeRef?;lastLoadStatus=SecItemCopyMatching(q as CFDictionary,&result)
        guard lastLoadStatus==errSecSuccess,let data=result as? Data else{return Credentials()}
        do{return try decoded(data)}catch{lastLoadStatus=errSecDecode;return Credentials()}
    }
    static let names=["googleOCR","googleTranslation","baiduOCR","baiduOCRSecret","baiduAppID","baiduTranslationSecret"]
    static func pendingChanges(_ c:Credentials,previous:Credentials?)->[(String,String)] {
        let values=[c.googleOCR,c.googleTranslation,c.baiduOCR,c.baiduOCRSecret,c.baiduAppID,c.baiduTranslationSecret].map{$0.trimmingCharacters(in:.whitespacesAndNewlines)}
        let old=previous.map{[$0.googleOCR,$0.googleTranslation,$0.baiduOCR,$0.baiduOCRSecret,$0.baiduAppID,$0.baiduTranslationSecret]}
        return names.indices.compactMap{i in if let old,old[i]==values[i]{return nil};return (names[i],values[i])}
    }
    static func saveAll(_ c:Credentials,previous:Credentials?=nil,keychain:SecKeychain?=nil)throws {
        if previous != nil && pendingChanges(c,previous:previous).isEmpty{return}
        let data=try encoded(c);var q=query(keychain:keychain);q[kSecReturnRef as String]=true
        var ref:CFTypeRef?;var status=SecItemCopyMatching(q as CFDictionary,&ref)
        if status==errSecItemNotFound {
            // 使用当前签名身份创建受保护的 macOS 专用记录，不放宽为所有应用可访问。
            status=data.withUnsafeBytes{bytes in guard let pointer=bytes.baseAddress else{return errSecParam};return SecKeychainAddGenericPassword(keychain,UInt32(service.utf8.count),service,UInt32(account.utf8.count),account,UInt32(data.count),pointer,nil)}
        }else if status==errSecSuccess,let ref {
            status=data.withUnsafeBytes{bytes in SecKeychainItemModifyAttributesAndData((ref as! SecKeychainItem),nil,UInt32(data.count),bytes.baseAddress)}
        }
        guard status==errSecSuccess else{throw TextError(message:"Text 专用凭据保存失败（\(status)）。旧密钥记录未改动。")}
    }
}

struct Shortcut:Codable,Equatable {
    var code:UInt32, flags:UInt, key:String
    static let capture=Shortcut(code:18,flags:NSEvent.ModifierFlags.command.rawValue,key:"1")
    static let results=Shortcut(code:15,flags:NSEvent.ModifierFlags([.command,.shift]).rawValue,key:"R")
    var display:String {let f=NSEvent.ModifierFlags(rawValue:flags);return (f.contains(.control) ? "⌃":"")+(f.contains(.option) ? "⌥":"")+(f.contains(.shift) ? "⇧":"")+(f.contains(.command) ? "⌘":"")+key.uppercased()}
}
struct Preferences:Codable {
    var autoHide=true, autoFormat=false, onTop=false, showImage=false, translationEnabled=false, freeGuard=true
    var ocrEngine="baidu", translationEngine="baidu", target="zh-CN", iconStyle=0
    var capture:Shortcut? = .capture, results:Shortcut? = .results
    var width:Double=270, height:Double=203, previewWidth:Double=270, previewHeight:Double=203
    var uniformWindowSizeVersion:Int? = 3
}
struct LastResult:Codable {
    var source="", translation="", sourceLanguage="auto", target="zh-CN", name="", originals:[String]=[]
}
struct MonthUsage:Codable {
    var month="", googleOCR=0, googleCharacters=0, baiduOCR=0, baiduCharacters=0, baiduTranslationCalls=0
    var baiduTranslationPartial=false
    static var currentMonth:String {let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.timeZone=TimeZone.current;f.dateFormat="yyyy-MM";return f.string(from:Date())}
    mutating func refresh(){if month != Self.currentMonth{self=MonthUsage(month:Self.currentMonth)}}
    func allowed(engine:String,characters:Int?=nil)->Bool {
        if let n=characters {return engine=="google" ? googleCharacters+n <= 450_000 : baiduCharacters+n <= 40_000}
        return engine=="google" ? googleOCR+1 <= 900 : baiduOCR+1 <= 900
    }
    mutating func add(engine:String,characters:Int?=nil){refresh();if let n=characters {if engine=="google"{googleCharacters+=n}else{baiduCharacters+=n;baiduTranslationCalls+=1}}else{if engine=="google"{googleOCR+=1}else{baiduOCR+=1}}}
}
extension MonthUsage {
    init(from decoder:Decoder)throws {
        self.init();let c=try decoder.container(keyedBy:CodingKeys.self)
        month=try c.decodeIfPresent(String.self,forKey:.month) ?? ""
        googleOCR=try c.decodeIfPresent(Int.self,forKey:.googleOCR) ?? 0;googleCharacters=try c.decodeIfPresent(Int.self,forKey:.googleCharacters) ?? 0
        baiduOCR=try c.decodeIfPresent(Int.self,forKey:.baiduOCR) ?? 0;baiduCharacters=try c.decodeIfPresent(Int.self,forKey:.baiduCharacters) ?? 0
        baiduTranslationCalls=try c.decodeIfPresent(Int.self,forKey:.baiduTranslationCalls) ?? 0
        baiduTranslationPartial=try c.decodeIfPresent(Bool.self,forKey:.baiduTranslationPartial) ?? (baiduCharacters>0)
    }
}
final class DiskStore {
    let root:URL
    init(root:URL?=nil)throws {
        self.root=root ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("TextMenu",isDirectory:true)
        try FileManager.default.createDirectory(at:self.root,withIntermediateDirectories:true)
        var values=URLResourceValues();values.isExcludedFromBackup=true;var url=self.root;try? url.setResourceValues(values)
    }
    func read<T:Decodable>(_ name:String,as:T.Type)->T? {guard let data=try? Data(contentsOf:root.appendingPathComponent(name)) else{return nil};return try? JSONDecoder().decode(T.self,from:data)}
    func write<T:Encodable>(_ value:T,name:String)throws{try JSONEncoder().encode(value).write(to:root.appendingPathComponent(name),options:.atomic)}
    func saveOriginals(_ files:[URL])throws->[String] {
        let folder="input-"+UUID().uuidString;let dir=root.appendingPathComponent(folder,isDirectory:true);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        do {return try files.enumerated().map {index,url in let name="\(folder)/\(index).\(url.pathExtension.lowercased())";try FileManager.default.copyItem(at:url,to:root.appendingPathComponent(name));return name}}
        catch{try? FileManager.default.removeItem(at:dir);throw error}
    }
    func prune(keeping names:[String]) {let keep=Set(names.compactMap{$0.split(separator:"/").first.map(String.init)});for url in (try? FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)) ?? [] where url.lastPathComponent.hasPrefix("input-") && !keep.contains(url.lastPathComponent){try? FileManager.default.removeItem(at:url)}}
}
enum Imaging {
    static func cgImage(_ data:Data,max:CGFloat=2800)throws->CGImage {
        guard let source=CGImageSourceCreateWithData(data as CFData,nil),let image=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:max,kCGImageSourceShouldCacheImmediately:true] as CFDictionary) else{throw TextError(message:"图片无法读取，请选择 PNG、JPG、HEIC 或 WebP 图片")};return image
    }
    static func jpeg(_ image:CGImage)throws->Data {
        guard let context=CGContext(data:nil,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue) else{throw TextError(message:"图片背景处理失败")}
        let rect=CGRect(x:0,y:0,width:image.width,height:image.height);context.setFillColor(CGColor(gray:1,alpha:1));context.fill(rect);context.draw(image,in:rect);guard let opaque=context.makeImage() else{throw TextError(message:"图片背景处理失败")}
        let data=NSMutableData();guard let output=CGImageDestinationCreateWithData(data,UTType.jpeg.identifier as CFString,1,nil) else{throw TextError(message:"图片转换失败")};CGImageDestinationAddImage(output,opaque,[kCGImageDestinationLossyCompressionQuality:0.88] as CFDictionary);guard CGImageDestinationFinalize(output) else{throw TextError(message:"图片转换失败")};return data as Data
    }
    static func render(_ page:CGPDFPage)throws->CGImage {
        let rect=page.getBoxRect(.mediaBox);let scale=min(2.4,2800/max(rect.width,rect.height));let w=max(1,Int(rect.width*scale)),h=max(1,Int(rect.height*scale))
        guard let ctx=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{throw TextError(message:"PDF 页面无法渲染")}
        let dest=CGRect(x:0,y:0,width:w,height:h);ctx.setFillColor(CGColor(gray:1,alpha:1));ctx.fill(dest);ctx.concatenate(page.getDrawingTransform(.mediaBox,rect:dest,rotate:0,preserveAspectRatio:true));ctx.drawPDFPage(page);guard let image=ctx.makeImage() else{throw TextError(message:"PDF 页面无法渲染")};return image
    }
}
enum Paragraphs {
    static func format(_ text:String)->String {
        let paragraphs=text.replacingOccurrences(of:"\r\n",with:"\n").components(separatedBy:"\n\n")
        return paragraphs.map {paragraph in
            let lines=paragraph.split(separator:"\n").map {String($0).replacingOccurrences(of:"[ \\t]+",with:" ",options:.regularExpression).trimmingCharacters(in:.whitespaces)}
            return lines.reduce(""){result,line in guard !result.isEmpty else{return line};let a=result.unicodeScalars.last?.value ?? 0,b=line.unicodeScalars.first?.value ?? 0;let bothChinese=(0x3400...0x9fff).contains(a)&&(0x3400...0x9fff).contains(b);return result+(bothChinese ? "":" ")+line}
        }.filter{!$0.isEmpty}.joined(separator:"\n\n")
    }
}
struct TranslationResponse {var text:String, language:String}
struct CloudAPI {
    var session:URLSession = .shared
    func send(_ url:URL,json:[String:Any]?=nil,form:[String:String]?=nil)async throws->[String:Any] {
        var request=URLRequest(url:url);request.httpMethod="POST";request.timeoutInterval=35
        if let json {request.setValue("application/json; charset=utf-8",forHTTPHeaderField:"Content-Type");request.httpBody=try JSONSerialization.data(withJSONObject:json)}
        if let form {var parts=URLComponents();parts.queryItems=form.map{URLQueryItem(name:$0.key,value:$0.value)};request.httpBody=parts.percentEncodedQuery?.replacingOccurrences(of:"+",with:"%2B").data(using:.utf8);request.setValue("application/x-www-form-urlencoded; charset=utf-8",forHTTPHeaderField:"Content-Type")}
        let (data,response)=try await session.data(for:request)
        guard let obj=try JSONSerialization.jsonObject(with:data) as? [String:Any] else{throw TextError(message:"服务返回格式异常")}
        if let error=obj["error"] as? [String:Any] {throw TextError(message:error["message"] as? String ?? "服务调用失败")}
        if obj["error"] is String {throw TextError(message:"服务授权失败，请检查账户配置")}
        if let code=obj["error_code"] {throw TextError(message:"服务错误 \(code)：\(obj["error_msg"] as? String ?? "请检查密钥与服务权限")")}
        guard let response=response as? HTTPURLResponse,(200...299).contains(response.statusCode) else{throw TextError(message:"服务请求失败，请检查网络或账户配置")};return obj
    }
    func recognize(_ data:Data,engine:String,keys:Credentials)async throws->String {
        guard keys.readyOCR(engine) else{throw TextError.unconfigured}
        if engine=="google" {
            var url=URLComponents(string:"https://vision.googleapis.com/v1/images:annotate")!;url.queryItems=[URLQueryItem(name:"key",value:keys.googleOCR)]
            let obj=try await send(url.url!,json:["requests":[["image":["content":data.base64EncodedString()],"features":[["type":"DOCUMENT_TEXT_DETECTION"]]]]])
            guard let result=(obj["responses"] as? [[String:Any]])?.first else{throw TextError(message:"未收到识别结果")}
            if let error=result["error"] as? [String:Any] {throw TextError(message:error["message"] as? String ?? "识别失败")}
            if let full=result["fullTextAnnotation"] as? [String:Any],let pages=full["pages"] as? [[String:Any]] {
                var paragraphs:[String]=[]
                for page in pages{for block in page["blocks"] as? [[String:Any]] ?? []{for paragraph in block["paragraphs"] as? [[String:Any]] ?? []{
                    var line=""
                    for word in paragraph["words"] as? [[String:Any]] ?? []{for symbol in word["symbols"] as? [[String:Any]] ?? []{line+=symbol["text"] as? String ?? "";let property=symbol["property"] as? [String:Any],br=property?["detectedBreak"] as? [String:Any],kind=br?["type"] as? String ?? "";if ["SPACE","SURE_SPACE"].contains(kind){line+=" "}else if ["LINE_BREAK","EOL_SURE_SPACE"].contains(kind){line+="\n"}else if kind=="HYPHEN"{line+="-\n"}}}
                    if !line.isEmpty{paragraphs.append(line.trimmingCharacters(in:.whitespacesAndNewlines))}
                }}}
                if !paragraphs.isEmpty{return paragraphs.joined(separator:"\n\n")}
            }
            return (result["fullTextAnnotation"] as? [String:Any])?["text"] as? String ?? (result["textAnnotations"] as? [[String:Any]])?.first?["description"] as? String ?? ""
        }
        let auth=try await send(URL(string:"https://aip.baidubce.com/oauth/2.0/token")!,form:["grant_type":"client_credentials","client_id":keys.baiduOCR,"client_secret":keys.baiduOCRSecret])
        guard let token=auth["access_token"] as? String else{throw TextError(message:"百度 OCR 授权失败")}
        var url=URLComponents(string:"https://aip.baidubce.com/rest/2.0/ocr/v1/general_basic")!;url.queryItems=[URLQueryItem(name:"access_token",value:token)]
        let obj=try await send(url.url!,form:["image":data.base64EncodedString(),"detect_direction":"true","paragraph":"true"])
        let words=(obj["words_result"] as? [[String:Any]] ?? []).compactMap{$0["words"] as? String}
        if let paragraphs=obj["paragraphs_result"] as? [[String:Any]],!paragraphs.isEmpty {return paragraphs.compactMap {p->String? in guard let indexes=p["words_result_idx"] as? [Int] else{return nil};return indexes.filter{words.indices.contains($0)}.map{words[$0]}.joined(separator:"\n")}.joined(separator:"\n\n")}
        return words.joined(separator:"\n")
    }
    func translate(_ text:String,target:String,engine:String,keys:Credentials)async throws->TranslationResponse {
        guard keys.readyTranslation(engine) else{throw TextError.unconfigured}
        if engine=="google" {
            var url=URLComponents(string:"https://translation.googleapis.com/language/translate/v2")!;url.queryItems=[URLQueryItem(name:"key",value:keys.googleTranslation)]
            let obj=try await send(url.url!,json:["q":text,"target":target,"format":"text"])
            guard let body=obj["data"] as? [String:Any],let result=(body["translations"] as? [[String:Any]])?.first,let translation=result["translatedText"] as? String else{throw TextError(message:"未收到翻译结果")}
            return TranslationResponse(text:translation,language:result["detectedSourceLanguage"] as? String ?? "auto")
        }
        guard let target=Languages.baidu[target] else{throw TextError(message:"百度暂未适配此目标语言，请选择 Google 翻译")}
        let salt=UUID().uuidString,sign=Insecure.MD5.hash(data:Data((keys.baiduAppID+text+salt+keys.baiduTranslationSecret).utf8)).map{String(format:"%02x",$0)}.joined()
        let obj=try await send(URL(string:"https://fanyi-api.baidu.com/api/trans/vip/translate")!,form:["q":text,"from":"auto","to":target,"appid":keys.baiduAppID,"salt":salt,"sign":sign])
        guard let rows=obj["trans_result"] as? [[String:Any]] else{throw TextError(message:"未收到翻译结果")}
        let from=obj["from"] as? String ?? "auto",language=Languages.baidu.first(where:{$0.value==from})?.key ?? from
        return TranslationResponse(text:rows.compactMap{$0["dst"] as? String}.joined(separator:"\n"),language:language)
    }
    static func chunks(_ text:String,maxBytes:Int)->[String] {var parts:[String]=[],part="";for char in text{let next=String(char);if part.utf8.count+next.utf8.count>maxBytes{parts.append(part);part=""};part+=next};if !part.isEmpty{parts.append(part)};return parts}
}
enum Languages {
    static let codes="zh-CN en ja ko fr de es ru pt it ar th vi zh-TW af sq am hy az eu be bn bs bg ca ceb ny co hr cs da nl eo et tl fi fy gl ka el gu ht ha haw he hi hmn hu is ig id ga jv kn kk km rw ku ky lo la lv lt lb mk mg ms ml mt mi mr mn my ne no or ps fa pl pa ro sm gd sr st sn sd si sk sl so su sw sv tg ta tt te tr tk uk ur ug uz cy xh yi yo zu".split(separator:" ").map(String.init)
    static let baidu=["zh-CN":"zh","zh-TW":"cht","en":"en","ja":"jp","ko":"kor","fr":"fra","de":"de","es":"spa","ru":"ru","pt":"pt","it":"it","ar":"ara","th":"th","vi":"vie","el":"el","nl":"nl","pl":"pl","bg":"bul","et":"est","da":"dan","fi":"fin","cs":"cs","ro":"rom","sl":"slo","sv":"swe","hu":"hu","yue":"yue","wyw":"wyw"]
    static func name(_ code:String)->String {if code=="zh-CN"{return "简体中文"};if code=="zh-TW"{return "繁体中文"};if code=="yue"{return "粤语"};if code=="wyw"{return "文言文"};return Locale(identifier:"zh_Hans").localizedString(forLanguageCode:code) ?? code}
}
