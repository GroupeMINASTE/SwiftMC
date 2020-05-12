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

public class ChannelWrapper {
    
    // Vars
    var channel: Channel
    var decoder: MinecraftDecoder
    var encoder: MinecraftEncoder
    var closed: Bool = false
    var closing: Bool = false
    
    init(channel: Channel, decoder: MinecraftDecoder, encoder: MinecraftEncoder) {
        self.channel = channel
        self.decoder = decoder
        self.encoder = encoder
    }
    
    func setProtocol(prot: Prot) {
        decoder.prot = prot
        encoder.prot = prot
    }
    
    func setVersion(version: Int32) {
        decoder.protocolVersion = version
        encoder.protocolVersion = version
    }
    
    func send(packet: Packet) {
        if !closed {
            channel.writeAndFlush(packet, promise: nil)
        }
    }
    
}
