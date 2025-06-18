#!/bin/bash

# Multiplayer Functionality Test Runner
# This script runs all unit tests for the multiplayer functionality

echo "=== Game of Strife - Multiplayer Test Suite ==="
echo "Starting unit tests..."

# Kill any existing Godot processes to ensure clean test environment
echo "Cleaning up existing processes..."
taskkill.exe /F /IM godot.exe 2>/dev/null || true
taskkill.exe /F /IM "Godot_v4.4.1-stable_win64.exe" 2>/dev/null || true

# Wait a moment for processes to fully terminate
sleep 2

# Run the test suite
echo "Running multiplayer functionality tests..."
echo "Test output will be saved to test_results.log"

# Run tests in headless mode with output redirection
/mnt/c/ProgramData/chocolatey/bin/godot.exe --headless -- tests/TestMain.tscn > test_results.log 2>&1

# Capture exit code
exit_code=$?

# Display results
echo ""
echo "=== TEST RESULTS ==="
cat test_results.log

# Check if tests passed
if [ $exit_code -eq 0 ]; then
    echo ""
    echo "✅ ALL TESTS PASSED!"
    echo "Exit code: $exit_code"
else
    echo ""
    echo "❌ SOME TESTS FAILED!"
    echo "Exit code: $exit_code"
    echo "Check test_results.log for detailed failure information."
fi

# Clean up any test files that might have been created
echo "Cleaning up test files..."
rm -f test_*.txt 2>/dev/null || true
rm -f claude_commands_test*.txt 2>/dev/null || true

exit $exit_code