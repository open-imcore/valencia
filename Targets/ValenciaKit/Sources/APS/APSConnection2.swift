//
//  APSConnection2.swift
//  ValenciaKit
//
//  Created by Eric Rabil on 10/22/22.
//  Copyright © 2022 tuist.io. All rights reserved.
//

import Foundation
import Logging

private let logger = Logger(label: "com.ericrabil.valencia.aps.connection")

extension Optional {
    var isPresent: String {
        switch self {
        case .none: return "NO"
        case .some: return "YES"
        }
    }
}

public class APSConnection: APSSocketDelegate, APSSocketDelegateParsedPayloadReceiving {
    public func socket(connected socket: APSSocketProtocol) {
        let token = identity.pushToken?.token
        logger.info("Socket connected. Sending connect payload. Has push token? \(token.isPresent)")
        var payload = APSPayload(command: .connect, fields: [2: Data([1])])
        if let token = token {
            payload.fields[1] = token
        }
        socket.send(payload)
    }
    
    public func socket(disconnected socket: APSSocketProtocol) {
        logger.info("Socket disconnected.")
    }
    
    public func identity(for socket: APSSocketProtocol) -> SecIdentity? {
        identity.createSecIdentity()
    }
    
    public func socket(_ socket: APSSocketProtocol, received payload: APSPayload) {
        switch payload.command {
        case .connectResponse:
            guard let response = APSConnectResponse(payload: payload) else {
                logger.error("Failed to parse connect response!")
                return
            }
            let token = response.pushToken
            logger.info("Received connect response from courier. Received push token? \(token.isPresent)")
            if let token = token {
                try! identity.record(pushToken: token)
            }
            var writer = APSWriter()
            APSPushTopicsRequest(enabledTopics: ["com.apple.idmsauth"], disabledTopics: []).write(to: &writer)
            socket.send(writer.data)
        default:
            break
        }
    }
    
    let identity: APSIdentity
    let socket: APSSocket
    
    public init(identity: APSIdentity) {
        self.identity = identity
        self.socket = APSSocket(hostName: "43-courier.push.apple.com", port: 5223)
        self.socket.delegate = self
    }
    
    public func connect() {
        socket.connect()
    }
}
