#!/bin/bash

# Test script for Game of Strife multiplayer functionality
GODOT="/mnt/c/ProgramData/chocolatey/bin/godot.exe"

echo "=== Game of Strife Multiplayer Test Script ==="

case "$1" in
    "server")
        echo "Starting server (timeout 30s)..."
        timeout 30s $GODOT --headless --host
        ;;
    "client")
        echo "Starting client connecting to ${2:-127.0.0.1} (timeout 15s)..."
        timeout 15s $GODOT --headless --client ${2:-127.0.0.1}
        ;;
    "test-connection")
        echo "Testing server-client connection..."
        echo "Starting server in background..."
        timeout 20s $GODOT --headless --host &
        SERVER_PID=$!
        
        echo "Waiting 3 seconds for server startup..."
        sleep 3
        
        echo "Starting client..."
        timeout 10s $GODOT --headless --client 127.0.0.1
        
        echo "Cleaning up server..."
        kill $SERVER_PID 2>/dev/null
        wait $SERVER_PID 2>/dev/null
        echo "Test complete!"
        ;;
    "network-test")
        echo "Running network tests..."
        timeout 30s $GODOT --headless --test-network
        ;;
    "local-test")
        echo "Running local multiplayer test..."
        timeout 30s $GODOT --headless --test-local-multiplayer
        ;;
    "help"|*)
        echo "Usage: $0 [command] [options]"
        echo ""
        echo "Commands:"
        echo "  server                 - Start headless server"
        echo "  client [ip]           - Connect as client (default: 127.0.0.1)"
        echo "  test-connection       - Test server-client connection"
        echo "  network-test          - Run network diagnostics"
        echo "  local-test           - Run local multiplayer test"
        echo "  help                 - Show this help"
        echo ""
        echo "Examples:"
        echo "  $0 server"
        echo "  $0 client"
        echo "  $0 client 192.168.1.100"
        echo "  $0 test-connection"
        ;;
esac