# SwiftMC

[![Build Status](https://travis-ci.com/GroupeMINASTE/SwiftMC.svg?token=oK8ceAyYNdbxPjHsz2xq&branch=master)](https://travis-ci.com/GroupeMINASTE/SwiftMC)
[![License](https://img.shields.io/github/license/GroupeMINASTE/SwiftMC)](LICENSE)
[![Issues](https://img.shields.io/github/issues/GroupeMINASTE/SwiftMC)]()
[![Pull Requests](https://img.shields.io/github/issues-pr/GroupeMINASTE/SwiftMC)]()
[![Code Size](https://img.shields.io/github/languages/code-size/GroupeMINASTE/SwiftMC)]()
[![CodeFactor](https://www.codefactor.io/repository/github/groupeminaste/swiftmc/badge)](https://www.codefactor.io/repository/github/groupeminaste/swiftmc)
[![Open Source Helpers](https://www.codetriage.com/groupeminaste/swiftmc/badges/users.svg)](https://www.codetriage.com/groupeminaste/swiftmc)

A Minecraft server and proxy written from scratch in Swift.

> **NOTICE**: This swift package is in active development, so the code may build with warnings or errors

Trello board for the project: [https://trello.com/b/GWH4gv9g/swiftmc](https://trello.com/b/GWH4gv9g/swiftmc)

## Installation (run a server)

Clone the repository and start the server

```bash
git clone https://github.com/GroupeMINASTE/SwiftMC.git
cd SwiftMC
swift run -c release
```

## Create a custom server

Add SwiftMC to the dependencies of your swift executable package:

```swift
.package(url: "https://github.com/GroupeMINASTE/SwiftMC.git", from: "0.0.1")
```

Create a server:

```swift
import SwiftMC

// Initialize a server
let server = SwiftMC()

// And start it
DispatchQueue.global().async {
    server.start()
}

// Read commands from console
while let input = readLine(strippingNewline: true) {
    server.dispatchCommand(command: input)
}
```

See [DOCUMENTATION.md](DOCUMENTATION.md) for a full documentation of all available features to customize your server.
