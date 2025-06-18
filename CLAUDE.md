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

### WSL Users
If using WSL with Godot installed via Chocolatey on Windows:
```bash
# Add this alias to ~/.bashrc for convenience
alias godot="/mnt/c/ProgramData/chocolatey/bin/godot.exe"

# Usage:
godot project.godot         # Open in editor
godot -- project.godot      # Run game directly
```

### Command Line Multiplayer Testing
The game supports command line arguments for automated multiplayer testing:

```bash
# Start server (host mode)
godot --host

# Connect as client to specific IP
godot --client 127.0.0.1
godot --client 192.168.1.100

# Run network diagnostics
godot --headless --test-network

# Test local multiplayer setup
godot --headless --test-local-multiplayer

# Additional options
godot --port 3007                    # Use custom port
godot --debug-multiplayer            # Enable debug logging
godot --skip-2d                      # Skip 2D editor, go to 3D

# Quick testing with predefined patterns
godot --pattern glider               # Load glider pattern and start
godot --pattern block                # Load block pattern and start
godot --pattern blinker              # Load blinker pattern and start
godot --pattern toad                 # Load toad pattern and start
godot --pattern beacon               # Load beacon pattern and start
godot --pattern pulsar               # Load pulsar pattern and start

# Instant multiplayer setup
godot --auto-host                    # Start as host with glider pattern
godot --auto-client                  # Connect to localhost with block pattern
godot --auto-client 192.168.1.100   # Connect to specific IP with block pattern
```

#### Automated Testing Script
Use the included test script for easier testing with timeouts:
```bash
# Test complete server-client connection
./tests/test_multiplayer.sh test-connection

# Start headless server
./tests/test_multiplayer.sh server

# Connect as client
./tests/test_multiplayer.sh client [ip_address]

# Run network tests
./tests/test_multiplayer.sh network-test
```

#### Cleaning Up Background Processes
**IMPORTANT**: When testing multiplayer via command line, background Godot processes may accumulate. Always clean them up:

```bash
# Kill all Godot processes on Windows (from WSL)
taskkill.exe /F /IM godot.exe
taskkill.exe /F /IM "Godot_v4.4.1-stable_win64.exe"

# Check for remaining processes
tasklist.exe | grep -i godot
```

This is especially important after running multiple test sessions to prevent resource issues.

### Unit Testing

The project includes comprehensive unit tests for multiplayer functionality:

#### Running Tests

```bash
# Quick verification of all functionality
./tests/verify_tests.sh

# Run full automated test suite  
./tests/run_tests.sh

# Manual test execution (open in Godot)
# Load and run tests/TestMain.tscn
```

#### Test Coverage

**Test Framework** (`tests/test_framework.gd`):
- Simple assertion-based testing system
- Test result tracking and reporting
- Pass/fail statistics

**Multiplayer Core Tests** (`tests/test_multiplayer.gd`):
- GameState initialization and pattern storage
- Multiplayer peer creation and management
- Pattern sharing and synchronization
- Player pattern storage per peer ID

**Command System Tests** (`tests/test_command_system.gd`):
- Command file parsing and validation
- Role-based file selection (host/client)
- Peer ID specific file monitoring
- Command execution and file clearing

**Integration Tests** (`tests/test_integration.gd`):
- End-to-end multiplayer connection flow
- Command file system in multiplayer environment
- Pattern synchronization between players

#### Test Results
- All tests verify core multiplayer functionality works correctly
- Command file system supports independent player control
- Pattern sharing maintains game balance (damage/velocity scaling)
- Server-client architecture handles connections reliably

### Claude Code Player Control API

#### Multiple Command File System
Different players can be controlled independently using separate command files:

**Command File Types:**
- `claude_commands.txt` - Shared by all instances (default)
- `claude_commands_host.txt` - Only read by the host player
- `claude_commands_client.txt` - Only read by client players
- `claude_commands_1.txt` through `claude_commands_4.txt` - Read by specific peer IDs (1-4 only)

**Usage Examples:**
```bash
# Control only the host player
echo "walk forward 3" > claude_commands_host.txt

# Control only client players
echo "jump" > claude_commands_client.txt

# Control all connected players
echo "list" > claude_commands.txt

# Combat examples
echo "aim 1" > claude_commands_host.txt          # Host aims at player 1
echo "shoot 0" > claude_commands_client.txt      # Client shoots at player 0 (host)
echo "shoot_nearest" > claude_commands.txt       # All players shoot at nearest enemy
```

**How It Works:**
- Each game instance monitors different sets of command files based on its multiplayer role
- Commands are automatically processed and cleared from files after execution
- Host monitors: default + host-specific + peer ID files
- Clients monitor: default + client-specific + peer ID files
- Allows independent control of different players in multiplayer sessions

#### Player Control Commands
For testing and debugging, players have programmatic movement controls available:

#### Godot Console Commands (F4 to open console)
```gdscript
# List all available players
Game3D.claude_list_players()

# Get player status
Game3D.claude_get_player_status(0)  # 0 = local player, 1+ = remote players

# Move player to specific position (smoothly)
Game3D.claude_move_player_to(Vector3(10, 0, 5), 0)

# Teleport player instantly
Game3D.claude_teleport_player_to(Vector3(0, 0, 0), 0)

# Enable numpad movement controls (8=forward, 2=back, 4=left, 6=right, 7=up, 1=down)
Game3D.claude_enable_player_debug_movement(true, 0)

# Run automated movement test
Game3D.claude_test_movement()
```

#### Direct Player Control (if you have player reference)
```gdscript
var player = Game3D.claude_get_local_player()

# Movement commands
player.claude_move_to(Vector3(5, 0, 0))        # Move to position
player.claude_teleport_to(Vector3(0, 0, 0))   # Instant teleport
player.claude_move_relative(Vector3(0, 0, 5))  # Move by offset
player.claude_stop_movement()                  # Stop current movement

# Configuration
player.claude_set_move_speed(10.0)            # Set movement speed
player.claude_enable_debug_movement(true)     # Enable numpad controls

# Status
var pos = player.claude_get_position()        # Get current position
var status = player.claude_get_status()       # Get full status dict
```

#### Manual Numpad Controls
When debug movement is enabled, use numpad keys for direct control:
- **Numpad 8**: Move forward (negative Z)
- **Numpad 2**: Move backward (positive Z)  
- **Numpad 4**: Move left (negative X)
- **Numpad 6**: Move right (positive X)
- **Numpad 7**: Move up (positive Y)
- **Numpad 1**: Move down (negative Y)

These controls work in addition to normal WASD movement and are useful for precise positioning during testing.

#### Combat Commands

The Claude command system now supports targeting and shooting at other players in multiplayer matches:

**Basic Combat Commands:**
```bash
# Aim at specific players
aim 1              # Aim at player 1 (local player aims)
aim 2 0            # Player 0 aims at player 2

# Shoot at specific players  
shoot 1            # Aim and shoot at player 1 (local player)
shoot 0 1          # Player 1 shoots at player 0

# Auto-targeting
nearest            # Find nearest enemy to local player
nearest 1          # Find nearest enemy to player 1
shoot_nearest      # Shoot at nearest enemy (local player)
shoot_nearest 1    # Player 1 shoots at nearest enemy
```

**Combat Usage Examples:**
```bash
# Host targets client in multiplayer
echo "aim 1" > claude_commands_host.txt

# Client retaliates
echo "shoot 0" > claude_commands_client.txt

# Auto-combat: everyone shoots at nearest enemy
echo "shoot_nearest" > claude_commands.txt

# Coordinated attack: player 1 aims while player 2 shoots
echo "aim 2" > claude_commands_1.txt
echo "shoot 2" > claude_commands_2.txt
```

**Combat Mechanics:**
- Only the local player (player 0) can currently aim (camera control limitation)
- Shooting automatically aims at target before firing
- Commands respect shooting cooldowns (0.5 seconds between shots)
- Pattern bullets are fired based on each player's current Conway's Game of Life pattern
- All players can be targeted regardless of their role (host/client)

## Quick Start Commands

For rapid testing and development, use these command line options to skip the 2D editor and start directly in 3D with predefined patterns:

### Pattern Loading
```bash
# Load specific Conway's Game of Life patterns
godot --pattern glider     # Classic 5-cell glider
godot --pattern block      # Stable 4-cell block  
godot --pattern blinker    # Oscillating 3-cell pattern
godot --pattern toad       # 6-cell period-2 oscillator
godot --pattern beacon     # 6-cell period-2 oscillator
godot --pattern pulsar     # Large 24-cell period-3 oscillator
```

### Instant Multiplayer Setup
```bash
# Start as host with glider pattern
godot --auto-host

# Connect as client with block pattern
godot --auto-client                    # Connects to localhost
godot --auto-client 192.168.1.100     # Connects to specific IP
```

### Combined Usage Examples
```bash
# Host with specific pattern
godot --pattern pulsar --host

# Client with specific pattern connecting to host
godot --pattern beacon --client 192.168.1.100

# Testing multiplayer locally (run in separate terminals)
Terminal 1: godot --auto-host
Terminal 2: godot --auto-client
```

## Technical Notes

- Cell size constant: 64.0 pixels (main.gd:18)
- Multiplayer port: 3006 (game_3d.gd:19)
- Character uses CharacterBody3D with custom gravity calculations
- Pattern shooting spawns RigidBody3D instances of colony cells

## Known Issues
- Canceling scan still not working

## Important Development Notes
- When running the game from command line, always redirect output to a log file to avoid blocking:
  ```bash
  nohup /mnt/c/ProgramData/chocolatey/bin/godot.exe -- project.godot > godot_output.log 2>&1 &
  ```
  This allows you to check the console output periodically with `tail -f godot_output.log`