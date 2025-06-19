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

## Development Best Practices

### Background Process Management
- **Always use `disown` when starting child processes**
  - Prevents zombie processes
  - Allows long-running background tasks to continue after terminal closes
- **Alternative to disown for Godot processes**:
  - `(/mnt/c/ProgramData/chocolatey/bin/godot.exe --auto-host > host_output.log 2>&1 &) && exit 0`
    - Redirects output to log file
    - Runs in background
    - Exits current shell immediately

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
- Server-client architecture handles connections reliably

## Known Issues

### Pattern Alignment
- Player pattern visual boards have slight misalignment with Conway's Game of Life coordinates
- Corner cells don't appear exactly at board corners due to asymmetric coordinate mapping (-5 to +4 range)
- Visual pattern uses 10x10 grid mapped to 32x32 texture on 2.5x2.5 unit board
- Shooting mechanics work correctly, only visual alignment is affected
- **Location**: `addons/PlayerCharacter/StateMachine/player_character_script.gd` lines 684-687 (texture generation)