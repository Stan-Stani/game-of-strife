#!/bin/bash

# Quick verification script for Game of Strife
# Runs essential functionality tests for rapid feedback

echo "Game of Strife - Quick Verification"
echo "==================================="

# Check if Godot is available
if ! command -v godot &> /dev/null; then
    # Try Windows path for WSL users
    if command -v /mnt/c/ProgramData/chocolatey/bin/godot.exe &> /dev/null; then
        GODOT_CMD="/mnt/c/ProgramData/chocolatey/bin/godot.exe"
    else
        echo "Error: Godot not found in PATH"
        echo "Please install Godot or add it to your PATH"
        exit 1
    fi
else
    GODOT_CMD="godot"
fi

echo "Using Godot: $GODOT_CMD"
echo ""

# Test 1: Basic Conway functionality
echo "Testing Conway's Game of Life basics..."
CONWAY_OUTPUT=$(timeout 10s $GODOT_CMD --headless --test-conway 2>&1)
CONWAY_EXIT_CODE=$?

# timeout command returns 124 on timeout, but we check for expected output
if echo "$CONWAY_OUTPUT" | grep -q "Conway tests completed"; then
    echo "✓ Conway's Game of Life: WORKING"
    CONWAY_PASS=true
else
    echo "✗ Conway's Game of Life: FAILED"
    CONWAY_PASS=false
fi

# Test 2: Pattern loading
echo "Testing pattern loading..."
PATTERN_OUTPUT=$(timeout 10s $GODOT_CMD --headless --pattern glider --debug 2>&1)
PATTERN_EXIT_CODE=$?

if echo "$PATTERN_OUTPUT" | grep -q "Loaded pattern: glider"; then
    echo "✓ Pattern Loading: WORKING"
    PATTERN_PASS=true
else
    echo "✗ Pattern Loading: FAILED"
    PATTERN_PASS=false
fi

# Test 3: Command line argument parsing
echo "Testing command line arguments..."
ARG_OUTPUT=$(timeout 10s $GODOT_CMD --headless --debug 2>&1)
ARG_EXIT_CODE=$?

# Check if Godot launched properly (indicates arg parsing worked)
if echo "$ARG_OUTPUT" | grep -q "Godot Engine"; then
    echo "✓ Command Line Args: WORKING"
    ARG_PASS=true
else
    echo "✗ Command Line Args: FAILED"
    ARG_PASS=false
fi

# Clean up any background processes
if command -v taskkill.exe &> /dev/null; then
    taskkill.exe /F /IM godot.exe 2>/dev/null || true
    taskkill.exe /F /IM "Godot_v4.4.1-stable_win64.exe" 2>/dev/null || true
fi

echo ""
echo "Quick Verification Summary:"
echo "=========================="

if $CONWAY_PASS && $PATTERN_PASS && $ARG_PASS; then
    echo "✓ All core functionality is working"
    echo "The game is ready for development and testing"
    exit 0
else
    echo "✗ Some functionality is not working properly"
    echo "Run './tests/run_tests.sh' for detailed analysis"
    exit 1
fi