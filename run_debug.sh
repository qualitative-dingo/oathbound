#!/bin/bash
# Launch two Oathbound instances side-by-side: HOST (left) | CLIENT (right)
# Usage: ./run_debug.sh

GODOT="/Users/andreattar/Downloads/Godot.app/Contents/MacOS/Godot"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -f "$GODOT" ]; then
    echo "ERROR: Godot not found at $GODOT"
    echo "Update the GODOT variable in this script to your Godot binary path."
    exit 1
fi

echo "Starting HOST (left half)..."
"$GODOT" --path "$PROJECT_DIR" -- --host &
HOST_PID=$!

sleep 2

echo "Starting CLIENT (right half)..."
"$GODOT" --path "$PROJECT_DIR" -- --client &
CLIENT_PID=$!

echo ""
echo "HOST  PID: $HOST_PID"
echo "CLIENT PID: $CLIENT_PID"
echo ""
echo "Press Ctrl+C to kill both instances."

trap "kill $HOST_PID $CLIENT_PID 2>/dev/null; exit" INT TERM
wait
