//
//  APSConnection.swift
//  ValenciaKit
//
//  Created by Eric Rabil on 10/18/22.
//  Copyright © 2022 tuist.io. All rights reserved.
//

import Foundation

public protocol APSConnectionProtocol {
    var delegate: Optional<any APSConnectionDelegate> { get set }
    
    func send(_ payload: APSPayload)
}

public protocol APSConnectionDelegate: AnyObject {
    func connection(disconnected connection: any APSConnectionProtocol)
    func connection(connected    connection: any APSConnectionProtocol)
    func connection(replaced     connection: any APSConnectionProtocol, replacement: any APSConnectionProtocol)
}

public protocol APSConnectionRawPayloadReceiving: AnyObject {
    func connection(_ connection:            any APSConnectionProtocol, finishedReading reader: APSReader)
}

public protocol APSConnectionParsedPayloadReceiving: AnyObject {
    func connection(_ connection:            any APSConnectionProtocol, received        payload: APSPayload)
}

private class APSConnectionDelegateStub: APSConnectionDelegate {
    static let shared = APSConnectionDelegateStub()
    
    func connection(disconnected connection: APSConnectionProtocol) {
        
    }
    
    func connection(connected connection: APSConnectionProtocol) {
        
    }
    
    func connection(replaced connection: APSConnectionProtocol, replacement: APSConnectionProtocol) {
        
    }
}

public class EphemeralAPSConnection: NSObject, URLSessionStreamDelegate, URLSessionTaskDelegate, StreamDelegate, APSConnectionProtocol {
    public init(identity: SecIdentity) {
        self.identity = identity
    }
    
    let identity: SecIdentity
    
    var stream: URLSessionStreamTask?
    
    public unowned var delegate: (any APSConnectionDelegate)?
    
    public func connect() {
        if stream != nil {
            preconditionFailure("USE ME ONCE.")
        }
        let task = URLSession.shared.streamTask(withHostName: "43-courier.push.apple.com", port: 5223)
        stream = task
        task.delegate = self
        task.startSecureConnection()
        task.resume()
        task.captureStreams()
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let cred = URLCredential(identity: identity, certificates: nil, persistence: .none)
        completionHandler(.useCredential, cred)
    }
    
    var inputStream: InputStream? {
        didSet {
            if let inputStream = inputStream {
                inputStream.delegate = self
            }
        }
    }
    var outputStream: OutputStream? {
        didSet {
            if let outputStream = outputStream {
                outputStream.delegate = self
            }
        }
    }
    
    private func schedule(_ stream: Stream) {
        stream.schedule(in: .main, forMode: .default)
    }
    
    public func urlSession(_ session: URLSession, streamTask: URLSessionStreamTask, didBecome inputStream: InputStream, outputStream: OutputStream) {
        self.inputStream = inputStream
        self.outputStream = outputStream
        schedule(inputStream)
        schedule(outputStream)
        inputStream.open()
        outputStream.open()
    }
    
    var outBuffer = Data()
    var inBuffer = Data()
    
    func write(_ data: Data) {
        outBuffer += data
    }
    
    func hasSpace() {
        guard !outBuffer.isEmpty else {
            return
        }
        outBuffer.withUnsafeBytes { bytes in
            let pointer = bytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
            switch outputStream!.write(pointer, maxLength: bytes.count) {
            case 0:
                print("WHAT THE FUCK?")
            case -1:
                print("WHAT THE FUCK?!")
            case let written:
                guard written > 0 else {
                    preconditionFailure("what the hell mama")
                }
                self.outBuffer.replaceSubrange(0..<written, with: Data())
                if self.outBuffer.isEmpty {
                    print("all done writing shit")
                }
            }
        }
    }
    
    let readBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
    var readData = Data()
    
    func read() {
        var reader = APSReader(data: readData)
        reader.read()
        guard let delegate = delegate else {
            return
        }
        if let delegate = delegate as? APSConnectionRawPayloadReceiving {
            delegate.connection(self, finishedReading: reader)
        }
        if let delegate = delegate as? APSConnectionParsedPayloadReceiving,
           let command = APSCommand(rawValue: reader.command) {
            delegate.connection(self, received: APSPayload(command: command, fields: reader.fields))
        }
    }
    
    func hasBytes() {
        switch inputStream!.read(readBuffer, maxLength: 1024) {
        case 0:
            print("need more reading!")
            readData += Data(UnsafeMutableBufferPointer(start: readBuffer, count: 1024))
            hasBytes()
        case -1:
            if inputStream?.streamError == nil {
                read()
            } else {
                print("shit broke", inputStream!.streamError)
            }
        case let bytes:
            guard bytes > 0 else {
                preconditionFailure("what the hell mama")
            }
            readData += Data(UnsafeMutableBufferPointer(start: readBuffer, count: bytes)[0..<bytes])
            if inputStream!.hasBytesAvailable {
                hasBytes()
            }
        }
    }
    
    public func send(_ payload: APSPayload) {
        var writer = APSWriter()
        writer.write(payload: payload)
        self.write(writer.data)
    }
    
    public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        print(aStream, eventCode)
        switch eventCode {
        case .hasSpaceAvailable:
            print("space!")
            self.hasSpace()
        case .openCompleted:
            print("opened!")
            if aStream === outputStream {
                delegate?.connection(connected: self)
            }
        case .endEncountered:
            print(aStream, "ended!")
            if aStream === inputStream {
                delegate?.connection(disconnected: self)
            }
        case .hasBytesAvailable:
            print("bytes!")
            self.hasBytes()
        default:
            print("??? \(eventCode.rawValue)")
        }
    }
}
