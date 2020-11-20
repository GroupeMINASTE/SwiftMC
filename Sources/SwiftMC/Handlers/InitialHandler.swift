/*
*  Copyright (C) 2020 Groupe MINASTE
*
* This program is free software; you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation; either version 2 of the License, or
* (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License along
* with this program; if not, write to the Free Software Foundation, Inc.,
* 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
*
*/

import Foundation
import NIO
import CryptoSwift

class InitialHandler: PacketHandler {
    
    var channel: ChannelWrapper?
    
    func connected(channel: ChannelWrapper) {
        self.channel = channel
    }
    
    func disconnected(channel: ChannelWrapper) {
        self.channel = nil
    }
    
    func shouldHandle(packet: Packet) -> Bool {
        return !(channel?.closing ?? true)
    }
    
    func handle(packet: Packet) {
        // Check packet type
        if let pingPacket = packet as? PingPacket {
            self.handle(pingPacket: pingPacket)
        }
        if let handshake = packet as? Handshake {
            self.handle(handshake: handshake)
        }
        if let statusRequest = packet as? StatusRequest {
            self.handle(statusRequest: statusRequest)
        }
        if let loginRequest = packet as? LoginRequest {
            self.handle(loginRequest: loginRequest)
        }
        if let encryptionResponse = packet as? EncryptionResponse {
            self.handle(encryptionResponse: encryptionResponse)
        }
    }
    
    func handle(pingPacket: PingPacket) {
        // Send back
        channel?.close(packet: pingPacket)
    }
    
    func handle(handshake: Handshake) {
        if let channel = channel {
            // Save
            channel.protocolVersion = handshake.protocolVersion
            
            // Remove FML from host
            if handshake.host.contains("\0") {
                let split = handshake.host.split(separator: "\0", maxSplits: 2, omittingEmptySubsequences: true)
                handshake.host = String(split[0])
            }
            
            // Remove . at the end (dns record)
            if !handshake.host.isEmpty && handshake.host.last == "." {
                let _ = handshake.host.removeLast()
            }
            
            // Check request protocol
            switch handshake.requestedProtocol {
                
            case 1:
                // Ping
                channel.prot = .STATUS
            case 2:
                // Login
                channel.prot = .LOGIN
                
                // Check server/client version
                if !ProtocolConstants.supported_versions_ids.contains(handshake.protocolVersion) {
                    if handshake.protocolVersion > channel.server.configuration.protocolVersion {
                        disconnect(reason: "Outdated server!")
                    } else {
                        disconnect(reason: "Outdated client!")
                    }
                }
            default:
                return
                
            }
        }
    }
    
    func handle(statusRequest: StatusRequest) {
        // Send packet
        if let channel = channel, let json = channel.server.getServerInfo(preferedProtocol: channel.protocolVersion).toJSON() {
            channel.send(packet: StatusResponse(response: json))
        }
    }
    
    func handle(loginRequest: LoginRequest) {
        if let channel = channel {
            // Check name
            if loginRequest.data.contains(".") || loginRequest.data.count > 16 {
                // Invalid name
                disconnect(reason: "Invalid name!")
                return
            }
            
            // Save name
            channel.name = loginRequest.data
            
            // Check number of slots
            let connected = channel.server.players.count
            let slots = channel.server.configuration.slots
            if connected >= slots {
                // To many people
                disconnect(reason: "Too many people are connected, try again later!")
                return
            }
            
            // Check not already connected
            if channel.server.players.contains(where: { $0.getName().lowercased() == loginRequest.data.lowercased() }) {
                // Already connected
                disconnect(reason: "You are already connected!")
                return
            }
            
            // Check for online mode
            if channel.server.mode == .online || channel.server.mode == .auto {
                if EncryptionManager.supportsEncryption(), #available(iOS 10.0, tvOS 10.0, macOS 10.12, watchOS 3.0, *) {
                    // Send encryption packet
                    let encryptionRequest = EncryptionManager.generateRequest()
                    channel.send(packet: encryptionRequest)
                    channel.encryptionRequest = encryptionRequest
                } else if channel.server.mode == .auto {
                    // End login
                    finish()
                } else {
                    // Encryption not supported
                    disconnect(reason: "Encryption is not supported on this server!")
                }
            } else {
                // End login
                finish()
            }
        }
    }
    
    func handle(encryptionResponse: EncryptionResponse) {
        if let channel = channel, let username = channel.name, let encryptionRequest = channel.encryptionRequest, #available(iOS 10.0, tvOS 10.0, macOS 10.12, watchOS 3.0, *) {
            // Prepare data
            guard let sharedKey = EncryptionManager.getSecret(response: encryptionResponse, request: encryptionRequest), let idBytes = encryptionRequest.serverId.data(using: .utf8), let publicKey = EncryptionManager.keys?.publicKey, let publicKeyData = EncryptionManager.getData(for: publicKey) else {
                // Error
                disconnect(reason: "Failed to authenticate your account!")
                return
            }
            
            // Save shared key
            channel.sharedKey = sharedKey
            channel.decoder.iv = sharedKey
            channel.encoder.iv = sharedKey
            
            // Get the encoded hash
            let encodedHash = Data(Digest.sha1([UInt8](idBytes) + [UInt8](sharedKey) + [UInt8](publicKeyData))).toSignedHexString()
            
            // Complete the request
            MojangHasJoined(username: username, serverId: encodedHash).fetch { dict in
                // Check data validity
                if let dict = dict {
                    // Read data
                    channel.name = dict["name"] as? String ?? channel.name
                    channel.uuid = (dict["id"] as? String)?.addSeparatorUUID() ?? channel.uuid
                    channel.properties = dict["properties"] as? [[String: Any]]
                    
                    // Set as online mode player
                    channel.onlineMode = true
                    
                    // End login
                    self.finish()
                } else if channel.server.mode == .auto {
                    // End login
                    self.finish()
                } else {
                    // Error
                    self.disconnect(reason: "Invalid session!")
                }
            }
        } else {
            // Encryption not supported
            disconnect(reason: "Encryption is not supported on this server!")
        }
    }
    
    func finish() {
        // Set offline UUID if required
        if channel?.uuid == nil {
            channel?.uuid = channel?.name?.getUUID()
        }
        
        // Check that name and uuid are set
        if let name = channel?.name, let uuid = channel?.uuid {
            // Enable threshold
            channel?.send(packet: SetCompression(threshold: 256), threshold: 256)
            
            // Send success packet and switch to game protocol
            channel?.server.log("Authenticating player \(name)... (\(uuid))")
            channel?.send(packet: LoginSuccess(uuid: uuid, username: name), newProtocol: .GAME)
            channel?.setHandler(handler: GameHandler())
        } else {
            // Disconnect
            disconnect(reason: "An error occurred while authentification")
        }
    }
    
    func disconnect(reason: String) {
        channel?.server.log("Client disconnected: \(reason)")
        channel?.kick(reason: reason)
    }
    
}
