#!/bin/bash

# Script to validate all example Lua files
API_URL="http://localhost:8787/api/v1/scripts/validate"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXAMPLES_DIR="$SCRIPT_DIR/../../apps/autorun_flutter/lib/examples"

echo "Validating all Lua example scripts..."
echo "================================"

cd "$EXAMPLES_DIR"
for file in *.lua; do
    if [ -f "$file" ]; then
        echo -n "Testing $file... "
        
        # Use jq to properly escape the JSON
        response=$(cat "$file" | jq -Rs '{lua_source: .}' | curl -s -X POST "$API_URL" -H "Content-Type: application/json" -d @-)
        
        # Check if validation passed
        is_valid=$(echo "$response" | jq -r '.data.is_valid // false')
        
        if [ "$is_valid" = "true" ]; then
            echo "✅ VALID"
        else
            echo "❌ INVALID"
            echo "$response" | jq -r '.data.errors[]?' 2>/dev/null || echo "$response" | jq -r '.error' 2>/dev/null
            exit 1
        fi
    fi
done

echo "✅ All Lua scripts validated successfully"