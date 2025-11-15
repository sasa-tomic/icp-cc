#!/bin/bash

# Script to validate all example Lua files
API_URL="http://localhost:8787/api/v1/scripts/validate"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXAMPLES_DIR="$SCRIPT_DIR/../../apps/autorun_flutter/lib/examples"
TIMEOUT_SECONDS=30

echo "Validating all Lua example scripts..."
echo "================================"

cd "$EXAMPLES_DIR"
for file in *.lua; do
    if [ -f "$file" ]; then
        echo -n "Testing $file... "

        # Build payload with jq to ensure proper escaping
        payload=$(jq -Rs '{lua_source: .}' < "$file")
        if [ $? -ne 0 ]; then
            echo "❌ PAYLOAD ERROR"
            echo "Error: Failed to build JSON payload for $file"
            exit 1
        fi

        response=$(timeout "$TIMEOUT_SECONDS" curl --fail-with-body -sS -X POST "$API_URL" -H "Content-Type: application/json" -d "$payload")
        command_status=$?

        if [ $command_status -eq 124 ]; then
            echo "❌ TIMEOUT (after ${TIMEOUT_SECONDS}s)"
            echo "Error: Script validation timed out"
            echo "This might indicate an issue with the validation endpoint or the Lua script"
            exit 1
        elif [ $command_status -ne 0 ]; then
            echo "❌ CURL FAILED (exit code: $command_status)"
            echo "Error: Failed to connect to validation endpoint at $API_URL"
            echo "Make sure the Cloudflare Worker is running and accessible"
            if [ -n "$response" ]; then
                echo "Response payload:"
                echo "$response"
            fi
            exit 1
        fi

        # Check if we got a response
        if [ -z "$response" ]; then
            echo "❌ EMPTY RESPONSE"
            echo "Error: No response from validation endpoint"
            exit 1
        fi

        # Check if validation passed
        is_valid=$(echo "$response" | jq -r '.data.is_valid // false')
        parse_error=$?

        if [ $parse_error -ne 0 ]; then
            echo "❌ INVALID JSON RESPONSE"
            echo "Raw response:"
            echo "$response"
            exit 1
        fi

        if [ "$is_valid" = "true" ]; then
            echo "✅ VALID"
        else
            echo "❌ INVALID"
            echo "Error response:"
            echo "$response" | jq '.' 2>/dev/null || echo "$response"
            exit 1
        fi
    fi
done

echo "✅ All Lua scripts validated successfully"
