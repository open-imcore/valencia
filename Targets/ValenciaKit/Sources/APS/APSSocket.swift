//
//  APSSocket.swift
//  ValenciaKit
//
//  Created by Eric Rabil on 10/22/22.
//  Copyright © 2022 tuist.io. All rights reserved.
//

import Foundation
import Logging

public protocol APSSocketProtocol {
    var delegate: APSSocketDelegate? { get set }
    
    func connect()
    func send(_ payload: APSPayload)
    func send(_ data: Data)
}

public protocol APSSocketDelegate: AnyObject {
    func socket(connected socket: APSSocketProtocol)
    func socket(disconnected socket: APSSocketProtocol)
    func identity(for socket: APSSocketProtocol) -> SecIdentity?
}

public protocol APSSocketDelegateRawPayloadReceiving: APSSocketDelegate {
    func socket(_ socket: APSSocketProtocol, finishedReading reader: APSReader)
}

public protocol APSSocketDelegateParsedPayloadReceiving: APSSocketDelegate {
    func socket(_ socket: APSSocketProtocol, received payload: APSPayload)
}

private let logger = Logger(label: "com.ericrabil.valencia.aps.socket")

extension SecCertificate {
    func copyHexSerialNumber() -> String? {
        SecCertificateCopySerialNumberData(self, nil).map {
            ($0 as Data).hexEncodedString()
        }
    }
}

extension SecIdentity {
    var certificate: SecCertificate? {
        var cert: SecCertificate?
        SecIdentityCopyCertificate(self, &cert)
        return cert
    }
}

public class APSSocket: NSObject, URLSessionStreamDelegate, URLSessionTaskDelegate, StreamDelegate, APSSocketProtocol {
    public init(hostName: String, port: Int, delegate: APSSocketDelegate? = nil) {
        self.hostName = hostName
        self.port = port
        self.delegate = delegate
    }
    
    public let hostName: String
    public let port: Int
    var stream: URLSessionStreamTask?
    
    public weak var delegate: APSSocketDelegate?
    
    public func connect() {
        if stream != nil {
            preconditionFailure("USE ME ONCE.")
        }
        logger.info("About to connect to APS using hostname \(hostName) port \(port)")
        let task = URLSession.shared.streamTask(withHostName: hostName, port: port)
        stream = task
        task.delegate = self
        task.startSecureConnection()
        task.resume()
        task.captureStreams()
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
        logger.debug("Connection upgraded to stream task")
        self.inputStream = inputStream
        self.outputStream = outputStream
        schedule(inputStream)
        schedule(outputStream)
        inputStream.open()
        outputStream.open()
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        logger.info("Received auth challenge from courier.")
        switch delegate?.identity(for: self) {
        case .some(let identity):
            logger.info("Responding to auth challenge with identity serial no. \(identity.certificate?.copyHexSerialNumber() ?? "nil")")
            let cred = URLCredential(identity: identity, certificates: nil, persistence: .none)
            completionHandler(.useCredential, cred)
        case .none:
            logger.error("Could not locate an identity to respond with for auth challenge.")
            completionHandler(.performDefaultHandling, .none)
        }
    }
    
    var outBuffer = Data()
    var inBuffer = Data()
    
    public func send(_ data: Data) {
        outBuffer += data
    }
    
    public func send(_ payload: APSPayload) {
        var writer = APSWriter()
        writer.write(payload: payload)
        logger.debug("Sending command \(payload.command.description) of size \(writer.data.count)")
        self.send(writer.data)
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
        let command = APSCommand(rawValue: reader.command)
        logger.debug("Received command \(reader.command) (\(command?.description ?? "unknown!")) of size \(reader.data.count)")
        if let delegate = delegate as? APSSocketDelegateRawPayloadReceiving {
            delegate.socket(self, finishedReading: reader)
        }
        if let delegate = delegate as? APSSocketDelegateParsedPayloadReceiving,
           let command = command {
            delegate.socket(self, received: APSPayload(command: command, fields: reader.fields))
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
    
    public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        print(aStream, eventCode)
        switch eventCode {
        case .hasSpaceAvailable:
            print("space!")
            self.hasSpace()
        case .openCompleted:
            print("opened!")
            if aStream === outputStream {
                delegate?.socket(connected: self)
            }
        case .endEncountered:
            print(aStream, "ended!")
            if aStream === inputStream {
                delegate?.socket(disconnected: self)
            }
        case .hasBytesAvailable:
            print("bytes!")
            self.hasBytes()
        default:
            print("??? \(eventCode.rawValue)")
        }
    }
}

