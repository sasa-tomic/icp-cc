#!/bin/bash

# Demo script to show improved static validation capabilities
API_URL="http://localhost:8787/api/v1/scripts/validate"
TIMEOUT_SECONDS=30

# Helper function for making HTTP requests with timeout and error handling
make_request() {
    local payload="$1"
    local response
    local exit_code

    response=$(timeout "$TIMEOUT_SECONDS" curl --fail-with-body -sS -X POST "$API_URL" -H "Content-Type: application/json" -d "$payload")
    exit_code=$?

    if [ $exit_code -eq 124 ]; then
        echo "ERROR: Request timed out after ${TIMEOUT_SECONDS}s"
        return 124
    elif [ $exit_code -ne 0 ]; then
        echo "ERROR: curl failed with exit code $exit_code"
        if [ -n "$response" ]; then
            echo "Response payload:"
            echo "$response"
        fi
        return $exit_code
    fi

    printf '%s\n' "$response"
    return 0
}

echo "🔍 Improved Static Validation Demo"
echo "=================================="
echo

# Test 1: Security Issues (Context-Aware)
echo "🚨 Test 1: Security Issues (Context-Aware)"
echo "Testing real secrets vs demo data..."

echo "   Testing with demo key (should be allowed in example):"
payload='{"lua_source": "-- Example script\\nfunction init(arg) return { api_key = \"demo_key_for_testing\" }, {} end function view(state) return { type = \"text\", props = { text = \"Hello\" } } end function update(msg, state) return state, {} end"}'
response=$(make_request "$payload")
request_exit_code=$?

if [ $request_exit_code -ne 0 ]; then
    echo "   ❌ Request failed: $response"
    exit $request_exit_code
elif [ -z "$response" ]; then
    echo "   ✅ Demo key correctly allowed in example"
else
    echo "   ❌ Demo key incorrectly blocked"
fi

echo "   Testing with real secret (should be blocked):"
payload='{"lua_source": "function init(arg) return { api_key = \"sk-1234567890abcdef1234567890abcdef12345678\" }, {} end function view(state) return { type = \"text\", props = { text = \"Hello\" } } end function update(msg, state) return state, {} end"}'
response=$(make_request "$payload")
request_exit_code=$?

if [ $request_exit_code -ne 0 ]; then
    echo "   ❌ Request failed: $response"
    exit $request_exit_code
elif [ -n "$response" ]; then
    echo "   ✅ Real secret correctly blocked"
    echo "   Error: $response" | sed 's/^/     /'
else
    echo "   ❌ Real secret incorrectly allowed"
fi

echo "   Testing dangerous functions (should be blocked):"
payload='{"lua_source": "function init(arg) return {}, {} end function view(state) return { type = \"text\", props = { text = \"Hello\" } } end function update(msg, state) loadstring(\"print(\\\"hello\\\")\")() return state, {} end"}'
response=$(make_request "$payload")
request_exit_code=$?

if [ $request_exit_code -ne 0 ]; then
    echo "   ❌ Request failed: $response"
    exit $request_exit_code
elif [ -n "$response" ]; then
    echo "   ✅ Dangerous function correctly blocked"
    echo "   Error: $response" | sed 's/^/     /'
else
    echo "   ❌ Dangerous function incorrectly allowed"
fi

echo

# Test 2: Performance Issues (Smart Detection)
echo "⚡ Test 2: Performance Issues (Smart Detection)"
echo "Testing infinite loops with context awareness..."

echo "   Testing legitimate loop with break (should be allowed):"
payload=$(cat <<'EOF'
{"lua_source": "function init(arg) return { counter = 0 }, {} end function view(state) return { type = \"text\", props = { text = \"Counter: \" .. state.counter } } end function update(msg, state) while true do if state.counter > 10 then break end state.counter = state.counter + 1 end return state, {} end"}
EOF
)
response=$(make_request "$payload")
request_exit_code=$?
if [ $request_exit_code -ne 0 ]; then
    echo "   ❌ Request failed: $response"
    exit $request_exit_code
fi
errors=$(echo "$response" | jq -r '.data.errors[]?' 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "   ❌ Invalid JSON response"
    echo "$response"
    exit 1
fi
if [ -z "$errors" ]; then
    echo "   ✅ Legitimate loop correctly allowed"
else
    echo "   ❌ Legitimate loop incorrectly blocked"
    echo "$errors" | sed 's/^/     /'
fi

echo "   Testing real infinite loop (should be blocked):"
payload=$(cat <<'EOF'
{"lua_source": "function init(arg) return {}, {} end function view(state) return { type = \"text\", props = { text = \"Hello\" } } end function update(msg, state) while true do state.counter = (state.counter or 0) + 1 end return state, {} end"}
EOF
)
response=$(make_request "$payload")
request_exit_code=$?
if [ $request_exit_code -ne 0 ]; then
    echo "   ❌ Request failed: $response"
    exit $request_exit_code
fi
errors=$(echo "$response" | jq -r '.data.errors[]?' 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "   ❌ Invalid JSON response"
    echo "$response"
    exit 1
fi
if [ -n "$errors" ]; then
    echo "   ✅ Real infinite loop correctly blocked"
    echo "$errors" | sed 's/^/     /'
else
    echo "   ❌ Real infinite loop incorrectly allowed"
fi
echo

# Test 3: UI Structure Issues
echo "🎨 Test 3: UI Structure Issues"
echo "Testing missing types and invalid UI nodes..."
payload=$(cat <<'EOF'
{"lua_source": "function init(arg) return {}, {} end function view(state) return { type = \"column\", children = { state.show_error and { props = { text = \"Error\" } } } } end function update(msg, state) return state, {} end"}
EOF
)
response=$(make_request "$payload")
request_exit_code=$?
if [ $request_exit_code -ne 0 ]; then
    echo "   ❌ Request failed: $response"
    exit $request_exit_code
fi
errors=$(echo "$response" | jq -r '.data.errors[]?' 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "   ❌ Invalid JSON response"
    echo "$response"
    exit 1
fi

if [ -n "$errors" ]; then
    echo "✅ Caught UI structure issues:"
    echo "$errors" | sed 's/^/   - /'
else
    echo "❌ Failed to catch UI structure issues"
fi
echo

# Test 4: Event Handler Issues
echo "🔄 Test 4: Event Handler Issues"
echo "Testing unmatched event handlers..."
payload=$(cat <<'EOF'
{"lua_source": "function init(arg) return {}, {} end function view(state) return { type = \"column\", children = { { type = \"button\", props = { on_press = { type = \"my_action\" } } } } } end function update(msg, state) if msg.type == \"other_action\" then return state, {} end return state, {} end"}
EOF
)
response=$(make_request "$payload")
request_exit_code=$?
if [ $request_exit_code -ne 0 ]; then
    echo "   ❌ Request failed: $response"
    exit $request_exit_code
fi
warnings=$(echo "$response" | jq -r '.data.warnings[]?' 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "   ❌ Invalid JSON response"
    echo "$response"
    exit 1
fi

if [ -n "$warnings" ]; then
    echo "✅ Caught event handler issues:"
    echo "$warnings" | sed 's/^/   - /'
else
    echo "❌ Failed to catch event handler issues"
fi
echo

# Test 5: ICP Integration Issues (Context-Aware)
echo "🔗 Test 5: ICP Integration Issues (Context-Aware)"
echo "Testing canister ID validation with context..."

echo "   Testing test canister ID in example (should be allowed):"
payload=$(cat <<'EOF'
{"lua_source": "-- Example script\nfunction init(arg) return {}, {} end function view(state) return { type = \"text\", props = { text = \"Hello\" } } end function update(msg, state) return state, { { kind = \"icp_call\", id = \"test\", call = { canister_id = \"test-canister\", method = \"test\", kind = 0 } } } end"}
EOF
)
response=$(make_request "$payload")
request_exit_code=$?
if [ $request_exit_code -ne 0 ]; then
    echo "   ❌ Request failed: $response"
    exit $request_exit_code
fi
errors=$(echo "$response" | jq -r '.data.errors[]?' 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "   ❌ Invalid JSON response"
    echo "$response"
    exit 1
fi
if [ -z "$errors" ]; then
    echo "   ✅ Test canister ID correctly allowed in example"
else
    echo "   ❌ Test canister ID incorrectly blocked"
    echo "$errors" | sed 's/^/     /'
fi

echo "   Testing invalid canister ID in production (should be blocked):"
payload=$(cat <<'EOF'
{"lua_source": "function init(arg) return {}, {} end function view(state) return { type = \"text\", props = { text = \"Hello\" } } end function update(msg, state) return state, { { kind = \"icp_call\", id = \"test\", call = { canister_id = \"invalid-id\", method = \"test\", kind = 0 } } } end"}
EOF
)
response=$(make_request "$payload")
request_exit_code=$?
if [ $request_exit_code -ne 0 ]; then
    echo "   ❌ Request failed: $response"
    exit $request_exit_code
fi
errors=$(echo "$response" | jq -r '.data.errors[]?' 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "   ❌ Invalid JSON response"
    echo "$response"
    exit 1
fi
if [ -n "$errors" ]; then
    echo "   ✅ Invalid canister ID correctly blocked"
    echo "$errors" | sed 's/^/     /'
else
    echo "   ❌ Invalid canister ID incorrectly allowed"
fi
echo

echo "🎉 Improved validation demo completed!"
echo "These validations prevent runtime errors before script execution."
