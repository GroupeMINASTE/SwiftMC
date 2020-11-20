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
import AsyncHTTPClient

public class BStatsSubmitData {
    
    let server: SwiftMC
    
    public init(server: SwiftMC) {
        self.server = server
    }
    
    public func fetch() {
        let client = HTTPClient(eventLoopGroupProvider: .createNew)
        
        var urlComponents = URLComponents()
        urlComponents.scheme = "https"
        urlComponents.host = "bstats.org"
        urlComponents.path = "/submitData/server-implementation"
        
        guard let url = urlComponents.url else {
            return
        }
        
        guard let body = try? JSONSerialization.data(withJSONObject: [
            // Server data
            "serverUUID": server.configuration.bstats["server-uuid"] ?? UUID().uuidString,
            "osName": System.name,
            "osArch": System.arch,
            "osVersion": System.version,
            "coreCount": System.coreCount,
            
            // Plugin data
            "plugins": [
                [
                    "pluginName": "SwiftMC",
                    "customCharts": [
                        // Players
                        [
                            "chartId": "players",
                            "data": [
                                "value": server.players.count
                            ]
                        ],
                        // Mode
                        [
                            "chartId": "mode",
                            "data": [
                                "value": "\(server.configuration.mode)"
                            ]
                        ],
                    ]
                ]
            ]
        ], options: []) else {
            return
        }
        
        if var request = try? HTTPClient.Request(url: url.absoluteString, method: .POST) {
            request.headers.add(name: "Accept", value: "application/json")
            request.headers.add(name: "Content-Type", value: "application/json")
            request.headers.add(name: "User-Agent", value: "MC-Server/1")
            request.body = .data(body)
            
            client.execute(request: request).whenComplete { _ in
                try? client.syncShutdown()
            }
        }
    }
    
}
