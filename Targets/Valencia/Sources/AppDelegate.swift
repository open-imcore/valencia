import Cocoa
import ValenciaKit
import ValenciaUI
import IMFoundation
import IMSharedUtilities
import IMCore
import SwiftMachO
import CoreSymbolication

class BasicAPSConnectionDelegate: APSConnectionDelegate, APSConnectionParsedPayloadReceiving {
    let identity: APSIdentity
    
    init(_ identity: APSIdentity) {
        self.identity = identity
    }
    
//    func connection(_ connection: ValenciaKit.APSConnectionProtocol, finishedReading reader: ValenciaKit.APSReader) {
//        print("command: ", reader.command)
//        print("size: ", reader.size)
//        print("fields: ", (reader.fields as NSDictionary).debugDescription)
//    }
    
    func connection(_ connection: APSConnectionProtocol, received payload: APSPayload) {
        print("received payload \(payload.command.rawValue), \((payload.fields as NSDictionary).debugDescription)")
        switch payload.command {
        case .connectResponse:
            if let response = APSConnectResponse(payload: payload) {
                if let token = response.pushToken {
                    try! identity.record(pushToken: token)
                }
            }
        default:
            return
        }
    }
    
    func connection(disconnected connection: ValenciaKit.APSConnectionProtocol) {
        
    }
    
    func connection(connected connection: ValenciaKit.APSConnectionProtocol) {
        connection.send(APSPayload(command: .connect, fields: [2: Data([1])]))
    }
    
    func connection(replaced connection: ValenciaKit.APSConnectionProtocol, replacement: ValenciaKit.APSConnectionProtocol) {
        
    }
}

import ERWeakLink

func lookupAuthKitString(_ name: String) -> String! {
    ERWeakLinkSymbol(name, .privateFramework("AuthKit")) as CFString? as String?
}

typealias CFMachPortCreateWithPort_t = @convention(c) (
    _ allocator: CFAllocator?,
    _ portNum: mach_port_t,
    _ callout: CFMachPortCallBack?,
    _ context: UnsafeMutablePointer<CFMachPortContext>?,
    _ shouldFreeInfo: UnsafeMutablePointer<DarwinBoolean>?
) -> CFMachPort

typealias ptrace_t = @convention(c) (CInt, pid_t, caddr_t, CInt) -> CInt
let _ptrace = {
    if $0 == 31 { // PT_DENY_ATTACH
        return 0
    }
    return (Researcher.shared.swizzleContext("_ptrace") as Researcher.CSwizzleContext<ptrace_t>).original($0, $1, $2, $3)
} as ptrace_t

//struct dyld_interpose_tuple {
//    const void* replacement;
//    const void* replacee;
//};
//extern void dyld_dynamic_interpose(const struct mach_header* mh, const struct dyld_interpose_tuple array[], size_t count);

@_cdecl("ptrace_fake") func ptrace_fake(_ arg1: CInt, _ pid: pid_t, _ addr: caddr_t, _ arg4: CInt) -> CInt {
    return 0
}

@main struct AppDelegate {
    static func main() throws {
//        Researcher.shared.swizzleC("_CFMachPortCreateWithPort", replacement: { allocator, portNum, callout, context, shouldFreeInfo in
//            print(allocator, portNum, callout, context, shouldFreeInfo)
//            return (Researcher.shared.swizzleContext("_CFMachPortCreateWithPort") as Researcher.CSwizzleContext<CFMachPortCreateWithPort_t>).original(allocator, portNum, callout, context, shouldFreeInfo)
//        } as CFMachPortCreateWithPort_t)
        
//        let adid = dlopen("/System/Library/PrivateFrameworks/CoreADI.framework/adid", RTLD_LAZY)
//        print(dlsym(adid, "EntryPoint"))
//        print(dlsym(adid, "_EntryPoint"))
//        print(dlsym(adid, "main"))
//        let header = dlsym(adid, "_mh_execute_header")!
        let headerData = try Data(contentsOf: URL(fileURLWithPath: "/System/Library/PrivateFrameworks/CoreADI.framework/Versions/A/adid"))
        let macho = try MachO(fromData: headerData)
        
        for cmd in macho.cmds {
            switch cmd {
            case let mainCommand as MainLoadCommand:
//                DispatchQueue.global().asyncAfter(deadline: .now().advanced(by: .seconds(5))) {
                let adid = dlopen("/System/Library/PrivateFrameworks/CoreADI.framework/adid", RTLD_LAZY)
                let execHeader = dlsym(adid, "_mh_execute_header")!
                var info = Dl_info()
                guard dladdr(execHeader, &info) != 0 else {
                    preconditionFailure()
                }
                withUnsafePointer(to: ptrace_fake) { ptrace_fake in
                    var interpose = dyld_interpose_tuple(replacement: ptrace_fake, replacee: dlsym(adid, "ptrace"))
                    dyld_dynamic_interpose(info.dli_fbase.assumingMemoryBound(to: mach_header.self), &interpose, 1)
                    let main = execHeader.advanced(by: Int(mainCommand.entryOffset))
                    let result = unsafeBitCast(main, to: (@convention(c) () -> Int).self)()
                    print("result: \(result)")
                }
            default:
                break
            }
        }
//        headerData.withUnsafeBytes { buffer in
//            let header = buffer.baseAddress!
//            let mheader = header.assumingMemoryBound(to: mach_header_64.self).pointee
//            var cursor = header.advanced(by: MemoryLayout<mach_header_64>.size)
//            var current: load_command {
//                unsafeAddress {
//                    UnsafePointer(cursor.assumingMemoryBound(to: load_command.self))
//                }
//            }
//            for i in 0..<Int(mheader.ncmds) {
//                defer {
//                    if UInt64(i) != (mheader.ncmds) - 1 {
//                        cursor = cursor.advanced(by: Int(current.cmdsize))
//                    }
//                }
//                if current.cmd == LC_MAIN {
//                    atexit {
//                        print("asdf")
//                    }
//                    atexit_b {
//                        print("asdfasdf")
//                    }
//    //                int    ptrace(int _request, pid_t _pid, caddr_t _addr, int _data);
//                    typealias ptrace_t = @convention(c) (CInt, pid_t, caddr_t, CInt) -> CInt
                    
//    //                DispatchQueue.global().asyncAfter(deadline: .now().advanced(by: .seconds(5))) {
//                    let adid = dlopen("/System/Library/PrivateFrameworks/CoreADI.framework/adid", RTLD_LAZY)
//                    let execHeader = dlsym(adid, "_mh_execute_header")!
//
//                    let offset = cursor.assumingMemoryBound(to: entry_point_command.self).pointee.entryoff
//                    let main = execHeader.advanced(by: Int(offset))
//                    print(unsafeBitCast(main, to: (@convention(c) () -> Int).self)())
////                    let thread = Thread(block: unsafeBitCast(, to: (@convention(c) () -> Void).self))
////                    NotificationCenter.default.addObserver(forName: .NSThreadWillExit, object: thread, queue: .main) {
////                        print($0)
////                    }
////                        thread.start()
//    //                }
//                    break
//                }
//            }
//        }
//        let data = Data(bytesNoCopy: header!, count: Int(header!.assumingMemoryBound(to: mach_header_64.self).pointee.sizeofcmds), deallocator: .none)
//        let _macho = try SwiftMachO.MachO(fromFile: "/System/Library/PrivateFrameworks/CoreADI.framework/adid")
//        let _data = Data(bytesNoCopy: header, count: _macho.data.count, deallocator: .none)
//        let macho = try SwiftMachO.MachO(_data)
//        print(macho.cpuType == CPU_TYPE_ARM64)
//        print(Int(mheader.ncmds) == macho.cmds.count)
//        let symbolicator = CSSymbolicatorCreateWithTask(mach_task_self_)
//        defer { CSRelease(symbolicator) }
//        let owner = CSSymbolicatorGetSymbolOwnerWithNameAtTime(symbolicator, "adid", UInt64(kCSNow))
//        defer { CSRelease(owner) }
//        let region = CSSymbolOwnerGetRegionWithName(owner, "__TEXT __text")
//        defer { CSRelease(region) }
//        var symbols: [CSSymbolRef] = []
//        defer { symbols.forEach(CSRelease(_:)) }
//        if region.csCppData != nil {
//            CSRegionForeachSymbol(region) { symbol in
//                symbols.append(symbol)
//                return 1
//            }
//        }
//        print(CSRegionGetRange(region).location)
//
//        CSSymbolicatorForeachRegionAtTime(symbolicator, UInt64(kCSNow)) { section in
//            if strcmp(CSSymbolOwnerGetName(CSRegionGetSymbolOwner(section)), "adid") == 0 {
//                print(String(cString: CSRegionGetName(section)))
//                CSRegionForeachSymbol(section) { symbol in
//                    if let name = CSSymbolGetName(symbol) ?? CSSymbolGetMangledName(symbol) {
//                        if strcmp("MACH_HEADER", name) == 0 {
//                            print(CSSymbolGetInstructionData(symbol))
//                        }
//                        print(String(cString: name))
//                    } else {
//                        print(CSSymbolGetRange(symbol).location)
//                    }
//                    return 1
//                }
//            }
//            return 1
//        }
//        for (idx, cmd) in macho.cmds.enumerated() {
//            switch cmd {
//            case let main as MainLoadCommand:
//                print("START")
//                print(Int(main.entryOffset))
//                for symbol in symbols {
//                    let range = CSSymbolGetRange(symbol)
//                    if Int(range.location) - Int(bitPattern: header) == main.entryOffset {
////                        unsafeBitCast(UnsafeMutableRawPointer(bitPattern: Int(range.location)), to: (@convention(c) () -> Int).self)()
//                        print(CSSymbolOwnerGetBaseAddress(CSSymbolGetSymbolOwner(symbol)))
//                        print("GAY")
//                    }
//                }
//                print("STOP")
//                print(Int(CSRegionGetRange(region).location + main.entryOffset))
//
////                Thread(block: entry!).start()
//                print(main.entryOffset)
//            case let seg as Segment64LoadCommand:
//                print(seg.name)
//            default:
//                continue
//            }
//        }
//        print(adid)
        
        print(lookupAuthKitString("AKHTTPHeaderClientInfo")!)
        print(Anisette.shared)
        
//        var con: APSConnection?
        
        
        
//        let identities = APSIdentityStorage.shared.loadIdentities()
        
//        APSIdentityStorage.shared.loadIdentity { result in
//            switch result.map(APSConnection.init(identity:)) {
//            case .success(let connection):
//                connection.connect()
//                con = connection
//                break
//            case .failure(let error):
//                fatalError()
//            }
//        }
        
//        APSPuppeteer.shared.generateClientIdentity(overrides: [
//            "SerialNumber": "ABCDEFGHIJ" as NSString,
//            "UniqueDeviceID": UUID().uuidString as NSString
//        ]) { keys, identity in
//            guard let (pub, pri, kc, name) = keys else {
//                preconditionFailure()
//            }
//            guard let identity = identity else {
//                preconditionFailure()
//            }
//            ses = EphemeralAPSConnection(identity: identity.0, pub: pub, pri: pri, kc: kc, name: name)
//            ses!.delegate = BasicAPSConnectionDelegate.shared
//            ses!.connect()
//        }
        
        dispatchMain()
    }
}
