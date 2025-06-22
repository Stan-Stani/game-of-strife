#!/bin/bash

# Complete test suite runner for Game of Strife
# Runs all tests and generates comprehensive reports

echo "Game of Strife - Complete Test Suite"
echo "===================================="

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

# Create logs directory
mkdir -p tests/logs

# Run unit tests
echo "Running unit tests..."
$GODOT_CMD --headless --test tests/TestMain.tscn > tests/logs/unit_tests.log 2>&1
UNIT_TEST_EXIT_CODE=$?

# Run Conway's Game of Life tests
echo "Running Conway's Game of Life tests..."
$GODOT_CMD --headless --test-conway --debug > tests/logs/conway_tests.log 2>&1
CONWAY_TEST_EXIT_CODE=$?

# Test pattern loading
echo "Testing pattern loading..."
$GODOT_CMD --headless --pattern glider --test-conway > tests/logs/pattern_tests.log 2>&1
PATTERN_TEST_EXIT_CODE=$?

# Generate test report
echo ""
echo "Test Results Summary:"
echo "===================="

if [ $UNIT_TEST_EXIT_CODE -eq 0 ]; then
    echo "✓ Unit Tests: PASSED"
else
    echo "✗ Unit Tests: FAILED"
fi

if [ $CONWAY_TEST_EXIT_CODE -eq 0 ]; then
    echo "✓ Conway Tests: PASSED"
else
    echo "✗ Conway Tests: FAILED"
fi

if [ $PATTERN_TEST_EXIT_CODE -eq 0 ]; then
    echo "✓ Pattern Tests: PASSED"
else
    echo "✗ Pattern Tests: FAILED"
fi

echo ""
echo "Test logs saved to tests/logs/"
echo "Unit test log: tests/logs/unit_tests.log"
echo "Conway test log: tests/logs/conway_tests.log"
echo "Pattern test log: tests/logs/pattern_tests.log"

# Clean up any background processes
if command -v taskkill.exe &> /dev/null; then
    echo ""
    echo "Cleaning up background processes..."
    taskkill.exe /F /IM godot.exe 2>/dev/null || true
    taskkill.exe /F /IM "Godot_v4.4.1-stable_win64.exe" 2>/dev/null || true
fi

# Exit with error code if any tests failed
if [ $UNIT_TEST_EXIT_CODE -ne 0 ] || [ $CONWAY_TEST_EXIT_CODE -ne 0 ] || [ $PATTERN_TEST_EXIT_CODE -ne 0 ]; then
    echo ""
    echo "Some tests failed. Check the logs for details."
    exit 1
else
    echo ""
    echo "All tests passed successfully!"
    exit 0
fi