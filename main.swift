import AppKit

let args=CommandLine.arguments
MainActor.assumeIsolated {
    if let i=args.firstIndex(of:"--make-icons"),args.count>i+1 {do{try AppArtwork.makeIcons(URL(fileURLWithPath:args[i+1]));exit(0)}catch{fputs(error.localizedDescription,stderr);exit(1)}}
    if let i=args.firstIndex(of:"--render-previews"),args.count>i+1{do{try SelfTests.render(URL(fileURLWithPath:args[i+1]));exit(0)}catch{fputs(error.localizedDescription,stderr);exit(1)}}
    if let i=args.firstIndex(of:"--self-test"),args.count>i+1 {Task{@MainActor in let code=await SelfTests.run(URL(fileURLWithPath:args[i+1]));exit(code)};RunLoop.main.run();exit(1)}
    do {
        var testRoot:URL?
        if let i=args.firstIndex(of:"--test-root"),args.count>i+1{testRoot=URL(fileURLWithPath:args[i+1])}
        if Bundle.main.bundleIdentifier?.hasSuffix(".uitest")==true,let path=Bundle.main.object(forInfoDictionaryKey:"TextUITestRoot") as? String{testRoot=URL(fileURLWithPath:path)}
        if testRoot==nil,let id=Bundle.main.bundleIdentifier,let existing=NSRunningApplication.runningApplications(withBundleIdentifier:id).first(where:{$0.processIdentifier != ProcessInfo.processInfo.processIdentifier}){existing.activate(options:[.activateIgnoringOtherApps]);exit(0)}
        let store=try DiskStore(root:testRoot),state=TextState(disk:store,loadKeys:testRoot==nil)
        if testRoot != nil,let i=args.firstIndex(of:"--fixture"),args.count>i+1,let fixture=try? JSONDecoder().decode(LastResult.self,from:Data(contentsOf:URL(fileURLWithPath:args[i+1]))){state.result=fixture;state.prefs.translationEnabled=true;state.detail="界面验证文本 · 非真实识别结果"}
        let app=NSApplication.shared,delegate=TextApp(state:state);app.delegate=delegate;withExtendedLifetime(delegate){app.run()}
    }catch{let a=NSAlert();a.messageText="Text 无法启动";a.informativeText=error.localizedDescription;a.runModal();exit(1)}
}
