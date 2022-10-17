//
//  APSProtocol.swift
//  ValenciaKit
//
//  Created by Eric Rabil on 10/18/22.
//  Copyright © 2022 tuist.io. All rights reserved.
//

import Foundation
import CryptoKit

public enum APSCommand: UInt8 {
    case connect = 7
    case connectResponse = 8
    case pushTopics = 9
    case pushNotification = 10
    case pushNotificationResponse = 11
    case keepAlive = 12
    case keepAliveAck = 13
    case noStorage = 14
    case flush = 15
}

extension APSCommand: CustomStringConvertible {
    public var description: String {
        switch self {
        case .connect: return "connect"
        case .connectResponse: return "connectResponse"
        case .pushTopics: return "pushTopics"
        case .pushNotification: return "pushNotification"
        case .pushNotificationResponse: return "pushNotificationResponse"
        case .keepAlive: return "keepAlive"
        case .keepAliveAck: return "keepAliveAck"
        case .noStorage: return "noStorage"
        case .flush: return "flush"
        }
    }
}

extension BinaryInteger {
    func decompose() -> Data {
        var bytes: [UInt8] = []
        var scratch = self
        for _ in 0..<MemoryLayout<Self>.size {
            bytes.append(UInt8(scratch & 0xff))
            scratch = scratch >> 8
        }
        return Data(bytes.reversed())
    }
}

// https://github.com/mfrister/pushproxy/blob/master/doc/apple-push-protocol-ios5-lion.md
public struct APSWriter {
    public init(data: Data = Data()) {
        self.data = data
    }
    
    public var data: Data = Data()
    
    internal mutating func write(command: APSCommand) {
        data.append(command.rawValue)
    }
    
    /// Inserts the payload size after the command, once all fields have been written
    internal mutating func writeTotalSize() {
        data.insert(contentsOf: UInt32(data.count - 1).decompose(), at: 1)
    }
    
    internal mutating func write(payloadSize: UInt16) {
        data.append(payloadSize.decompose())
    }
    
    internal mutating func write(field: UInt8, data: Data) {
        self.data.append(field)
        self.data.append(UInt16(data.count).decompose())
        self.data.append(data)
    }
    
    public mutating func write(payload: APSPayload) {
        write(command: payload.command)
        for (field, data) in payload.fields {
            write(field: field, data: data)
        }
        writeTotalSize()
    }
}

public struct APSReader {
    @_disfavoredOverload
    public init(data: Data) {
        self.init(data: data)
    }
    
    internal init(data: Data, command: UInt8 = 0, size: UInt32 = 0, fields: [UInt8 : Data] = [:]) {
        self.data = data
        self.command = command
        self.size = size
        self.fields = fields
    }
    
    public var data: Data
    
    public var command: UInt8        = 0
    public var size: UInt32          = 0
    public var fields: [UInt8: Data] = [:]
    
    public mutating func read() {
        command = data[0]
        size = data[1...4].reversed().withUnsafeBytes { bytes in
            bytes.load(as: UInt32.self)
        }
        var fieldData = data[5..<(5 + size)]
        while !fieldData.isEmpty {
            let startIndex = fieldData.startIndex
            let command = fieldData[startIndex]
            let sizeRange = fieldData.index(after: startIndex)...fieldData.index(startIndex, offsetBy: 2)
            let size: UInt16 = fieldData[sizeRange].load()
            let fieldsStart = fieldData.index(after: sizeRange.upperBound)
            let fieldsStop = fieldsStart..<(fieldData.index(fieldsStart, offsetBy: Int(size)))
            fields[command] = fieldData[fieldsStop]
            fieldData = fieldData[fieldsStop.upperBound...]
        }
    }
}

extension Data {
    func load<P: BinaryInteger>() -> P {
        reversed().withUnsafeBytes { bytes in
            bytes.load(as: P.self)
        }
    }
}

public struct APSPayload {
    public init(command: APSCommand, fields: [UInt8 : Data] = [:]) {
        self.command = command
        self.fields = fields
    }
    
    public var command: APSCommand
    public var fields: [UInt8: Data]
}

public struct APSConnectResponse {
    public init?(payload: APSPayload) {
        guard payload.command == .connectResponse else {
            return nil
        }
        ok = payload.fields[1]?.first == 0
        pushToken = payload.fields[3]
        maxMessageSize = payload.fields[4]?.load()
        field5 = payload.fields[5]?.load()
        capabilities = payload.fields[6]?.load()
        largeMessageSize = payload.fields[8]?.load()
        serverTime = payload.fields[10]?.load()
        countryCode = payload.fields[11]?.load()
    }
    
    public var ok: Bool
    public var pushToken: Data?
    public var maxMessageSize: UInt16?
    public var field5: UInt16?
    public var capabilities: UInt32?
    public var largeMessageSize: UInt16?
    public var serverTime: UInt64?
    public var countryCode: UInt16?
}

private func sha1(_ string: String) -> Data {
    var hasher = Insecure.SHA1()
    hasher.update(data: Data(string.utf8))
    return Data(hasher.finalize())
}

public struct APSPushTopicsRequest {
    public var enabledTopics: [String]
    public var disabledTopics: [String]
    
    func write(to writer: inout APSWriter) {
        writer.write(command: .pushTopics)
        for enabledTopic in enabledTopics.lazy.map(sha1(_:)) {
            writer.write(field: 2, data: enabledTopic)
        }
        for disabledTopic in disabledTopics.lazy.map(sha1(_:)) {
            writer.write(field: 2, data: disabledTopic)
        }
        writer.writeTotalSize()
    }
}

extension String {
    subscript(_ i: Int) -> Character {
        self[index(startIndex, offsetBy: i)]
    }
    
    subscript(_ p: ClosedRange<Int>) -> Substring {
        self[index(startIndex, offsetBy: p.lowerBound)...index(startIndex, offsetBy: p.upperBound)]
    }
}

public extension Data {
    func hexEncodedString() -> String {
        map { String(format: "%02hhx", $0) }.joined()
    }
}

public extension Data {
    init?(hex: String) {
        // are you sane?
        guard hex.count.isMultiple(of: 2) else {
            return nil
        }
//        for i in stride(from: 0, to: hex.count, by: 2) {
//            let idx = hex.index(hex.startIndex, offsetBy: i)
//            let afterEnd = hex.index(idx, offsetBy: 2)
//            let byte = hex[idx..<afterEnd]
//            let char = UInt8(byte, radix: 16)
//        }
        let bytes = stride(from: 0, to: hex.count, by: 2)
            .map { idx in hex[idx...(idx + 1)] }
            .compactMap { byte in UInt8(byte, radix: 16) }
        // are we sane?
        guard (hex.count / 2) == bytes.count else {
            return nil
        }
        self = Data(bytes)
    }
}
