# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

"Game of Strife" is a 3rd person multiplayer combat/construction game where "everything is Conway's Game of Life". Built in Godot 4.4, it features:

- **2D Conway's Game of Life Editor**: Create cellular automata patterns (main.gd)
- **3D Game World**: Transition patterns into 3D combat environment (game_3d.gd) 
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

### Command Line Testing
The game supports command line arguments for automated testing:

```bash
# Run game in headless mode for testing
godot --headless

# Test Conway's Game of Life functionality
godot --test-conway

# Load specific patterns for testing
godot --pattern glider      # Load glider pattern
godot --pattern block       # Load block pattern  
godot --pattern blinker     # Load blinker pattern
godot --pattern toad        # Load toad pattern
godot --pattern beacon      # Load beacon pattern
godot --pattern pulsar      # Load pulsar pattern

# Skip UI for direct testing
godot --skip-ui

# Enable debug logging
godot --debug

# Combine options for comprehensive testing
godot --headless --test-conway --pattern glider --debug
```

#### Cleaning Up Background Processes
**IMPORTANT**: When testing via command line, background Godot processes may accumulate. Always clean them up:

```bash
# Kill all Godot processes on Windows (from WSL)
taskkill.exe /F /IM godot.exe
taskkill.exe /F /IM "Godot_v4.4.1-stable_win64.exe"

# Check for remaining processes
tasklist.exe | grep -i godot
```

This is especially important after running multiple test sessions to prevent resource issues.

## Testing Framework

### Unit Testing

The project includes comprehensive unit tests for core functionality:

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

**Conway's Game of Life Tests** (`tests/test_conway.gd`):
- Cell state management
- Pattern evolution rules
- Grid boundary handling
- Pattern loading and saving

**GameState Tests** (`tests/test_gamestate.gd`):
- Pattern storage and retrieval
- Data persistence between scenes
- Colony data validation

**Integration Tests** (`tests/test_integration.gd`):
- 2D to 3D scene transitions
- Pattern visualization in 3D world
- Character controller integration

### Testing Best Practices

#### Background Process Management
- **Always use proper process cleanup when testing**
  - Prevents zombie processes
  - Ensures clean test environment
- **Use output redirection for headless testing**:
  - `godot --headless --test-conway > test_output.log 2>&1`
  - Captures all output for debugging

#### Test Development Guidelines
- Write tests before implementing new features
- Ensure all tests pass before committing changes
- Use descriptive test names that explain what is being tested
- Group related tests in logical test files
- Clean up test resources properly

### Claude Testing Workflow

When Claude needs to test changes:

1. **Run Unit Tests First**:
   ```bash
   ./tests/verify_tests.sh
   ```

2. **Test Specific Functionality**:
   ```bash
   # Test Conway's Game of Life changes
   godot --headless --test-conway --debug
   
   # Test pattern functionality
   godot --headless --pattern glider --test-conway
   ```

3. **Clean Up Processes**:
   ```bash
   taskkill.exe /F /IM godot.exe
   ```

4. **Review Test Output**:
   - Check for any failed assertions
   - Verify expected behavior matches actual results
   - Look for performance issues or warnings

## Known Issues

### Pattern Alignment
- Player pattern visual boards have slight misalignment with Conway's Game of Life coordinates
- Corner cells don't appear exactly at board corners due to asymmetric coordinate mapping (-5 to +4 range)
- Visual pattern uses 10x10 grid mapped to 32x32 texture on 2.5x2.5 unit board
- Shooting mechanics work correctly, only visual alignment is affected
- **Location**: `addons/PlayerCharacter/StateMachine/player_character_script.gd` lines 684-687 (texture generation)

## Development Guidelines

### Code Quality
- Always run tests before committing changes
- Use descriptive variable and function names
- Follow existing code style and patterns
- Add comments for complex logic

### Performance Considerations
- Conway's Game of Life calculations can be intensive for large grids
- Use appropriate data structures for pattern storage
- Consider optimization for real-time 3D rendering

### Security
- Never commit sensitive information
- Validate all input parameters
- Use safe file operations for pattern loading/saving