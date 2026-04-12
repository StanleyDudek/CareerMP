# CareerMP
Enabling [BeamNG.drive](https://beamng.com/game/)'s Career Mode in [BeamMP](https://beammp.com/) servers.

<img width="2468" height="861" alt="image" src="https://github.com/user-attachments/assets/bd9bcb2f-530f-4fcd-a76b-732ec6ce7159" />


## Overview
The goal of CareerMP is not to change the base game career mode or create my own unique multiplayer career mode like others have done before to good effect, but to provide whatever handling is necessary on the BeamMP client and server to allow the base game career mode to function as multiplayer, so you can play career mode with friends in the same space.

This is basically the same as single player career mode, and ~~all~~ most of what that means, but in addition to you, there will be real players doing their own careers as well.

## Highlights / Features
- Support for all base-game career features at parity with single player career mode
- Saves are local, you can continue on another server running CareerMP, you can take an online save offline and vice versa
- Mod vehicles that the base game already support in career mode ~~can spawn in traffic and~~ can be found at dealerships
- Render distance of vehicles have been increased so that you can see players on the bigMap
- ~~Forced simple_traffic models are used, in freeroaming career, players spawn 2 road traffic vehicles each; missions, challenges, scenarios add additional unmetered traffic~~
- Traffic Signals are synced, for a congruent experience for all players
- Red light camera / speed trap data broadcasts
- Dragrace scoreboard display and winner light syncing
- Missions, challenges, scenarios prefabs (track layouts, barriers, hay bales, barrels, arrow signs, gates, unique structures, et cetera) are synced on the fly so you can observe others engage in these activities and have to find creative ways around should they block your path
- MP UI app injection into missions, challenges, scenarios, making sure you can see chat or quit the session from most points of play
- Syncing the active states (shown or hidden) of vehicles is a critical part of behind the scenes functionality
- Nametag visibility supression for many spawnables including traffic to limit visual clutter
- Playerlist based payment system to pay other players

## Requirements
Due to multiplayer overhead, client performance requirements are accordingly more demanding than single player career. Players with moderate systems have reported 5-10% impact compared to an unmodded BeamMP server lobby, high end systems are not really affected, and low end systems will suffer and struggle to maintain realtime physics and position sync if they are running fewer than 20-30 FPS.

CareerMP was initially made to work on the following versions of BeamNG and BeamMP softwares:
- BeamNG.drive v0.38.4
- BeamMP Server v3.9.0 (v3.9.1)
- BeamMP Launcher v2.7.0
- BeamMP Client v4.20.2

Updates to any of these could possibly render CareerMP non-functional without notice.

## Installation
1. Download the latest [release](https://github.com/StanleyDudek/CareerMP/releases/) and unpack the contents to the root directory of your BeamMP server directory
2. Set `MaxCars = 100` or greater in your `ServerConfig.toml`
3. Set `Map = "/levels/west_coast_usa/info.json"` in your `ServerConfig.toml`
4. Once run with CareerMP installed, a config file will be generated

## Server Console Usage
To read config settings:

`CareerMP GetConfig <section> <key>`

`CMP GetConfig <section> <key>`

To set config settings:

`CareerMP SetConfig <section> <key> <value>`

`CMP SetConfig <section> <key> <value>`

## Notes
As CareerMP relies on the base game's career mode, it currently will only function on the West Coast, USA map.

CareerMP provides no player moderation itself, and should not conflict with the server moderation plugin of your choice, provided all players can be allowed to spawn at least 100 vehicles.

CareerMP uses your BeamMP username to create a save file, and will currently always start you in the save file matching your BeamMP username when you join the server. You can continue this file offline, you can continue this save in any other server running CareerMP, if you would like to use a specific file from single player to autoload online in a server running CareerMP, you can make sure the save file's save name matches your BeamMP username before joining. You may also load any save from the ESC menu in game.

Be aware that using the same save across modded servers and unmodded servers will likely face compatibility issues.

Currently everyone’s vehicle marketplace will be local to their save, that is, you cannot currently exchange vehicles with other players, but I hope to make this available, I believe it’s quite possible.

## Gallery

<img width="1763" height="1115" alt="image" src="https://github.com/user-attachments/assets/bb741ab2-7710-42e6-8835-0fc028933e8d" />

<img width="1349" height="1087" alt="image" src="https://github.com/user-attachments/assets/481bd55a-cc52-4b21-b290-ce934bb7a956" />

<img width="1503" height="1148" alt="image" src="https://github.com/user-attachments/assets/a610afff-fb08-4c9f-937c-ba7bfbbe72d1" />

<img width="1215" height="647" alt="image" src="https://github.com/user-attachments/assets/769505e7-bdb1-4eed-a6b7-a5640671353b" />

<img width="1338" height="1112" alt="image" src="https://github.com/user-attachments/assets/14cab7ec-0ebb-4a37-a08d-0e7780360036" />

<img width="1626" height="1035" alt="image" src="https://github.com/user-attachments/assets/bdc5aa9f-e731-43c0-bb14-31ea6bf0647c" />

If you would like to know more or are interested in contributing, please find me on my discord server: [Dudek's Sandbox](https://discord.gg/caU5adg)
