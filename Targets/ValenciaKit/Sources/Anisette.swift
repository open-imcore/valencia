//
//  Anisette.swift
//  ValenciaKit
//
//  Created by Eric Rabil on 10/24/22.
//  Copyright © 2022 tuist.io. All rights reserved.
//

import Foundation
import ERWeakLink

@objc protocol AKADIProxy: NSObjectProtocol {
    @objc(getIDMSRoutingInfo:forDSID:)
    static func getIDMSRoutingInfo(_ info: UnsafeMutablePointer<CUnsignedLongLong>, for dsid: CUnsignedLongLong) -> CInt
    @objc(setIDMSRoutingInfo:forDSID:)
    static func setIDMSRoutingInfo(_ info: CUnsignedLongLong, for dsid: CUnsignedLongLong) -> CInt
    @objc(requestOTPForDSID:outMID:outMIDSize:outOTP:outOTPSize:)
    static func requestOTP(for dsid: CUnsignedLongLong, outMID: UnsafeMutablePointer<UnsafePointer<CChar>>, outMIDSize: UnsafeMutablePointer<CUnsignedInt>, outOTP: UnsafeMutablePointer<UnsafePointer<CChar>>, outOTPSize: UnsafeMutablePointer<CUnsignedInt>) -> CInt
    @objc(dispose:)
    static func dispose(_ buf: UnsafeMutableRawPointer) -> CInt
    @objc(isMachineProvisioned:)
    static func isProvisioned(for dsid: CUnsignedLongLong) -> CInt
    // +(int)startProvisioningWithDSID:(unsigned long long)arg2 SPIM:(char *)arg3 SPIMLength:(unsigned int)arg4 outCPIM:(char * *)arg5 outCPIMLength:(unsigned int *)arg6 outSession:(unsigned int *)arg7
    @objc(startProvisioningWithDSID:SPIM:SPIMLength:outCPIM:outCPIMLength:outSession:)
    static func startProvisioning(with dsid: CUnsignedLongLong, spim: UnsafePointer<CChar>, spimLength: CUnsignedInt, outCPIM: UnsafeMutablePointer<UnsafePointer<CChar>>, outCPIMLength: UnsafeMutablePointer<CUnsignedInt>, outSession: UnsafeMutablePointer<CUnsignedInt>) -> CInt
    @objc(endProvisioningWithSession:PTM:PTMLength:TK:TKLength:)
    static func endProvisioning(with session: CUnsignedInt, ptm: UnsafePointer<CChar>, ptmLength: CUnsignedInt, tk: UnsafePointer<CChar>, tkLength: CUnsignedInt) -> CInt
    @objc(destroyProvisioningSession:)
    static func destroyProvisioningSession(_ id: CUnsignedInt) -> CInt
    @objc(synchronizeWithDSID:SIM:SIMLength:outMID:outMIDLength:outSRM:outSRMLength:)
    static func synchronize(with dsid: CUnsignedLongLong, sim: UnsafePointer<CChar>, simLength: CUnsignedInt, outMID: UnsafeMutablePointer<UnsafePointer<CChar>>, outMIDLength: UnsafeMutablePointer<CUnsignedInt>, outSRM: UnsafeMutablePointer<UnsafePointer<CChar>>, outSRMLength: UnsafeMutablePointer<CUnsignedInt>) -> CInt
    @objc(eraseProvisioningForDSID:)
    static func eraseProvisioning(for dsid: CUnsignedLongLong) -> CInt
}

public class Anisette {
    public static let shared = Anisette()
    
    let AKADIProxy$: AKADIProxy.Type = ERWeakLinkObjC("AKADIProxy", .string("/System/Library/PrivateFrameworks/AuthKit.framework/Versions/A/Support/akd"))
    
    init() {
        var info: CUnsignedLongLong = 0
        print(AKADIProxy$.getIDMSRoutingInfo(&info, for: 1234))
    }
}
