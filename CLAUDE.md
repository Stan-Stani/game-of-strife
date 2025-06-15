# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

"Game of Strife" is a 3rd person multiplayer combat/construction game where "everything is Conway's Game of Life". Built in Godot 4.4, it features:

- **2D Conway's Game of Life Editor**: Create cellular automata patterns (main.gd)
- **3D Game World**: Transition patterns into 3D combat environment (game_3d.gd) 
- **Multiplayer Support**: ENet-based networking with host/client architecture
- **3D Character Controller**: State machine-based player movement with ragdoll physics

## Core Architecture

### Scene Structure
- `Main.tscn` (main.gd): 2D Game of Life editor and simulator
- `Game3D.tscn` (game_3d.gd): 3D world where patterns become interactive objects
- `PlayerCharacterScene.tscn`: Complex character controller with state machine

### State Management
- `GameState` (autoload): Shares colony data between 2D editor and 3D world
- Colony data stored as `Dictionary` with `Vector2` keys and `bool` values

### Character Controller Architecture
Located in `addons/PlayerCharacter/`, uses a state machine pattern:
- `StateMachine/player_character_script.gd`: Main character controller
- Individual state scripts: idle, walk, run, jump, inair, ragdoll
- `OrbitControl/orbit_view.gd`: Camera system with orbit and aim modes
- `GodotPlush/`: 3D model with custom animations and materials

### Multiplayer System
- ENet peer-to-peer networking (game_3d.gd:18-51)
- Input actions: 'I' to host server, 'O' to connect as client
- Remote player synchronization via RPC calls

## Key Input Mappings

**2D Mode (Conway's Game of Life):**
- Left click: Place/remove cells
- Right click: Transition to 3D mode
- Enter: Start/stop simulation
- F12: Reset grid
- Middle mouse drag: Pan camera
- Mouse wheel: Zoom

**3D Mode:**
- WASD: Movement
- Shift: Run
- Space: Jump
- X: Aim camera
- Z: Side aim camera
- R: Ragdoll toggle
- Mouse: Look around
- Left click: Shoot colony pattern

## Development Commands

This is a Godot project - open `project.godot` in Godot Engine 4.4+ to run/test the game.

## Technical Notes

- Cell size constant: 64.0 pixels (main.gd:18)
- Multiplayer port: 3006 (game_3d.gd:19)
- Character uses CharacterBody3D with custom gravity calculations
- Pattern shooting spawns RigidBody3D instances of colony cells

## Known Issues
- Canceling scan still not working