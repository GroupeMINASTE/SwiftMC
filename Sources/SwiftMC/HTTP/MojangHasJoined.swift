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

public class MojangHasJoined {
    
    let username: String
    let serverId: String
    
    public init(username: String, serverId: String) {
        self.username = username
        self.serverId = serverId
    }
    
    public func fetch(completionHandler: @escaping ([String: Any]?) -> ()) {
        let client = HTTPClient(eventLoopGroupProvider: .createNew)
        
        var urlComponents = URLComponents()
        urlComponents.scheme = "https"
        urlComponents.host = "sessionserver.mojang.com"
        urlComponents.path = "/session/minecraft/hasJoined"
        urlComponents.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "serverId", value: serverId)
        ]
        
        guard let url = urlComponents.url else {
            completionHandler(nil)
            return
        }
        
        client.get(url: url.absoluteString).whenComplete { result in
            switch result {
            case.failure(_):
                completionHandler(nil)
            case .success(let response):
                if response.status == .ok, let body = response.body, let json = try?JSONSerialization.jsonObject(with: Data(buffer: body), options: []) as? [String: Any] {
                    completionHandler(json)
                } else {
                    completionHandler(nil)
                }
            }
            try? client.syncShutdown()
        }
    }
    
}
