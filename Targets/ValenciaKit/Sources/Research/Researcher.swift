//
//  Researcher.swift
//  Valencia
//
//  Created by Eric Rabil on 10/28/22.
//  Copyright © 2022 tuist.io. All rights reserved.
//

import Foundation
import Swexy

struct Clashable: Hashable {
    static func == (lhs: Clashable, rhs: Clashable) -> Bool {
        lhs.class === rhs.class
    }
    
    func hash(into hasher: inout Hasher) {
        unsafeBitCast(self.class, to: OpaquePointer.self).hash(into: &hasher)
    }
    
    let `class`: AnyClass
}



public class Researcher {
    @Atomic fileprivate var originals: [Clashable: [MethodType: [Selector: IMP]]] = [:]
    @Atomic fileprivate var cOriginals: [String: UnsafeMutableRawPointer] = [:]
}

import fishhook

public extension Researcher {
    static let shared = Researcher()
}

extension Atomic {
    mutating func withExclusiveMutableAccess<P>(callback: (inout T) throws -> P) rethrows -> P {
        try callback(&wrappedValue)
    }
}

public extension Researcher {
    enum MethodType: Hashable {
        public static let `default` = MethodType.instance
        
        case instance
        case `static`
        
        func getMethod(_ cls: AnyClass, sel: Selector) -> Method? {
            switch self {
            case .instance: return class_getInstanceMethod(cls, sel)
            case .static: return class_getClassMethod(cls, sel)
            }
        }
    }
    
    struct SwizzleContext {
        public var original: IMP
        public var name: Selector
    }
    
    enum SwizzleError: Error {
        case noSuchMethod
        case alreadySwizzled(IMP)
    }
    
    func swizzle<P>(_ cls: AnyClass, type: MethodType = .default, sel: Selector, _ replacement: (SwizzleContext) -> P) throws {
        guard let method = type.getMethod(cls, sel: sel) else {
            throw SwizzleError.noSuchMethod
        }
        let clash = Clashable(class: cls)
        try _originals.withExclusiveMutableAccess { originals in
            if let imp = originals[clash]?[type]?[sel] {
                throw SwizzleError.alreadySwizzled(imp)
            }
            let imp = method_getImplementation(method)
            originals[clash, default: [:]][type, default: [:]][sel] = imp
            method_setImplementation(method, imp_implementationWithBlock(replacement(SwizzleContext(original: imp, name: sel))))
        }
    }
}

public extension Researcher {
    class CSwizzleContext<P> {
        internal init(_ rebinding: rebinding) {
            self.rebinding = rebinding
        }
        
        internal var rebinding: rebinding
        
        public var name: String {
            String(bytesNoCopy: UnsafeMutableRawPointer(mutating: rebinding.name), length: strlen(rebinding.name), encoding: .utf8, freeWhenDone: false)!
        }
        
        public var original: P! {
            rebinding.replaced.pointee?.assumingMemoryBound(to: P.self).pointee
        }
        
        public var replacement: P! {
            rebinding.replacement.assumingMemoryBound(to: P.self).pointee
        }
    }
    
    func swizzleC<P>(_ name: UnsafePointer<CChar>, replacement: P) {
        var rebinding = rebinding(
            name: name,
            replacement: unsafeBitCast(replacement, to: UnsafeMutableRawPointer.self),
            replaced: .allocate(capacity: 1)
        )
        print(rebind_symbols(&rebinding, 1))
    }
    
    func swizzleContext<P>(_ name: String) -> CSwizzleContext<P>! {
        cOriginals[name]?.assumingMemoryBound(to: CSwizzleContext<P>.self).pointee
    }
}
