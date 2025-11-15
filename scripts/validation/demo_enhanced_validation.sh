#!/bin/bash

# Demo script to show enhanced static validation capabilities
API_URL="http://localhost:8787/api/v1/scripts/validate"

echo "🔍 Enhanced Static Validation Demo"
echo "=================================="
echo

# Test 1: Security Issues (Context-Aware)
echo "🚨 Test 1: Security Issues (Context-Aware)"
echo "Testing real secrets vs demo data..."

echo "   Testing with demo key (should be allowed in example):"
response=$(cat << 'EOF' | curl -s -X POST "$API_URL" -H "Content-Type: application/json" -d @- | jq -r '.data.errors[]?'
{
  "lua_source": "-- Example script\nfunction init(arg) return { api_key = \"demo_key_for_testing\" }, {} end function view(state) return { type = \"text\", props = { text = \"Hello\" } } end function update(msg, state) return state, {} end"
}
EOF
)
if [ -z "$response" ]; then
    echo "   ✅ Demo key correctly allowed in example"
else
    echo "   ❌ Demo key incorrectly blocked"
fi

echo "   Testing with real secret (should be blocked):"
response=$(cat << 'EOF' | curl -s -X POST "$API_URL" -H "Content-Type: application/json" -d @- | jq -r '.data.errors[]?'
{
  "lua_source": "function init(arg) return { api_key = \"sk-1234567890abcdef1234567890abcdef12345678\" }, {} end function view(state) return { type = \"text\", props = { text = \"Hello\" } } end function update(msg, state) return state, {} end"
}
EOF
)
if [ -n "$response" ]; then
    echo "   ✅ Real secret correctly blocked"
    echo "   Error: $response" | sed 's/^/     /'
else
    echo "   ❌ Real secret incorrectly allowed"
fi

echo "   Testing dangerous functions (should be blocked):"
response=$(cat << 'EOF' | curl -s -X POST "$API_URL" -H "Content-Type: application/json" -d @- | jq -r '.data.errors[]?'
{
  "lua_source": "function init(arg) return {}, {} end function view(state) return { type = \"text\", props = { text = \"Hello\" } } end function update(msg, state) loadstring(\"print(\\\"hello\\\")\")() return state, {} end"
}
EOF
)
if [ -n "$response" ]; then
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
response=$(cat << 'EOF' | curl -s -X POST "$API_URL" -H "Content-Type: application/json" -d @- | jq -r '.data.errors[]?'
{
  "lua_source": "function init(arg) return { counter = 0 }, {} end function view(state) return { type = \"text\", props = { text = \"Counter: \" .. state.counter } } end function update(msg, state) while true do if state.counter > 10 then break end state.counter = state.counter + 1 end return state, {} end"
}
EOF
)
if [ -z "$response" ]; then
    echo "   ✅ Legitimate loop correctly allowed"
else
    echo "   ❌ Legitimate loop incorrectly blocked"
fi

echo "   Testing real infinite loop (should be blocked):"
response=$(cat << 'EOF' | curl -s -X POST "$API_URL" -H "Content-Type: application/json" -d @- | jq -r '.data.errors[]?'
{
  "lua_source": "function init(arg) return {}, {} end function view(state) return { type = \"text\", props = { text = \"Hello\" } } end function update(msg, state) while true do state.counter = (state.counter or 0) + 1 end return state, {} end"
}
EOF
)
if [ -n "$response" ]; then
    echo "   ✅ Real infinite loop correctly blocked"
    echo "   Error: $response" | sed 's/^/     /'
else
    echo "   ❌ Real infinite loop incorrectly allowed"
fi
echo

# Test 3: UI Structure Issues
echo "🎨 Test 3: UI Structure Issues"
echo "Testing missing types and invalid UI nodes..."
response=$(cat << 'EOF' | curl -s -X POST "$API_URL" -H "Content-Type: application/json" -d @- | jq -r '.data.errors[]?'
{
  "lua_source": "function init(arg) return {}, {} end function view(state) return { type = \"column\", children = { state.show_error and { props = { text = \"Error\" } } } } end function update(msg, state) return state, {} end"
}
EOF
)

if [ -n "$response" ]; then
    echo "✅ Caught UI structure issues:"
    echo "$response" | sed 's/^/   - /'
else
    echo "❌ Failed to catch UI structure issues"
fi
echo

# Test 4: Event Handler Issues
echo "🔄 Test 4: Event Handler Issues"
echo "Testing unmatched event handlers..."
response=$(cat << 'EOF' | curl -s -X POST "$API_URL" -H "Content-Type: application/json" -d @- | jq -r '.data.warnings[]?'
{
  "lua_source": "function init(arg) return {}, {} end function view(state) return { type = \"column\", children = { { type = \"button\", props = { on_press = { type = \"my_action\" } } } } } end function update(msg, state) if msg.type == \"other_action\" then return state, {} end return state, {} end"
}
EOF
)

if [ -n "$response" ]; then
    echo "✅ Caught event handler issues:"
    echo "$response" | sed 's/^/   - /'
else
    echo "❌ Failed to catch event handler issues"
fi
echo

# Test 5: ICP Integration Issues (Context-Aware)
echo "🔗 Test 5: ICP Integration Issues (Context-Aware)"
echo "Testing canister ID validation with context..."

echo "   Testing test canister ID in example (should be allowed):"
response=$(cat << 'EOF' | curl -s -X POST "$API_URL" -H "Content-Type: application/json" -d @- | jq -r '.data.errors[]?'
{
  "lua_source": "-- Example script\nfunction init(arg) return {}, {} end function view(state) return { type = \"text\", props = { text = \"Hello\" } } end function update(msg, state) return state, { { kind = \"icp_call\", id = \"test\", call = { canister_id = \"test-canister\", method = \"test\", kind = 0 } } } end"
}
EOF
)
if [ -z "$response" ]; then
    echo "   ✅ Test canister ID correctly allowed in example"
else
    echo "   ❌ Test canister ID incorrectly blocked"
fi

echo "   Testing invalid canister ID in production (should be blocked):"
response=$(cat << 'EOF' | curl -s -X POST "$API_URL" -H "Content-Type: application/json" -d @- | jq -r '.data.errors[]?'
{
  "lua_source": "function init(arg) return {}, {} end function view(state) return { type = \"text\", props = { text = \"Hello\" } } end function update(msg, state) return state, { { kind = \"icp_call\", id = \"test\", call = { canister_id = \"invalid-id\", method = \"test\", kind = 0 } } } end"
}
EOF
)
if [ -n "$response" ]; then
    echo "   ✅ Invalid canister ID correctly blocked"
    echo "   Error: $response" | sed 's/^/     /'
else
    echo "   ❌ Invalid canister ID incorrectly allowed"
fi
echo

echo "🎉 Enhanced validation demo completed!"
echo "These validations prevent runtime errors before script execution."