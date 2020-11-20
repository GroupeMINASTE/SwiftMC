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

// Main class
public class SwiftMC: CommandSender {
    
    // Publics vars
    public let configuration: Configuration
    public let logger: (ChatMessage) -> ()
    public let serverRoot: URL
    public let port: Int
    public let mode: AuthentificationMode
    public var players: [Player] {
        get {
            return clients.filter { client in
                client.name != nil && client.uuid != nil
            }
        }
    }
    
    // Internal vars
    internal let eventLoopGroup: EventLoopGroup
    internal var serverChannel: Channel?
    internal var commands: [String: Command]
    internal var listeners: [EventListener]
    internal var clients: [ChannelWrapper]
    internal var generators: [WorldGenerator]
    public internal(set) var worlds: [WorldProtocol]
    public internal(set) var running: Bool = false
    public internal(set) var ready: Bool = false
    public internal(set) var startTime: Int64 = 0

    // Initializer
    public init(serverRoot: String = FileManager.default.currentDirectoryPath, logger: @escaping (ChatMessage) -> () = { print($0.toString(useAnsi: true)) }) {
        self.serverRoot = URL(fileURLWithPath: serverRoot, isDirectory: true)
        self.configuration = Configuration(serverRoot: self.serverRoot)
        self.logger = logger
        self.port = configuration.port
        self.mode = configuration.mode
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        self.commands = [:]
        self.listeners = []
        self.worlds = []
        self.clients = []
        self.generators = [
            OverworldGenerator(), SuperflatGenerator()
        ]
    }
    
    // Start server
    public func start() {
        // Start
        running = true
        log("Starting server...")
        log("Server root: \(serverRoot.path)")
        log("Selected mode: \(mode)")
        
        // Register basic commands
        log("Registering server commands...")
        registerCommand("stop", command: StopCommand())
        registerCommand("help", command: HelpCommand())
        registerCommand("chat", command: ChatCommand())
        registerCommand("world", command: WorldCommand())
        registerCommand("gamemode", command: GamemodeCommand())
        registerCommand("gm", command: GamemodeCommand())
        
        // Load worlds
        log("Loading worlds...")
        
        // Add local worlds
        for localWorld in configuration.localWorlds {
            registerLocalWorld(name: localWorld["name"] as? String ?? "world", generator: localWorld["generator"] as? String ?? "overworld")
        }
        
        // Add remote worlds
        for remoteWorld in configuration.remoteWorlds {
            registerRemoteWorld(host: remoteWorld["host"] as? String ?? "127.0.0.1", port: remoteWorld["port"] as? Int ?? 25565)
        }
        
        // And load all of them
        worlds.forEach { world in
            world.load()
        }
        
        // Start a timer for background tasks
        eventLoopGroup.next().scheduleRepeatedTask(initialDelay: TimeAmount.seconds(1), delay: TimeAmount.seconds(1)) { task in
            // Check if the server stopped
            if !self.running {
                task.cancel()
                return
            }
            
            // Increment time
            self.startTime += 1
            
            // Send keep alive to connected clients
            self.players.filter { player in
                if let channel = player as? ChannelWrapper {
                    return channel.remoteChannel == nil
                }
                return false
            }.forEach { player in
                if let channel = player as? ChannelWrapper {
                    channel.send(packet: KeepAlive())
                }
            }
            
            // Send data to bStats
            if self.startTime % 1800 == 10 && self.configuration.bstats["enabled"] as? Bool ?? true {
                BStatsSubmitData(server: self).fetch()
            }
            
            // Save worlds
            if self.startTime % 300 == 0 {
                self.eventLoopGroup.next().execute {
                    self.worlds.forEach { world in
                        world.save()
                    }
                }
            }
        }
        
        // Create server bootstrap
        let bootstrap = makeBootstrap()
        do {
            // Get address
            var addr = sockaddr_in()
            addr.sin_port = in_port_t(configuration.port).bigEndian
            let address = SocketAddress(addr, host: "*")
            
            // Create server channel
            serverChannel = try bootstrap.bind(to: address).wait()
            
            // Check that everything is running
            if let addr = serverChannel?.localAddress {
                ready = true
                log("Server running on port \(addr.port ?? 25565)")
            } else {
                logError("ERROR: server reported no local address?")
                stop()
            }
        } catch let error as NIO.IOError {
            // Error starting server
            logError("ERROR: failed to start server, errno: \(error.errnoCode)\n\(error.localizedDescription)")
            stop()
        } catch {
            // Error starting server
            logError("ERROR: failed to start server: \(type(of: error))\(error)")
            stop()
        }
        
        // Wait
        do {
            try serverChannel?.closeFuture.wait()
            running = false
            log("Server is now down")
        } catch {
            logError("ERROR: Failed to wait on server: \(error)")
        }
    }

    // Stop server
    public func stop() {
        // Prepare to stop
        ready = false
        
        // Kick players
        players.forEach { player in
            player.kick(reason: "Server closed")
        }
        
        // Save worlds
        log("Saving worlds...")
        worlds.forEach { world in
            world.save()
        }
        
        // Close connection
        serverChannel?.close().whenComplete({ _ in
            self.log("Closing connection...")
        })
    }
    
    // Initialize server channels
    private func makeBootstrap() -> ServerBootstrap {
        let reuseAddrOpt = ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR)
        return ServerBootstrap(group: eventLoopGroup)
            // Specify backlog and enable SO_REUSEADDR for the server itself
            .serverChannelOption(ChannelOptions.backlog, value: Int32(256))
            .serverChannelOption(reuseAddrOpt, value: 1)
        
            // Set the handlers that are applied to the accepted Channels
            .childChannelInitializer { channel in
                // Create objects
                let decoder = MinecraftDecoder(server: true)
                let encoder = MinecraftEncoder(server: true)
                let wrapper = ChannelWrapper(id: self.generateId(), server: self, channel: channel, decoder: decoder, encoder: encoder, prot: .HANDSHAKE, protocolVersion: self.configuration.protocolVersion)
                
                // Add client to list
                self.clients.append(wrapper)
                
                // Add then to pipeline
                return channel.pipeline.addHandlers([
                    ByteToMessageHandler(decoder),
                    MessageToByteHandler(encoder),
                    ClientHandler(channelWrapper: wrapper)
                ])
            }
        
            // Enable TCP_NODELAY and SO_REUSEADDR for the accepted Channels
            .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
            .childChannelOption(reuseAddrOpt, value: 1)
    }
    
    // Log
    public func log(_ message: ChatMessage) {
        // Allow custom log channels (like remote access)
        logger(ChatMessage(extra: [
            ChatMessage(text: "[\(getCurrentTime())] "),
            message,
            ChatMessage(text: "")
        ]))
    }
    
    public func log(_ string: String) {
        // Send with correct format
        log(ChatMessage(text: string))
    }
    
    public func logError(_ string: String) {
        // Send with correct format
        log(ChatMessage(text: string).with(format: .red))
    }
    
    public func getCurrentTime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "hh:mm:ss"
        return formatter.string(from: Date())
    }
    
    // Get server infos for ping
    public func getServerInfo(preferedProtocol: Int32) -> ServerInfo {
        // Get players
        let players = self.players
        
        // Return the payload
        return ServerInfo(
            version: ServerInfo.ServerVersion(
                name: "SwiftMC *",
                protocolVersion: ProtocolConstants.supported_versions_ids.contains(preferedProtocol) ? preferedProtocol : configuration.protocolVersion
            ),
            players: ServerInfo.ServerPlayers(
                max: configuration.slots,
                online: players.count,
                sample: []
            ),
            description: ChatMessage(text: configuration.motd),
            favicon: configuration.favicon
        )
    }
    
    // Broadcast a packet to all players
    public func broadcast(packet: Packet) {
        // Send to all players
        players.forEach { player in
            if let channel = player as? ChannelWrapper {
                channel.send(packet: packet)
            }
        }
        
        // Check for a chat message to log it
        if let chat = packet as? Chat, let message = ChatMessage.decode(from: chat.message) {
            sendMessage(message: message)
        }
    }
    
    // Call listeners
    public func fireListeners(for event: Event) {
        for listener in listeners {
            event.call(listener: listener)
        }
    }
    
    // Get a new session id
    public func generateId() -> Int32 {
        var id: Int32
        repeat {
            id = Int32.random(in: Int32.min ... Int32.max)
        } while getPlayer(id: id) != nil
        return id
    }
    
    public func getPlayer(id: Int32) -> Player? {
        return clients.first(where: { $0.id == id })
    }
    
    public func getPlayer(uuid: String) -> Player? {
        return clients.first(where: { $0.uuid == uuid })
    }
    
    public func getPlayer(name: String) -> Player? {
        return clients.first(where: { $0.name?.lowercased() == name.lowercased() })
    }
    
    // Register a command
    public func registerCommand(_ name: String, command: Command) {
        let name = name.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " "))
        if commands[name] != nil {
            return
        }
        commands[name] = command
        log("Registered command /\(name)")
    }
    
    // Get name of a command sender
    public func getName() -> String {
        return "Server"
    }
    
    // Send a message to the server
    public func sendMessage(message: ChatMessage) {
        log(message)
    }
    
    // Unregister a command
    public func unregisterCommand(_ name: String) {
        let name = name.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " "))
        commands.removeValue(forKey: name)
        log("Unregistered command /\(name)")
    }
    
    // Register a listener
    public func registerListener(listener: EventListener) {
        listeners.append(listener)
    }
    
    // Register a local world
    public func registerLocalWorld(name: String, generator: String = "overworld") {
        if !worlds.contains(where: { $0.getName() == name }) {
            let world = LocalWorld(server: self, name: name, generator: getWorldGenerator(name: generator))
            worlds.append(world)
            log("Registered local world \(world.getName()) with generator \(world.generator.getName())")
        }
    }
    
    // Register a remote world
    public func registerRemoteWorld(host: String, port: Int) {
        if !worlds.contains(where: { $0.getName() == "\(host):\(port)" }) {
            let world = RemoteWorld(server: self, host: host, port: port)
            worlds.append(world)
            log("Registered remote world \(world.getName())")
        }
    }
    
    // Register a world generaror
    public func registerWorldGenerator(generator: WorldGenerator) {
        generators.append(generator)
        log("Registered generator \(generator.getName())")
    }
    
    // Get a world generator by name (or default if not found)
    public func getWorldGenerator(name: String) -> WorldGenerator {
        return generators.first(where: { $0.getName() == name }) ?? OverworldGenerator()
    }
    
    // Dispatch a command
    @discardableResult
    public func dispatchCommand(sender: CommandSender, command: String, showError: Bool = true) -> Bool {
        // Don't execute if server is not ready
        if !ready {
            return false
        }
        
        // Log
        log("\(sender.getName()) executed command /\(command)")
        
        // Get args
        var args = command.split(separator: " ").map {
            String($0)
        }
        if !args.isEmpty {
            // Get command name
            let name = args.removeFirst().lowercased()
            
            // Check if command exists
            if let command = commands[name] {
                // Execute
                command.execute(server: self, sender: sender, args: args)
                return true
            } else if showError {
                // Command not found
                sender.sendMessage(message: ChatColor.red + "Command /\(name) not found")
            }
        }
        return false
    }
    
    @discardableResult
    public func dispatchCommand(command: String, showError: Bool = true) -> Bool {
        dispatchCommand(sender: self, command: command, showError: showError)
    }
    
}
