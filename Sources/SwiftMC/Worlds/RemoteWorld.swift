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

public class RemoteWorld: WorldProtocol {
    
    // Configuration
    public let server: SwiftMC
    public let host: String
    public let port: Int
    public let ipForward: Bool
    
    // Player infos
    internal var playerItems = [PlayerInfo.Item]()
    
    // Initialize a remote world
    internal init(server: SwiftMC, host: String, port: Int, ipForward: Bool = false) {
        self.server = server
        self.host = host
        self.port = port
        self.ipForward = ipForward
    }
    
    // Connect a client
    public func connect(client: ChannelWrapper) {
        // Get address
        if let address = getAddress() {
            // Ping the server
            pingWorld(from: client) { response in
                // Check if the server responded to ping
                if response != nil {
                    // Init the channel
                    self.makeBootstrap(for: client).connect(to: address).whenSuccess() { channel in
                        // Prepare handshake
                        var host = self.host
                        
                        // Add ip forward parameters
                        if self.ipForward {
                            host += "\0\(client.channel.remoteAddress?.ipAddress ?? "")\0\(client.getUUID().replacingOccurrences(of: "-", with: ""))"
                            if let properties = client.properties, let json = try? JSONSerialization.data(withJSONObject: properties, options: []), let string = String(bytes: json, encoding: .utf8) {
                                host += "\0\(string)"
                            }
                        }
                        
                        // Send handshake
                        client.remoteChannel?.send(packet: Handshake(protocolVersion: client.protocolVersion, host: host, port: Int16(self.port), requestedProtocol: 2))
                        
                        // Change protocol
                        client.remoteChannel?.prot = .LOGIN
                        
                        // Login request
                        client.remoteChannel?.send(packet: LoginRequest(data: client.getName()))
                    }
                } else {
                    // The server did not respond, may be offline
                    self.remoteHandle(packet: Kick(message: ChatMessage(text: "This server seems to be offline").toJSON() ?? "{}"), for: client)
                }
            }
        }
    }
    
    // Disconnect a client
    public func disconnect(client: ChannelWrapper) {
        // Disconnect from the remote world
        client.remoteChannel?.close()
        
        // Clear the tablist for the player
        client.send(packet: PlayerInfo(action: .remove_player, items: playerItems))
    }
    
    // Handle a packet from the client
    public func handle(packet: Packet, for client: ChannelWrapper) {
        // Don't forward packet if protocol is not the same
        if client.prot.name != client.remoteChannel?.prot.name {
            return
        }
        
        // Check packet type
        
        
        // Foward to the server
        client.remoteChannel?.send(packet: packet)
    }
    
    // Handle a packet from the remote world
    internal func remoteHandle(packet: Packet, for client: ChannelWrapper) {
        // Check packet type
        if let setCompression = packet as? SetCompression {
            remoteHandle(setCompression: setCompression, for: client)
            return
        } else if let encryptionRequest = packet as? EncryptionRequest {
            remoteHandle(encryptionRequest: encryptionRequest, for: client)
            return
        } else if let loginSuccess = packet as? LoginSuccess {
            remoteHandle(loginSuccess: loginSuccess, for: client)
            return
        } else if let login = packet as? Login, client.receivedLogin {
            remoteHandle(login: login, for: client)
            return
        } else if let kick = packet as? Kick {
            if remoteHandle(kick: kick, for: client) {
                return
            }
        } else if let playerInfo = packet as? PlayerInfo {
            remoteHandle(playerInfo: playerInfo, for: client)
        }
        
        // Foward to client
        client.send(packet: packet)
    }
    
    internal func remoteHandle(setCompression: SetCompression, for client: ChannelWrapper) {
        // Set threshold
        client.remoteChannel?.threshold = setCompression.threshold
    }
    
    internal func remoteHandle(encryptionRequest: EncryptionRequest, for client: ChannelWrapper) {
        // Check that our client is supporting premium
        guard client.onlineMode, let accessToken = client.accessToken, #available(iOS 10.0, tvOS 10.0, macOS 10.12, watchOS 3.0, *) else {
            remoteHandle(packet: Kick(message: ChatMessage(text: "Online mode is required on this server. Be sure to be in online mode and have installed SwiftMCPremium to allow client communication.").toJSON() ?? "{}"), for: client)
            return
        }
        
        // Generate a shared key
        var sharedKey = [UInt8]()
        for _ in 0 ..< 16 {
            sharedKey.append(UInt8.random(in: 0 ..< 255))
        }
        
        // Get idBytes
        var idBytes = [UInt8]()
        if !encryptionRequest.serverId.isEmpty, let idData = encryptionRequest.serverId.data(using: .utf8) {
            idBytes = [UInt8](idData)
        }
        
        // Get the encoded hash
        let encodedHash = Data(Digest.sha1(idBytes + sharedKey + encryptionRequest.publicKey)).toSignedHexString()
        
        // Verify identity with Mojang
        MojangJoin(accessToken: accessToken, selectedProfile: client.getUUID().replacingOccurrences(of: "-", with: ""), serverId: encodedHash).fetch { result in
            if result, let secKey = EncryptionManager.getSecKey(from: Data(encryptionRequest.publicKey)), let encodedKey = EncryptionManager.encrypt(content: Data(sharedKey) as CFData, publicKey: secKey, usingAlgorithm: .rsaEncryptionPKCS1), let encodedToken = EncryptionManager.encrypt(content: Data(encryptionRequest.verifyToken) as CFData, publicKey: secKey, usingAlgorithm: .rsaEncryptionPKCS1) {
                // Client is authentificated
                client.remoteChannel?.send(packet: EncryptionResponse(sharedSecret: [UInt8](encodedKey as Data), verifyToken: [UInt8](encodedToken as Data)), sharedKey: sharedKey)
            } else {
                // Invalid session
                self.remoteHandle(packet: Kick(message: ChatMessage(text: "Invalid session!").toJSON() ?? "{}"), for: client)
            }
        }
    }
    
    internal func remoteHandle(loginSuccess: LoginSuccess, for client: ChannelWrapper) {
        // Store success and change to game protocol
        client.remoteChannel?.name = loginSuccess.username
        client.remoteChannel?.uuid = loginSuccess.uuid
        client.remoteChannel?.prot = .GAME
    }
    
    internal func remoteHandle(login: Login, for client: ChannelWrapper) {
        // Send an immediate respawn if required
        if client.protocolVersion >= ProtocolConstants.minecraft_1_15 {
            client.send(packet: GameState(reason: GameState.immediate_respawn, value: login.normalRespawn ? 0 : 1))
        }
        
        // Convert to respawn packet
        if client.lastDimmension == login.dimension {
            client.send(packet: Respawn(dimension: login.dimension >= 0 ? -1 : 0, hashedSeed: login.seed, difficulty: login.difficulty, gameMode: login.gameMode, levelType: login.levelType))
        }
        client.send(packet: Respawn(dimension: login.dimension, hashedSeed: login.seed, difficulty: login.difficulty, gameMode: login.gameMode, levelType: login.levelType))
        client.lastDimmension = login.dimension
    }
    
    internal func remoteHandle(kick: Kick, for client: ChannelWrapper) -> Bool {
        // Check if kick reason is because if forward
        if kick.message.contains("IP forwarding") {
            // Reconnect using ip forwarding
            client.goTo(world: RemoteWorld(server: server, host: host, port: port, ipForward: true))
            return true
        }
        
        // Reconnect to default server, if not self
        if let main = client.server.worlds.first, main.getName() != getName() {
            client.goTo(world: main)
            client.sendMessage(message: ChatColor.red + "Disconnected: \(ChatMessage.decode(from: kick.message)?.toString() ?? kick.message)")
            return true
        }
        return false
    }
    
    internal func remoteHandle(playerInfo: PlayerInfo, for client: ChannelWrapper) {
        // Iterate players
        for item in playerInfo.items {
            // Get the player
            let currentPlayer = getPlayer(uuid: item.uuid ?? "")
            
            // Check the action
            if playerInfo.action == .add_player {
                // Check that player doesn't already exist
                if currentPlayer == nil {
                    // Add it
                    playerItems.append(item)
                }
            } else if playerInfo.action == .remove_player {
                // Remove the player from the list
                playerItems.removeAll(where: { $0.uuid == item.uuid })
            }
        }
    }
    
    // Ping server
    public func pingWorld(from client: ChannelWrapper, completionHandler: @escaping (ServerInfo?) -> ()) {
        // Get address
        if let address = getAddress() {
            // Ping
            let reuseAddrOpt = ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR)
            ClientBootstrap(group: client.server.eventLoopGroup)
                .channelOption(reuseAddrOpt, value: 1)
                .channelInitializer { channel in
                    // Create objects
                    let decoder = MinecraftDecoder(server: false)
                    let encoder = MinecraftEncoder(server: false)
                    let wrapper = ChannelWrapper(id: self.generateId(), server: client.server, channel: channel, decoder: decoder, encoder: encoder, prot: .HANDSHAKE, protocolVersion: client.protocolVersion)
                    
                    // Add client to list
                    client.pingChannel = wrapper
                    
                    // Add then to pipeline
                    return channel.pipeline.addHandlers([
                        ByteToMessageHandler(decoder),
                        MessageToByteHandler(encoder),
                        RemoteWorldPingHandler(channelWrapper: client, completionHandler: completionHandler)
                    ])
                }
                .connect(to: address)
                .whenComplete { result in
                    if (try? result.get()) != nil {
                        // Send handshake
                        client.pingChannel?.send(packet: Handshake(protocolVersion: client.protocolVersion, host: self.host, port: Int16(self.port), requestedProtocol: 1))
                        
                        // Change protocol
                        client.pingChannel?.prot = .STATUS
                        
                        // Login request
                        client.pingChannel?.send(packet: StatusRequest())
                    } else {
                        // Server not found
                        completionHandler(nil)
                    }
                }
        }
    }
    
    public func getName() -> String {
        return "\(host):\(port)"
    }
    
    public func getType() -> WorldType {
        return .remote
    }
    
    public func getPlayers() -> [Player] {
        return playerItems
    }
    
    public func getAddress() -> SocketAddress? {
        return try? SocketAddress.makeAddressResolvingHost(host, port: port)
    }
    
    public func load() {
        // Nothing to load for remote worlds
    }
    
    public func save() {
        // Nothing to save too
    }
    
    public func getChunk(x: Int32, z: Int32) -> WorldChunk {
        // Empty chunk
        return WorldChunk(x: x, z: z)
    }
    
    // Get a new session id
    internal func generateId() -> Int32 {
        return Int32.random(in: Int32.min ... Int32.max)
    }
    
    // Initialize a client channel
    internal func makeBootstrap(for client: ChannelWrapper) -> ClientBootstrap {
        let reuseAddrOpt = ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR)
        return ClientBootstrap(group: client.server.eventLoopGroup)
            .channelOption(reuseAddrOpt, value: 1)
            .channelInitializer { channel in
                // Create objects
                let decoder = MinecraftDecoder(server: false)
                let encoder = MinecraftEncoder(server: false)
                let wrapper = ChannelWrapper(id: self.generateId(), server: client.server, channel: channel, decoder: decoder, encoder: encoder, prot: .HANDSHAKE, protocolVersion: client.protocolVersion)
                
                // Add client to list
                client.remoteChannel = wrapper
                
                // Add then to pipeline
                return channel.pipeline.addHandlers([
                    ByteToMessageHandler(decoder),
                    MessageToByteHandler(encoder),
                    RemoteWorldHandler(channelWrapper: client)
                ])
            }
    }
    
    // Remote world reader
    internal class RemoteWorldHandler: ChannelInboundHandler, ChannelHandler {
        
        // Requirements
        public typealias InboundIn = Packet
        public typealias OutboundOut = Packet
        
        // Variables
        let channelWrapper: ChannelWrapper
        var handler: PacketHandler?
        
        // Initializer
        init(channelWrapper: ChannelWrapper) {
            self.channelWrapper = channelWrapper
            self.channelWrapper.remoteChannel?.handler = self
        }
        
        // Read a packet from remote world
        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            // Read wrapper
            let packet = unwrapInboundIn(data)
            
            // Check for debug
            if channelWrapper.server.configuration.debug {
                channelWrapper.server.log("WORLD -> SERVER: \(packet.toString())")
            }
            
            // Get remote world
            if let world = channelWrapper.world as? RemoteWorld {
                world.remoteHandle(packet: packet, for: channelWrapper)
            }
        }
        
    }
    
    internal class RemoteWorldPingHandler: ChannelInboundHandler, ChannelHandler {
        
        // Requirements
        public typealias InboundIn = Packet
        public typealias OutboundOut = Packet
        
        // Variables
        let channelWrapper: ChannelWrapper
        var handler: PacketHandler?
        var completionHandler: (ServerInfo?) -> ()
        
        // Initializer
        init(channelWrapper: ChannelWrapper, completionHandler: @escaping (ServerInfo?) -> ()) {
            self.channelWrapper = channelWrapper
            self.completionHandler = completionHandler
            self.channelWrapper.pingChannel?.handler = self
        }
        
        // Read a packet from remote world
        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            // Read wrapper
            let packet = unwrapInboundIn(data)
            
            // Check for debug
            if channelWrapper.server.configuration.debug {
                channelWrapper.server.log("WORLD -> SERVER: \(packet.toString())")
            }
            
            // Get remote world
            if let response = packet as? StatusResponse {
                completionHandler(ServerInfo.decode(from: response.response))
            }
        }
        
    }
    
}
