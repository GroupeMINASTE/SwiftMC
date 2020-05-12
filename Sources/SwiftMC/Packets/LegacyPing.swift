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

class LegacyPing: Packet {
    
    var v1_5: Bool
    
    required init() {
        self.v1_5 = false
    }
    
    init(v1_5: Bool) {
        self.v1_5 = v1_5
    }
    
    func readPacket(from buffer: inout ByteBuffer, direction: DirectionData, protocolVersion: Int32) {
        // ???
    }
    
    func writePacket(to buffer: inout ByteBuffer, direction: DirectionData, protocolVersion: Int32) {
        // ???
    }
    
    func toString() -> String {
        return "LegacyPing(v1_5: \(v1_5))"
    }
    
}
