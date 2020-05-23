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

class LocalWorld: WorldProtocol {
    
    // Configuration
    public let server: SwiftMC
    public let name: String
    public let path: URL
    public let config: WorldConfiguration
    
    // World map
    private var regions: [WorldRegion]
    private var chunks: [WorldChunk]
    
    // Connected clients
    private var clients: [ChannelWrapper]
    
    // Initialize a remote world
    internal init(server: SwiftMC, name: String) {
        self.server = server
        self.name = name
        self.path = server.serverRoot.appendingPathComponent(name, isDirectory: true)
        self.config = WorldConfiguration()
        self.regions = []
        self.chunks = []
        self.clients = []
    }
    
    internal func connect(client: ChannelWrapper) {
        // Set a new local entity id
        client.id = generateId()
        
        // Add to clients
        clients.append(client)
        
        // Login player
        let login = Login(entityId: 1, gameMode: 1, dimension: 0, seed: 0, difficulty: 0, maxPlayers: 1, levelType: "default", viewDistance: 16, reducedDebugInfo: false, normalRespawn: true)
        
        // Check if a login was already handled
        if !client.receivedLogin {
            // Just send login
            client.send(packet: login)
        } else {
            // Send an immediate respawn if required
            if client.protocolVersion >= ProtocolConstants.minecraft_1_15 {
                client.send(packet: GameState(reason: GameState.immediate_respawn, value: login.normalRespawn ? 0 : 1))
            }
            
            // Convert to respawn packet
            if client.lastDimmension == login.dimension {
                client.send(packet: Respawn(dimension: login.dimension >= 0 ? -1 : 0, hashedSeed: login.seed, difficulty: login.difficulty, gameMode: login.gameMode, levelType: login.levelType))
            }
            client.send(packet: Respawn(dimension: login.dimension, hashedSeed: login.seed, difficulty: login.difficulty, gameMode: login.gameMode, levelType: login.levelType))
        }
        
        // Save current dimension
        client.lastDimmension = login.dimension
        
        // Get spawn location for player
        client.location = Location(world: self, x: Double(config.spawnX), y: Double(config.spawnY), z: Double(config.spawnZ), yaw: 0, pitch: 0)
        
        // Send chunks and position
        client.sendCurrentChunks()
        client.send(packet: client.getLocation().toPositionServerPacket())
        
        // Fire PlayerJoinEvent
        let event = PlayerJoinEvent(player: client, message: "\(ChatColor.green)[+] \(ChatColor.yellow)\(client.getName())")
        client.server.fireListeners(for: event)
        broadcast(packet: Chat(message: ChatMessage(text: event.message)))
        
        // Send PlayerInfo
        for player in clients {
            // Create the packet
            let packet = PlayerInfo(action: .add_player, items: [PlayerInfo.Item(uuid: player.uuid, username: player.name, properties: player.properties?.map({ properties in
                properties.map({ property in
                    property.value as? String ?? ""
                })
            }), gamemode: 0, ping: 0, displayname: nil)])
            
            // Send it
            player.getUUID() == client.getUUID() ? broadcast(packet: packet) : client.send(packet: packet)
        }
    }
    
    internal func disconnect(client: ChannelWrapper) {
        // Fire PlayerQuitEvent
        let event = PlayerQuitEvent(player: client, message: "\(ChatColor.red)[-] \(ChatColor.yellow)\(client.getName())")
        client.server.fireListeners(for: event)
        broadcast(packet: Chat(message: ChatMessage(text: event.message)))
        
        // Send PlayerInfo
        for player in clients {
            // Create the packet
            let packet = PlayerInfo(action: .remove_player, items: [PlayerInfo.Item(uuid: player.uuid)])
            
            // Send it
            player.getUUID() == client.getUUID() ? broadcast(packet: packet) : client.send(packet: packet)
        }
        
        // Remove client from current clients
        clients.removeAll(where: { current in
            current.id == client.id
        })
    }
    
    internal func handle(packet: Packet, for client: ChannelWrapper) {
        // Check packet type
        if let chat = packet as? Chat {
            handle(chat: chat, for: client)
        } else if let playerPosition = packet as? PlayerPosition {
            handle(playerPosition: playerPosition, for: client)
        } else if let playerPositionLook = packet as? PlayerPositionLook {
            handle(playerPositionLook: playerPositionLook, for: client)
        } else if let playerLook = packet as? PlayerLook {
            handle(playerLook: playerLook, for: client)
        }
    }
    
    internal func handle(chat: Chat, for client: ChannelWrapper) {
        // Fire PlayerChatEvent
        let event = PlayerChatEvent(player: client, message: chat.message, format: "\(ChatColor.aqua)[%@] \(ChatColor.reset)%@")
        client.server.fireListeners(for: event)
        broadcast(packet: Chat(message: ChatMessage(text: String(format: event.format, client.getName(), event.message))))
    }
    
    internal func handle(playerPosition: PlayerPosition, for client: ChannelWrapper) {
        // Forward
        handle(playerMoveTo: Location(world: self, x: playerPosition.x, y: playerPosition.y, z: playerPosition.z, yaw: client.getLocation().yaw, pitch: client.getLocation().pitch), for: client)
    }
    
    internal func handle(playerPositionLook: PlayerPositionLook, for client: ChannelWrapper) {
        // Forward
        handle(playerMoveTo: Location(world: self, x: playerPositionLook.x, y: playerPositionLook.y, z: playerPositionLook.z, yaw: playerPositionLook.yaw, pitch: playerPositionLook.pitch), for: client)
    }
    
    internal func handle(playerLook: PlayerLook, for client: ChannelWrapper) {
        // Forward
        handle(playerMoveTo: Location(world: self, x: client.getLocation().x, y: client.getLocation().y, z: client.getLocation().z, yaw: playerLook.yaw, pitch: playerLook.pitch), for: client)
    }
    
    internal func handle(playerMoveTo location: Location, for client: ChannelWrapper) {
        // Fire PlayerMoveEvent
        let event = PlayerMoveEvent(player: client, location: location)
        client.server.fireListeners(for: event)
        if !event.cancel {
            // Handle move
            client.location = event.to
            client.sendCurrentChunks()
        } else {
            // Cancel move
            
        }
    }
    
    public func pingWorld(from client: ChannelWrapper, completionHandler: @escaping (ServerInfo?) -> ()) {
        completionHandler(nil)
    }
    
    public func getName() -> String {
        return name
    }
    
    public func getType() -> WorldType {
        return .local
    }
    
    public func getPlayers() -> [Player] {
        return clients
    }
    
    public func generateId() -> Int32 {
        var id: Int32
        repeat {
            id = Int32.random(in: Int32.min ... Int32.max)
        } while server.getPlayer(id: id) != nil || getEntity(id: id) != nil
        return id
    }
    
    public func getEntity(id: Int32) -> Entity? {
        return clients.first(where: { $0.id == id })
    }
    
    internal func load() {
        // Start loading the world
        server.log("Start loading local world: \(name)")
        
        do {
            // Check if the world folder exists
            if !FileManager.default.fileExists(atPath: path.path) {
                // Create a folder
                server.log("Creating a new folder... (\(path.path))")
                try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true, attributes: nil)
            }
            
            // Read the configuration from the disk
            let level_dat = path.appendingPathComponent("level.dat")
            try config.read(from: level_dat)
            
            // Load main chunks
            let start = Date()
            let ev = server.eventLoopGroup.next()
            let promise = ev.makePromise(of: Date.self)
            ev.execute {
                // Parameters of the loading process
                let width = 10
                let spawn = Location(world: self, x: Double(self.config.spawnX), y: Double(self.config.spawnY), z: Double(self.config.spawnZ), yaw: 0, pitch: 0)
                let progressBar = ChatProgressBar(total: width * width, width: 50)
                
                // Iterate to load
                for x in 0 ..< width {
                    for z in 0 ..< width {
                        let chunkX = Int32(Int(spawn.x) >> 4 + x - width/2)
                        let chunkZ = Int32(Int(spawn.z) >> 4 + z - width/2)
                        self.loadChunk(x: chunkX, z: chunkZ) { _ in
                            // Update the progress bar
                            self.server.log(progressBar.increment())
                            if progressBar.isDone() {
                                promise.succeed(Date())
                            }
                        }
                    }
                }
            }
            
            // End of chunk loading
            let end = try promise.futureResult.wait()
            server.log("Loaded \(chunks.count) chunks in \(Int(end.timeIntervalSince(start))) seconds in local world: \(name)")
        } catch {
            // An error occurred loading the world
            server.logError("An error occurred loading local world: \(name)")
        }
    }
    
    public func save() {
        // Start saving the world
        server.log("Saving local world: \(name)")
        
        do {
            // Save the level.dat file
            try config.save(to: path.appendingPathComponent("level.dat"))
            
            // Save loaded regions
            // ...
        } catch {
            // An error occurred saving the world
            server.logError("An error occurred saving local world: \(name)")
        }
    }
    
    internal func getRegion(x: Int32, z: Int32) -> WorldRegion {
        // Return existing region if exists
        if let region = regions.first(where: { $0.x == x && $0.z == z }) {
            return region
        }
        
        // Init a new region
        let region = WorldRegion(world: self, x: x, z: z)
        regions.append(region)
        return region
    }
    
    public func getChunk(x: Int32, z: Int32) -> WorldChunk {
        // Return existing chunk if exists
        if let chunk = chunks.first(where: { $0.x == x && $0.z == z }) {
            return chunk
        }
        
        // Retrieve from a region
        if let chunk = getRegion(x: x >> 5, z: z >> 5).getChunk(x: x & (WorldRegion.region_size - 1), z: z & (WorldRegion.region_size - 1)) {
            chunks.append(chunk)
            return chunk
        }
        
        // Chunk did not load
        return WorldChunk(x: x, z: z)
    }
    
    public func loadChunk(x: Int32, z: Int32, completionHandler: @escaping (WorldChunk?) -> ()) {
        // Return existing chunk if exists
        if let chunk = chunks.first(where: { $0.x == x && $0.z == z }) {
            completionHandler(chunk)
            return
        }
        
        // Retrieve from a region
        let futureResult = getRegion(x: x >> 5, z: z >> 5).loadChunk(x: x & (WorldRegion.region_size - 1), z: z & (WorldRegion.region_size - 1))
        futureResult.whenSuccess({ chunk in
            self.chunks.append(chunk)
            completionHandler(chunk)
        })
        futureResult.whenFailure { error in
            completionHandler(nil)
        }
    }
    
    public func broadcast(packet: Packet) {
        // Send to all players
        clients.forEach { client in
            client.send(packet: packet)
        }
        
        // Check for a chat message to log it
        if let chat = packet as? Chat, let message = ChatMessage.decode(from: chat.message) {
            server.sendMessage(message: "[WORLD: \(getName())] \(message.toString())")
        }
    }
    
}

struct WorldError: Error {}
