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

public class MojangJoin {
    
    let accessToken: String
    let selectedProfile: String
    let serverId: String
    
    public init(accessToken: String, selectedProfile: String, serverId: String) {
        self.accessToken = accessToken
        self.selectedProfile = selectedProfile
        self.serverId = serverId
    }
    
    public func fetch(completionHandler: @escaping (Bool) -> ()) {
        let client = HTTPClient(eventLoopGroupProvider: .createNew)
        
        var urlComponents = URLComponents()
        urlComponents.scheme = "https"
        urlComponents.host = "sessionserver.mojang.com"
        urlComponents.path = "/session/minecraft/join"
        
        guard let url = urlComponents.url else {
            completionHandler(false)
            return
        }
        
        guard let body = try? JSONSerialization.data(withJSONObject: [
            "accessToken": accessToken,
            "selectedProfile": selectedProfile,
            "serverId": serverId
        ], options: []) else {
            completionHandler(false)
            return
        }
        
        client.post(url: url.absoluteString, body: .data(body)).whenComplete { result in
            switch result {
            case.failure(_):
                completionHandler(false)
            case .success(let response):
                if response.status == .noContent {
                    completionHandler(true)
                } else {
                    completionHandler(false)
                }
            }
            try? client.syncShutdown()
        }
    }
    
}
