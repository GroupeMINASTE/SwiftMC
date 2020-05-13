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

public class HelpCommand: Command {
    
    public func execute(sender: ChannelWrapper, args: [String]) {
        // Init base message
        let message = ChatMessage(extra: [
            ChatMessage(text: "SwiftMC Server - Developed by Nathan Fallet at Groupe MINASTE").with(color: .aqua)
        ])
        
        // Iterate commands
        for (name, command) in sender.server.commands {
            message.extra?.append(contentsOf: [
                ChatMessage(text: "\n/\(name): ").with(color: .gold),
                ChatMessage(text: command.description()).with(color: .yellow)
            ])
        }
        
        // Print help
        sender.send(packet: Chat(message: message))
    }
    
    public func description() -> String {
        return "Print this help command"
    }
    
}