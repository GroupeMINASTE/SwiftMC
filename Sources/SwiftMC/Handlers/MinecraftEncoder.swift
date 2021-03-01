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
import CompressNIO
import CryptoSwift

class MinecraftEncoder: MessageToByteEncoder {
    
    // Input alias
    typealias OutboundIn = Packet
    
    // Configuration for encoding
    var channel: ChannelWrapper?
    var server: Bool
    var iv: [UInt8]
    
    // Initializer
    init(server: Bool) {
        self.server = server
        self.iv = []
    }
    
    func encode(data: Packet, out: inout ByteBuffer) throws {
        // Init a temporary buffer
        var buffer1 = ByteBufferAllocator().buffer(capacity: 1024*1024)
        var buffer2 = ByteBufferAllocator().buffer(capacity: 1024*1024)
        var buffer3 = ByteBufferAllocator().buffer(capacity: 1024*1024)
        
        // Packet encoder
        try packetEncoder(data: data, out: &buffer1)
        
        // Threshold encoder
        try thresholdEncoder(from: &buffer1, out: &buffer2)
        
        // Frame encoder
        try frameEncoder(from: &buffer2, out: &buffer3)
        
        // Encryption encoder
        try encryptionEncoder(from: &buffer3, out: &out)
    }
    
    // Threshold
    func thresholdEncoder(from: inout ByteBuffer, out: inout ByteBuffer) throws {
        // Check for compression
        if let threshold = channel?.threshold, threshold != -1 {
            // Check for size
            let fromSize = Int32(from.readableBytes)
            if fromSize < threshold {
                out.writeVarInt(value: 0)
                out.writeBuffer(&from)
            } else {
                out.writeVarInt(value: fromSize)
                try from.compress(to: &out, with: .deflate)
            }
        } else {
            // Just send data
            out.writeBuffer(&from)
        }
    }
    
    // Frame encoder
    func frameEncoder(from: inout ByteBuffer, out: inout ByteBuffer) throws {
        out.writeVarInt(value: Int32(from.readableBytes))
        out.writeBuffer(&from)
    }
    
    // Encryption encoder
    func encryptionEncoder(from: inout ByteBuffer, out: inout ByteBuffer) throws {
        if from.readableBytes > 0 {
            if let sharedKey = channel?.sharedKey, let bytes = from.readBytes(length: from.readableBytes), let encrypted = try? AES(key: sharedKey, blockMode: CFB(iv: iv, segmentSize: .cfb8), padding: .noPadding).encrypt(bytes) {
                // Encrypt data with given key
                out.writeBytes([UInt8](encrypted))
                
                // Update IV
                self.iv = iv + encrypted
                self.iv.removeFirst(encrypted.count)
            } else {
                // Just send data
                out.writeBuffer(&from)
            }
        }
    }
    
    // Packet encoder
    func packetEncoder(data: Packet, out: inout ByteBuffer) throws {
        // Get direction
        if let channel = channel, let direction = server ? channel.prot.to_client : channel.prot.to_server {
            // Get packet id
            if let id = direction.getId(for: type(of: data), version: channel.protocolVersion) {
                // Write packet id
                out.writeVarInt(value: id)
            } else if let unknownPacket = data as? UnknownPacket {
                // Write packet id
                out.writeVarInt(value: unknownPacket.packetId)
            }
            
            // And write packet content
            data.writePacket(to: &out, direction: direction, protocolVersion: channel.protocolVersion)
        }
    }
    
}
