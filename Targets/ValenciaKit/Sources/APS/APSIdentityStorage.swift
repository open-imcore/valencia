//
//  APSIdentityStorage.swift
//  ValenciaKit
//
//  Created by Eric Rabil on 10/18/22.
//  Copyright © 2022 tuist.io. All rights reserved.
//

import Foundation

extension KeyedDecodingContainerProtocol {
    func decodeUUIDString(forKey key: Key) throws -> UUID {
        guard let uuid = UUID(uuidString: try decode(String.self, forKey: key)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: codingPath + [key], debugDescription: "malformed UUID"))
        }
        return uuid
    }
}

public struct APSActivationInfo: Codable {
    public init(activationRandomness: UUID = UUID(), buildVersion: String = "21G83", productVersion: String = "12.5.1", deviceClass: String = "MacOS", serialNumber: String = "0000000000", productType: String = "MacBookPro18,1", udid: UUID = UUID(), activationState: String = "Unactivated") {
        self.activationRandomness = activationRandomness
        self.buildVersion = buildVersion
        self.productVersion = productVersion
        self.deviceClass = deviceClass
        self.serialNumber = serialNumber
        self.productType = productType
        self.udid = udid
        self.activationState = activationState
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(activationRandomness.uuidString, forKey: .activationRandomness)
        try container.encode(buildVersion, forKey: .buildVersion)
        try container.encode(productVersion, forKey: .productVersion)
        try container.encode(deviceClass, forKey: .deviceClass)
        try container.encode(serialNumber, forKey: .serialNumber)
        try container.encode(productType, forKey: .productType)
        try container.encode(udid.uuidString, forKey: .udid)
        try container.encode(activationState, forKey: .activationState)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.activationRandomness = try container.decodeUUIDString(forKey: .activationRandomness)
        self.buildVersion = try container.decode(String.self, forKey: .buildVersion)
        self.productVersion = try container.decode(String.self, forKey: .productVersion)
        self.deviceClass = try container.decode(String.self, forKey: .deviceClass)
        self.serialNumber = try container.decode(String.self, forKey: .serialNumber)
        self.productType = try container.decode(String.self, forKey: .productType)
        self.udid = try container.decodeUUIDString(forKey: .udid)
        self.activationState = try container.decode(String.self, forKey: .activationState)
    }
    
    public var activationRandomness: UUID = UUID()
    public var buildVersion: String = "21G83"
    public var productVersion: String = "12.5.1"
    public var deviceClass: String = "MacOS"
    public var serialNumber: String = "0000000000"
    public var productType: String = "MacBookPro18,1"
    public var udid: UUID = UUID()
    public var activationState: String = "Unactivated"
    
    private enum CodingKeys: String, CodingKey {
        case activationRandomness = "ActivationRandomness"
        case buildVersion = "BuildVersion"
        case productVersion = "ProductVersion"
        case deviceClass = "DeviceClass"
        case serialNumber = "SerialNumber"
        case productType = "ProductType"
        case udid = "UniqueDeviceID"
        case activationState = "ActivationState"
    }
}

public struct APSPushToken: Codable {
    public init(token: Data, issuedAt: Date, identity: UUID) {
        self.token = token
        self.issuedAt = issuedAt
        self.identity = identity
    }
    
    public var token: Data
    public var issuedAt: Date
    public var identity: UUID
    
    private enum CodingKeys: String, CodingKey {
        case token = "Token"
        case issuedAt = "IssuedAt"
        case identity = "Identity"
    }
}

@_silgen_name("SecIdentityCreate")
func SecIdentityCreate(_ alloc: CFAllocator!, cert: SecCertificate, key: SecKey) -> SecIdentity

public class APSIdentity: Codable {
    public var certificate: Data?
    public var publicKey: Data?
    public var privateKey: Data?
    public var privateKeyAttrs: Data?
    public var activation: APSActivationInfo = APSActivationInfo()
    public var pushToken: APSPushToken?
    
    func parseKeyAttrs() -> CFDictionary? {
        guard let privateKeyAttrs = privateKeyAttrs else {
            return nil
        }
        return try? PropertyListSerialization.propertyList(from: privateKeyAttrs, format: nil) as? NSDictionary
    }
    
    func createSecKey() -> SecKey? {
        guard let privateKey = privateKey else {
            return nil
        }
        return SecKeyCreateWithData(privateKey as CFData, parseKeyAttrs() ?? ([:] as CFDictionary), nil)
    }
    
    func createSecCertificate() -> SecCertificate? {
        guard let certificate = certificate else {
            return nil
        }
        return SecCertificateCreateWithData(nil, certificate as CFData)
    }
    
    public func createSecIdentity() -> SecIdentity? {
        guard let key = createSecKey(), let cert = createSecCertificate() else {
            return nil
        }
        return SecIdentityCreate(nil, cert: cert, key: key)
    }
    
    private enum CodingKeys: String, CodingKey {
        case certificate = "Certificate"
        case publicKey = "PublicKey"
        case privateKey = "PrivateKey"
        case privateKeyAttrs = "PrivateKeyAttributes"
        case activation = "ActivationInfo"
        case pushToken = "PushToken"
    }
}

public extension APSIdentity {
    func save() throws {
        try APSIdentityStorage.shared.save(self)
    }
    
    func record(pushToken: Data) throws {
        self.pushToken = APSPushToken(token: pushToken, issuedAt: .now, identity: activation.udid)
        try save()
    }
}

public class APSIdentityStorage {
    public static let shared = APSIdentityStorage()
    
    private convenience init() {
        self.init(storageURL: URL(fileURLWithPath: ("~/Library/Valencia/Identities/APS" as NSString).expandingTildeInPath))
    }
    
    public init(storageURL: URL) {
        self.storageURL = storageURL
        
        try! FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
    }
    
    public let storageURL: URL
    
    private func url(for identity: UUID) -> URL {
        storageURL.appendingPathComponent(identity.uuidString).appendingPathExtension("plist")
    }
    
    private func url(for identity: APSIdentity) -> URL {
        url(for: identity.activation.udid)
    }
    
    public func loadIdentityIDs() -> [UUID] {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: storageURL.path) else {
            return []
        }
        return contents.compactMap { UUID(uuidString: String($0.split(separator: ".")[0])) }
    }
    
    public func loadIdentities() -> [UUID: APSIdentity] {
        loadIdentityIDs().reduce(into: [:]) { dict, id in
            do {
                dict[id] = try load(id)
            } catch {
                // TODO: log
            }
        }
    }
    
    public func save(_ identity: APSIdentity) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(identity)
        try data.write(to: url(for: identity))
    }
    
    public func load(_ identity: UUID) throws -> APSIdentity? {
        let url = url(for: identity)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try PropertyListDecoder().decode(APSIdentity.self, from: data)
    }
    
    public func createIdentity() throws -> APSIdentity {
        let identity = APSIdentity()
        try save(identity)
        return identity
    }
    
    public func loadIdentity(_ callback: @escaping (Result<APSIdentity, Error>) -> ()) {
        let identities = loadIdentities()
        if let identity = identities.values.first(where: { $0.publicKey != nil && $0.privateKey != nil && $0.certificate != nil }) {
            return callback(.success(identity))
        }
        do {
            var identity = try createIdentity()
            
            APSPuppeteer.shared.generateClientIdentity(overrides: try identity.activation.toFoundation() as! [String: NSObject]) { keys, identityData in
                guard let (pub, pri, kc, name) = keys else {
                    preconditionFailure()
                }
                guard let (secIdentity, cert) = identityData else {
                    preconditionFailure()
                }
                identity.certificate = SecCertificateCopyData(cert) as Data
                identity.publicKey = SecKeyCopyExternalRepresentation(pub, nil) as Data?
                identity.privateKey = SecKeyCopyExternalRepresentation(pri, nil) as Data?
                identity.privateKeyAttrs = SecKeyCopyAttributes(pri).map { try! PropertyListSerialization.data(fromPropertyList: $0, format: .binary, options: 0) }
                try! self.save(identity)
                callback(.success(identity))
//                identity.privateKey = SecKeyCopyExternalRepresentation(pri, nil) as Data
            }
        } catch {
            callback(.failure(error))
        }
    }
}

extension Encodable {
    func toFoundation() throws -> Any {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(self)
        return try PropertyListSerialization.propertyList(from: data, format: nil)
    }
}
