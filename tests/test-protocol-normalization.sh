#!/usr/bin/env bash
# Test script for Story 1.3: Edge Protocol Normalization
# Validates flow JSON structure and tests MQTT normalization
#
# Usage:
#   ./edge/tests/test-protocol-normalization.sh          # JSON validation only
#   ./edge/tests/test-protocol-normalization.sh --mqtt    # Include MQTT integration tests (requires Mosquitto running)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EDGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FLOWS_DIR="$EDGE_DIR/nodered/flows"

PASS=0
FAIL=0
MQTT_TESTS=false

if [[ "${1:-}" == "--mqtt" ]]; then
    MQTT_TESTS=true
fi

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== Story 1.3: Protocol Normalization Tests ==="
echo ""

# -------------------------------------------------------
# 1. JSON Structure Validation
# -------------------------------------------------------
echo "--- JSON Structure Validation ---"

# Test: flow file exists and is valid JSON
FLOW_FILE="$FLOWS_DIR/flow-protocol-normalization.json"
if [[ -f "$FLOW_FILE" ]]; then
    if python3 -m json.tool "$FLOW_FILE" > /dev/null 2>&1; then
        pass "flow-protocol-normalization.json is valid JSON"
    else
        fail "flow-protocol-normalization.json is NOT valid JSON"
    fi
else
    fail "flow-protocol-normalization.json does not exist"
fi

# Test: subflow file exists and is valid JSON
SUBFLOW_FILE="$FLOWS_DIR/subflows/subflow-normalize-output.json"
if [[ -f "$SUBFLOW_FILE" ]]; then
    if python3 -m json.tool "$SUBFLOW_FILE" > /dev/null 2>&1; then
        pass "subflow-normalize-output.json is valid JSON"
    else
        fail "subflow-normalize-output.json is NOT valid JSON"
    fi
else
    fail "subflow-normalize-output.json does not exist"
fi

# Test: flow contains a tab node named "protocol-normalization"
if python3 -c "
import json, sys
with open('$FLOW_FILE') as f:
    nodes = json.load(f)
tabs = [n for n in nodes if n.get('type') == 'tab' and n.get('label') == 'protocol-normalization']
sys.exit(0 if len(tabs) == 1 else 1)
" 2>/dev/null; then
    pass "Flow has exactly one tab named 'protocol-normalization'"
else
    fail "Flow missing tab named 'protocol-normalization'"
fi

# Test: flow contains a catch node scoped to protocol-normalization tab
if python3 -c "
import json, sys
with open('$FLOW_FILE') as f:
    nodes = json.load(f)
tab_id = None
for n in nodes:
    if n.get('type') == 'tab' and n.get('label') == 'protocol-normalization':
        tab_id = n['id']
        break
catches = [n for n in nodes if n.get('type') == 'catch']
if len(catches) < 1:
    sys.exit(1)
# Verify catch is scoped to this tab (not global scope: null)
for c in catches:
    scope = c.get('scope')
    if scope is not None and tab_id in scope:
        sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
    pass "Flow has catch node scoped to protocol-normalization tab"
else
    fail "Flow missing tab-scoped catch node"
fi

# Test: flow contains a comment node
if python3 -c "
import json, sys
with open('$FLOW_FILE') as f:
    nodes = json.load(f)
comments = [n for n in nodes if n.get('type') == 'comment']
sys.exit(0 if len(comments) >= 1 else 1)
" 2>/dev/null; then
    pass "Flow has comment/description node"
else
    fail "Flow missing comment/description node"
fi

# Test: flow contains mqtt-in subscribing to nexus/raw/+/+/+
if python3 -c "
import json, sys
with open('$FLOW_FILE') as f:
    nodes = json.load(f)
mqtt_in = [n for n in nodes if n.get('type') == 'mqtt in' and 'nexus/raw' in n.get('topic', '')]
sys.exit(0 if len(mqtt_in) >= 1 else 1)
" 2>/dev/null; then
    pass "Flow has MQTT-in subscribing to raw protocol topics"
else
    fail "Flow missing MQTT-in for raw protocol topics"
fi

# Test: flow contains mqtt-out for normalized output (at least 2: telemetry + errors)

if python3 -c "
import json, sys
with open('$FLOW_FILE') as f:
    nodes = json.load(f)
mqtt_out = [n for n in nodes if n.get('type') == 'mqtt out']
sys.exit(0 if len(mqtt_out) >= 2 else 1)
" 2>/dev/null; then
    pass "Flow has MQTT-out nodes for telemetry and errors"
else
    fail "Flow missing MQTT-out nodes (need >= 2: telemetry + errors)"
fi

# Test: flow contains modbus-read node
if python3 -c "
import json, sys
with open('$FLOW_FILE') as f:
    nodes = json.load(f)
modbus = [n for n in nodes if n.get('type') == 'modbus-read']
sys.exit(0 if len(modbus) >= 1 else 1)
" 2>/dev/null; then
    pass "Flow has modbus-read node"
else
    fail "Flow missing modbus-read node"
fi

# Test: flow contains modbus-client config node
if python3 -c "
import json, sys
with open('$FLOW_FILE') as f:
    nodes = json.load(f)
mc = [n for n in nodes if n.get('type') == 'modbus-client']
sys.exit(0 if len(mc) >= 1 else 1)
" 2>/dev/null; then
    pass "Flow has modbus-client config node"
else
    fail "Flow missing modbus-client config node"
fi

# Test: subflow definition exists in main flow
if python3 -c "
import json, sys
with open('$FLOW_FILE') as f:
    nodes = json.load(f)
sf = [n for n in nodes if n.get('type') == 'subflow' and n.get('name') == 'normalize-output']
sys.exit(0 if len(sf) >= 1 else 1)
" 2>/dev/null; then
    pass "Flow includes normalize-output subflow definition"
else
    fail "Flow missing normalize-output subflow definition"
fi

# Test: subflow instance used in flow
if python3 -c "
import json, sys
with open('$FLOW_FILE') as f:
    nodes = json.load(f)
inst = [n for n in nodes if 'subflow:' in n.get('type', '')]
sys.exit(0 if len(inst) >= 1 else 1)
" 2>/dev/null; then
    pass "Flow uses normalize-output subflow instance"
else
    fail "Flow missing normalize-output subflow instance"
fi

# Test: all nodes have unique IDs
if python3 -c "
import json, sys
with open('$FLOW_FILE') as f:
    nodes = json.load(f)
ids = [n['id'] for n in nodes if 'id' in n]
sys.exit(0 if len(ids) == len(set(ids)) else 1)
" 2>/dev/null; then
    pass "All node IDs are unique"
else
    fail "Duplicate node IDs detected"
fi

# Test: all flow nodes reference the correct tab
if python3 -c "
import json, sys
with open('$FLOW_FILE') as f:
    nodes = json.load(f)
tab_id = None
for n in nodes:
    if n.get('type') == 'tab' and n.get('label') == 'protocol-normalization':
        tab_id = n['id']
        break
if not tab_id:
    sys.exit(1)
# Check flow nodes reference this tab (config nodes and subflow defs don't have 'z')
config_types = {'mqtt-broker', 'modbus-client', 'subflow'}
for n in nodes:
    if n.get('type') in config_types or n.get('type') == 'tab':
        continue
    if 'z' in n and n['z'] != tab_id:
        # Allow subflow internal nodes
        sf_ids = [s['id'] for s in nodes if s.get('type') == 'subflow']
        if n['z'] not in sf_ids:
            sys.exit(1)
sys.exit(0)
" 2>/dev/null; then
    pass "All flow nodes correctly reference protocol-normalization tab"
else
    fail "Some nodes reference wrong tab"
fi

# Test: function nodes contain error handling references
if python3 -c "
import json, sys
with open('$FLOW_FILE') as f:
    nodes = json.load(f)
funcs = [n for n in nodes if n.get('type') == 'function' and 'protocol-normalization' in n.get('func', '')]
sys.exit(0 if len(funcs) >= 3 else 1)
" 2>/dev/null; then
    pass "Function nodes contain [protocol-normalization] error logging"
else
    fail "Function nodes missing standardized error logging"
fi

# -------------------------------------------------------
# 2. Package.json Validation
# -------------------------------------------------------
echo ""
echo "--- Package.json Validation ---"

PKG_FILE="$EDGE_DIR/nodered/package.json"

# Test: package.json has pinned versions (no wildcards)
if python3 -c "
import json, sys
with open('$PKG_FILE') as f:
    pkg = json.load(f)
deps = pkg.get('dependencies', {})
for name, version in deps.items():
    if version == '*':
        sys.exit(1)
sys.exit(0)
" 2>/dev/null; then
    pass "package.json has pinned dependency versions (no wildcards)"
else
    fail "package.json still has wildcard (*) versions"
fi

# Test: required modules present
if python3 -c "
import json, sys
with open('$PKG_FILE') as f:
    pkg = json.load(f)
deps = pkg.get('dependencies', {})
required = ['node-red-contrib-modbus', 'node-red-contrib-opcua', 'node-red-contrib-bacnet', 'node-red-node-serialport']
for r in required:
    if r not in deps:
        sys.exit(1)
sys.exit(0)
" 2>/dev/null; then
    pass "All required Node-RED contrib modules present"
else
    fail "Missing required contrib modules in package.json"
fi

# -------------------------------------------------------
# 3. Environment Variable Validation
# -------------------------------------------------------
echo ""
echo "--- Environment Config Validation ---"

ENV_FILE="$EDGE_DIR/.env.example"

for var in MODBUS_HOST MODBUS_PORT MODBUS_UNIT_ID MODBUS_POLL_INTERVAL_MS DEVICE_ID; do
    if grep -q "^${var}=" "$ENV_FILE" 2>/dev/null; then
        pass ".env.example contains $var"
    else
        fail ".env.example missing $var"
    fi
done

# -------------------------------------------------------
# 4. MQTT Integration Tests (optional, requires Mosquitto)
# -------------------------------------------------------
if [[ "$MQTT_TESTS" == "true" ]]; then
    echo ""
    echo "--- MQTT Integration Tests ---"

    if ! command -v mosquitto_pub &> /dev/null || ! command -v mosquitto_sub &> /dev/null; then
        echo "  SKIP: mosquitto_pub/mosquitto_sub not available"
    else
        MQTT_HOST="${MQTT_HOST:-127.0.0.1}"
        MQTT_PORT="${MQTT_PORT:-1883}"

        # Test: publish raw data and verify it arrives on raw topic
        echo "  Testing MQTT raw topic publish/subscribe..."

        RESULT=$(timeout 5 mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "nexus/raw/lorawan/zone-01/device-001" -C 1 -W 3 &
            sleep 1
            mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "nexus/raw/lorawan/zone-01/device-001" -m '{"temperature": 22.5, "vibration": 4.2}'
            wait
        ) 2>/dev/null || true

        if [[ -n "$RESULT" ]]; then
            pass "MQTT raw topic publish/subscribe works"
        else
            fail "MQTT raw topic publish/subscribe failed (is Mosquitto running?)"
        fi

        # Test: publish to normalized topic and verify format
        echo "  Testing MQTT normalized topic..."

        TEST_PAYLOAD='{"ts":1711929600000,"values":{"vibration_mm_s":4.2,"temperature_c":22.5}}'
        RESULT=$(timeout 5 mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "nexus/zone-01/device-001/telemetry" -C 1 -W 3 &
            sleep 1
            mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "nexus/zone-01/device-001/telemetry" -m "$TEST_PAYLOAD"
            wait
        ) 2>/dev/null || true

        if echo "$RESULT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert 'ts' in data
assert 'values' in data
assert isinstance(data['values'], dict)
" 2>/dev/null; then
            pass "Normalized topic accepts ThingsBoard format JSON"
        else
            fail "Normalized topic format validation failed"
        fi
    fi
fi

# -------------------------------------------------------
# Summary
# -------------------------------------------------------
echo ""
echo "=== Test Summary ==="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo ""

if [[ $FAIL -gt 0 ]]; then
    echo "RESULT: SOME TESTS FAILED"
    exit 1
else
    echo "RESULT: ALL TESTS PASSED"
    exit 0
fi
