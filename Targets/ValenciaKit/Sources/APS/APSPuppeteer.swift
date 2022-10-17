//
//  APSPuppeteer.swift
//  ValenciaKit
//
//  Created by Eric Rabil on 10/17/22.
//  Copyright © 2022 tuist.io. All rights reserved.
//

import Foundation
import ERWeakLink
import fishhook

typealias __SecKeychainCreate_t = @convention(c) (
    _ pathName: UnsafePointer<CChar>,
    _ passwordLength: UInt32,
    _ password: UnsafeRawPointer?,
    _ promptUser: Bool,
    _ initialAccess: SecAccess?,
    _ keychain: UnsafeMutablePointer<SecKeychain?>
) -> OSStatus

typealias __SecKeychainOpen_t = @convention(c) (
    _ pathName: UnsafePointer<CChar>,
    _ keychain: UnsafeMutablePointer<SecKeychain?>
) -> OSStatus

typealias __SecKeyCreatePair_t = @convention(c) (
    _ keychainRef: SecKeychain,
    _ algorithm: CSSM_ALGORITHMS,
    _ keySizeInBits: uint32,
    _ contextHandle: CSSM_CC_HANDLE,
    _ publicKeyUsage: CSSM_KEYUSE,
    _ publicKeyAttr: uint32,
    _ privateKeyUsage: CSSM_KEYUSE,
    _ privateKeyAttr: uint32,
    _ initialAccess: SecAccess,
    _ publicKey: UnsafeRawPointer,
    _ privateKey: UnsafeRawPointer
) -> OSStatus
private var __SecKeyCreatePair: __SecKeyCreatePair_t = { kc, alg, size, ctx, usg, attr, pusg, pattr, access, pub, pri in
    unsafeBitCast(__SecKeyCreatePair$.replaced.pointee!, to: __SecKeyCreatePair_t.self)(kc, alg, size, ctx, usg, attr, pusg, attr, access, pub, pri)
}
var __SecKeyCreatePair$ = rebinding(name: strdup("SecKeyCreatePair"), replacement: unsafeBitCast(__SecKeyCreatePair, to: UnsafeMutableRawPointer.self), replaced: .allocate(capacity: 1))

typealias __unlink_t = @convention(c) (
    _ path: UnsafePointer<CChar>
) -> Int

private var __SecKeychainOpen: __SecKeychainOpen_t = { path, out in
    if strcmp(path, "/Library/Keychains/apsd.keychain") == 0 {
        return __SecKeychainOpen("/tmp/apsd.keychain", out)
    }
    return unsafeBitCast(__SecKeychainOpen$.replaced.pointee!, to: __SecKeychainOpen_t.self)(path, out)
}
var __SecKeychainOpen$ = rebinding(name: strdup("SecKeychainOpen"), replacement: unsafeBitCast(__SecKeychainOpen, to: UnsafeMutableRawPointer.self), replaced: .allocate(capacity: 1))

private var __SecKeychainCreate: __SecKeychainCreate_t = { path, passLen, pass, prompt, access, keychain in
    if strcmp(path, "/Library/Keychains/apsd.keychain") == 0 {
        return __SecKeychainCreate("/tmp/apsd.keychain", passLen, pass, prompt, access, keychain)
    }
    return unsafeBitCast(__SecKeychainCreate$.replaced.pointee!, to: __SecKeychainCreate_t.self)(path, passLen, pass, prompt, access, keychain)
}
var __SecKeychainCreate$ = rebinding(name: strdup("SecKeychainCreate"), replacement: unsafeBitCast(__SecKeychainCreate, to: UnsafeMutableRawPointer.self), replaced: .allocate(capacity: 1))

typealias __APS_keyCreation_raw = @convention(c) (NSObject, Selector, UnsafeMutablePointer<SecKey?>, UnsafeMutablePointer<SecKey?>, SecKeychain?, natural_t, natural_t, String, UnsafeMutableRawPointer) -> OSStatus

extension Notification.Name {
    static let APSIdentityProcessed: Notification.Name = .init("com.ericrabil.valencia.aps.identity-processed")
}

public class APSPuppeteer {
    public static let shared = APSPuppeteer()
    
    private lazy var apsd = ERWeakLinkHandle.string("/System/Library/PrivateFrameworks/ApplePushService.framework/apsd")
    private lazy var APSCertificateProvisioner$: APSCertificateProvisioner.Type = ERWeakLinkObjC("APSCertificateProvisioner", apsd)
    private lazy var APSCertificateStorage$: APSCertificateStorage.Type = ERWeakLinkObjC("APSCertificateStorage", apsd)
    
    init() {
        assert(rebind_symbols(&__SecKeychainOpen$, 1) == 0, "failed to rebind SecKeychainOpen")
        assert(rebind_symbols(&__SecKeychainCreate$, 1) == 0, "failed to rebind SecKeychainCreate")
        assert(rebind_symbols(&__SecKeyCreatePair$, 1) == 0, "failed to rebind SecKeyCreatePair")
        assert(swizzleKeyPairCreation(), "failed to swizzle key pair creation methods")
        assert(swizzleConnectionCompletion(), "failed to swizzle connection completion methods")
    }
    
    private let queue = DispatchQueue(label: "com.ericrabil.valencia.aps-puppeteer")
    private lazy var opQueue: OperationQueue = {
        let q = OperationQueue()
        q.underlyingQueue = queue
        return q
    }()
    
    private var keyPairs: [(SecKey, SecKey, SecKeychain, String)] = []
    private var identities: [(SecIdentity, SecCertificate)] = []
    
    private func swizzleConnectionCompletion() -> Bool {
        let sel = #selector(APSCertificateProvisioner.connection(didFinishLoading:))
        guard let meth = class_getInstanceMethod(APSCertificateProvisioner$, sel) else {
            return false
        }
        let orig = unsafeBitCast(method_getImplementation(meth), to: (@convention(c) (NSObject, Selector, NSURLConnection) -> ()).self)
        let imp = imp_implementationWithBlock({ _self, connection in
            defer {
                NotificationCenter.default.post(name: .APSIdentityProcessed, object: _self)
            }
            defer { orig(_self, sel, connection) }
            let data = unsafeBitCast(_self, to: UnsafeRawPointer.self).advanced(by: 0x10).assumingMemoryBound(to: Unmanaged<NSData>.self).pointee.takeUnretainedValue()
            do {
                let scanner = Scanner(string: String(decoding: data, as: UTF8.self))
                if scanner.scanUpToString("<Protocol>") != nil,
                   scanner.scanString("<Protocol>") != nil,
                   let xml = scanner.scanUpToString("</Protocol>"),
                   let plist = try PropertyListSerialization.propertyList(from: Data(xml.utf8), format: nil) as? [AnyHashable: Any],
                   let activation = plist["device-activation"] as? [AnyHashable: Any],
                   let record = activation["activation-record"] as? [AnyHashable: Any],
                   let certificate = record["DeviceCertificate"] as? Data
                   {
                    print(certificate)
                    var externalFormat: SecExternalFormat = .init(rawValue: 0)!
                    var externalType: SecExternalItemType = .init(rawValue: 0)!
                    var out: CFArray?
                    let kc = unsafeBitCast(_self, to: APSCertificateProvisioner.self).getKeychain()
                    SecItemImport(certificate as CFData, nil, &externalFormat, &externalType, [], nil, kc, &out)
                    if let out = out,
                       let first = (out as NSArray).firstObject {
                        var identity: SecIdentity?
                        SecIdentityCreateWithCertificate(kc, first as! SecCertificate, &identity)
                        if let identity = identity {
                            self.queue.sync {
                                self.identities.append((identity, first as! SecCertificate))
                            }
                        }
                    }
                }
            } catch {
                preconditionFailure("\(error)")
            }
        } as @convention(block) (NSObject, NSURLConnection) -> ())
        method_setImplementation(meth, imp)
        return true
    }
    
    private func swizzleKeyPairCreation() -> Bool {
        let sel = #selector(APSCertificateProvisioner.create(keyPair:privKey:keychain:algorithm:size:userName:accessRef:))
        guard let meth = class_getInstanceMethod(APSCertificateProvisioner$, sel) else {
            return false
        }
        let orig = unsafeBitCast(method_getImplementation(meth), to: __APS_keyCreation_raw.self)
        let imp = imp_implementationWithBlock({ _self, pubKey, privKey, keychain, alg, size, userName, ref in
            switch orig(_self, sel, pubKey, privKey, keychain, alg, size, userName, ref) {
            case 0:
                if let pub = pubKey.pointee, let priv = privKey.pointee, let keychain = keychain {
                    self.queue.sync {
                        self.keyPairs.append((pub, priv, keychain, userName))
                    }
                }
                return 0
            case let ret:
                return ret
            }
        } as @convention(block) (NSObject, UnsafeMutablePointer<SecKey?>, UnsafeMutablePointer<SecKey?>, SecKeychain?, natural_t, natural_t, String, UnsafeMutableRawPointer) -> OSStatus)
        method_setImplementation(meth, imp)
        return true
    }
    
    /// I had to think pretty far out of the box here. This is the easiest way I've found to supply arbitrary data to be FP-signed.
    /// This swizzle will undo itself when it detects the apsd sentinal key (`ActivationState`), and is meant to be invoked immediately before generating a client identity.
    private func swizzleDictionary(_ overrideResponder: @escaping (String) -> NSObject?) -> Bool {
        let sel = #selector(NSMutableDictionary.setObject(_:forKey:))
        guard let meth = class_getInstanceMethod(object_getClass(NSMutableDictionary()), sel) else {
            return false
        }
        let orig = unsafeBitCast(method_getImplementation(meth), to: (@convention(c) (NSObject, Selector, NSObject?, String) -> Void).self)
        let imp = imp_implementationWithBlock({ _self, value, key in
            let value = self.queue.sync { overrideResponder(key) } ?? value
            print(" *** apsd setObject:\(value?.debugDescription ?? "nil") forKey:\(key)")
            orig(_self, sel, value, key)
            if key == "ActivationState" {
                self.queue.sync {
                    method_setImplementation(meth, unsafeBitCast(orig, to: IMP.self))
                    print("returned dictionary setter to original value")
                }
            }
        } as @convention(block) (NSObject, NSObject?, String) -> Void)
        method_setImplementation(meth, imp)
        return true
    }
    
    /// Attempts to provision a keypair capable of connecting to an APS courier, using the given overrides.
    public func generateClientIdentity(overrides: [String: NSObject] = [:], callback: @escaping ((SecKey, SecKey, SecKeychain, String)?, (SecIdentity, SecCertificate)?) -> ()) {
        keyPairs = []
        identities = []
        assert(swizzleDictionary { key in
            overrides[key]
        }, "failed to swizzle dictionary")
        APSCertificateProvisioner$.init(delegate: nil).generateClientIdentity()
        NotificationCenter.default.addObserver(forName: .APSIdentityProcessed, object: nil, queue: opQueue) { notification in
            callback(self.keyPairs.first, self.identities.first)
        }
    }
}

// MARK: - apsd types

/// The apsd types must be defined here as they have no compile-time symbols.

@objc protocol APSCertificateProvisioner: NSObjectProtocol {
    @objc(initWithDelegate:) init(delegate: NSObjectProtocol!)
    @objc func generateClientIdentity()
    @objc(createUserKeyPair:privKey:keychain:algorithm:size:userName:accessRef:) func create(keyPair publicKey: UnsafeMutablePointer<SecKey?>, privKey: UnsafeMutablePointer<SecKey?>, keychain: SecKeychain!, algorithm: natural_t, size: natural_t, userName: String, accessRef: UnsafeMutableRawPointer) -> OSStatus
    @objc(connectionDidFinishLoading:) func connection(didFinishLoading: NSURLConnection)
    @objc func getKeychain() -> SecKeychain
}

@objc protocol APSCertificateStorage: NSObjectProtocol {
    @objc static func deleteKeychain()
}
