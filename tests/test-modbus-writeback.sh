#!/usr/bin/env bash
# test-modbus-writeback.sh — Flow structure validation for flow-modbus-writeback.json
# Tests validate JSON structure, required nodes, MQTT topics, and error handling patterns.
# Does NOT require running Node-RED or Modbus devices.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOW_FILE="$SCRIPT_DIR/../nodered/flows/flow-modbus-writeback.json"
DOCKER_COMPOSE="$SCRIPT_DIR/../docker-compose.yml"

PASS=0
FAIL=0
TOTAL=0

pass() { ((PASS++)); ((TOTAL++)); echo "  ✅ $1"; }
fail() { ((FAIL++)); ((TOTAL++)); echo "  ❌ $1"; }

check_json() {
    local desc="$1"
    local query="$2"
    local expected="$3"
    local result
    result=$(python3 -c "
import json, sys
with open('$FLOW_FILE') as f:
    data = json.load(f)
$query
" 2>/dev/null) || { fail "$desc (python error)"; return; }
    if [ "$result" = "$expected" ]; then
        pass "$desc"
    else
        fail "$desc (expected '$expected', got '$result')"
    fi
}

check_json_contains() {
    local desc="$1"
    local query="$2"
    local expected="$3"
    local result
    result=$(python3 -c "
import json, sys
with open('$FLOW_FILE') as f:
    data = json.load(f)
$query
" 2>/dev/null) || { fail "$desc (python error)"; return; }
    if echo "$result" | grep -q "$expected"; then
        pass "$desc"
    else
        fail "$desc (expected to contain '$expected', got '$result')"
    fi
}

check_json_exists() {
    local desc="$1"
    local query="$2"
    local result
    result=$(python3 -c "
import json, sys
with open('$FLOW_FILE') as f:
    data = json.load(f)
$query
" 2>/dev/null) || { fail "$desc (python error)"; return; }
    if [ -n "$result" ] && [ "$result" != "0" ] && [ "$result" != "False" ] && [ "$result" != "None" ]; then
        pass "$desc"
    else
        fail "$desc (empty or falsy result)"
    fi
}

echo ""
echo "=== Modbus Write-Back Flow Structure Tests ==="
echo "Flow file: $FLOW_FILE"
echo ""

# --- File exists and is valid JSON ---
echo "--- Basic Structure ---"

if [ -f "$FLOW_FILE" ]; then
    pass "Flow file exists"
else
    fail "Flow file exists"
    echo "FATAL: Flow file not found. Aborting."
    exit 1
fi

if python3 -c "import json; json.load(open('$FLOW_FILE'))" 2>/dev/null; then
    pass "Flow file is valid JSON"
else
    fail "Flow file is valid JSON"
    echo "FATAL: Invalid JSON. Aborting."
    exit 1
fi

# --- Tab node ---
echo ""
echo "--- Flow Tab ---"

check_json "Has tab node with label 'modbus-writeback'" \
    "tabs = [n for n in data if n.get('type') == 'tab' and n.get('label') == 'modbus-writeback']; print(len(tabs))" \
    "1"

check_json_contains "Tab info contains FR49" \
    "tab = next(n for n in data if n.get('type') == 'tab'); print(tab.get('info', ''))" \
    "FR49"

# --- Comment/info node ---
echo ""
echo "--- Info Node ---"

check_json_exists "Has comment/info node" \
    "comments = [n for n in data if n.get('type') == 'comment']; print(len(comments))"

check_json_contains "Info node references modbus-writeback" \
    "c = next(n for n in data if n.get('type') == 'comment'); print(c.get('name', ''))" \
    "modbus-writeback"

# --- MQTT In nodes (2 subscriptions) ---
echo ""
echo "--- MQTT Input Nodes ---"

TAB_ID=$(python3 -c "
import json
with open('$FLOW_FILE') as f:
    data = json.load(f)
tab = next(n for n in data if n.get('type') == 'tab')
print(tab['id'])
" 2>/dev/null)

check_json "Has 2 MQTT In nodes" \
    "mqtt_in = [n for n in data if n.get('type') == 'mqtt in' and n.get('z') == '$TAB_ID']; print(len(mqtt_in))" \
    "2"

check_json_exists "MQTT In subscribes to nexus/internal/iec104-command" \
    "nodes = [n for n in data if n.get('type') == 'mqtt in' and 'iec104-command' in n.get('topic', '')]; print(len(nodes))"

check_json_exists "MQTT In subscribes to nexus/+/+/command" \
    "nodes = [n for n in data if n.get('type') == 'mqtt in' and 'nexus/+/+/command' in n.get('topic', '')]; print(len(nodes))"

# --- Normalization functions ---
echo ""
echo "--- Command Normalization ---"

check_json_exists "Has normalize-iec104-cmd function" \
    "nodes = [n for n in data if n.get('type') == 'function' and 'normalize-iec104' in n.get('name', '')]; print(len(nodes))"

check_json_exists "Has normalize-device-cmd function" \
    "nodes = [n for n in data if n.get('type') == 'function' and 'normalize-device' in n.get('name', '')]; print(len(nodes))"

# --- Validation function ---
echo ""
echo "--- Command Validation ---"

check_json_exists "Has validate-command function" \
    "nodes = [n for n in data if n.get('type') == 'function' and 'validate-command' in n.get('name', '')]; print(len(nodes))"

check_json_contains "validate-command checks device_id" \
    "node = next(n for n in data if n.get('name') == 'validate-command'); print(node.get('func', ''))" \
    "device_id"

check_json_contains "validate-command checks value range" \
    "node = next(n for n in data if n.get('name') == 'validate-command'); print(node.get('func', ''))" \
    "MODBUS_EXPORT_LIMIT_MIN"

check_json_contains "validate-command checks device registry" \
    "node = next(n for n in data if n.get('name') == 'validate-command'); print(node.get('func', ''))" \
    "deviceRegistry"

check_json_contains "validate-command checks supported actions" \
    "node = next(n for n in data if n.get('name') == 'validate-command'); print(node.get('func', ''))" \
    "set_export_limit_kw"

check_json "validate-command has 2 outputs (valid, error)" \
    "node = next(n for n in data if n.get('name') == 'validate-command'); print(node.get('outputs'))" \
    "2"

# --- Device registry init ---
echo ""
echo "--- Device Registry ---"

check_json_exists "Has init-device-registry function" \
    "nodes = [n for n in data if n.get('type') == 'function' and 'init-device-registry' in n.get('name', '')]; print(len(nodes))"

check_json_exists "Has inject node for registry init" \
    "nodes = [n for n in data if n.get('type') == 'inject' and n.get('z') == '$TAB_ID']; print(len(nodes))"

check_json_contains "Registry init stores deviceRegistry in flow context" \
    "node = next(n for n in data if n.get('name') == 'init-device-registry'); print(node.get('func', ''))" \
    "flow.set"

check_json_contains "Registry init stores actionMap in flow context" \
    "node = next(n for n in data if n.get('name') == 'init-device-registry'); print(node.get('func', ''))" \
    "actionMap"

# --- Modbus Write node ---
echo ""
echo "--- Modbus Write ---"

check_json_exists "Has modbus-write node" \
    "nodes = [n for n in data if n.get('type') == 'modbus-write']; print(len(nodes))"

check_json "modbus-write references shared Modbus TCP client config" \
    "node = next(n for n in data if n.get('type') == 'modbus-write'); print(node.get('server', ''))" \
    "pn01a0b0c0d0e0cc"

# --- Modbus Read-back node ---
echo ""
echo "--- Read-Back Verification ---"

check_json_exists "Has modbus-read node for read-back" \
    "nodes = [n for n in data if n.get('type') == 'modbus-read' and n.get('z') == '$TAB_ID']; print(len(nodes))"

check_json_exists "Has verify-readback function" \
    "nodes = [n for n in data if n.get('type') == 'function' and 'verify-readback' in n.get('name', '')]; print(len(nodes))"

check_json "verify-readback has 2 outputs (match, mismatch)" \
    "node = next(n for n in data if n.get('name') == 'verify-readback'); print(node.get('outputs'))" \
    "2"

# --- Retry logic ---
echo ""
echo "--- Retry Logic ---"

check_json_exists "Has retry-handler function" \
    "nodes = [n for n in data if n.get('type') == 'function' and 'retry-handler' in n.get('name', '')]; print(len(nodes))"

check_json "retry-handler has 2 outputs (retry, error)" \
    "node = next(n for n in data if n.get('name') == 'retry-handler'); print(node.get('outputs'))" \
    "2"

check_json_contains "retry-handler limits to 1 retry" \
    "node = next(n for n in data if n.get('name') == 'retry-handler'); print(node.get('func', ''))" \
    "maxRetries"

check_json_exists "Has delay node for retry" \
    "nodes = [n for n in data if n.get('type') == 'delay' and n.get('z') == '$TAB_ID']; print(len(nodes))"

# --- MQTT Output nodes ---
echo ""
echo "--- MQTT Output ---"

MQTT_OUT_COUNT=$(python3 -c "
import json
with open('$FLOW_FILE') as f:
    data = json.load(f)
count = len([n for n in data if n.get('type') == 'mqtt out' and n.get('z') == '$TAB_ID'])
print(count)
" 2>/dev/null)

if [ "$MQTT_OUT_COUNT" -ge 3 ]; then
    pass "Has at least 3 MQTT Out nodes (status, errors, telemetry)"
else
    fail "Has at least 3 MQTT Out nodes (expected >=3, got $MQTT_OUT_COUNT)"
fi

check_json_exists "Has MQTT Out for writeback-status" \
    "nodes = [n for n in data if n.get('type') == 'mqtt out' and 'Status' in n.get('name', '')]; print(len(nodes))"

check_json_exists "Has MQTT Out for writeback-errors" \
    "nodes = [n for n in data if n.get('type') == 'mqtt out' and 'Error' in n.get('name', '')]; print(len(nodes))"

check_json_exists "Has MQTT Out for telemetry update" \
    "nodes = [n for n in data if n.get('type') == 'mqtt out' and 'Telemetry' in n.get('name', '')]; print(len(nodes))"

# --- MQTT broker reference ---
echo ""
echo "--- MQTT Broker Config ---"

check_json "All MQTT nodes reference shared broker pn01a0b0c0d0e0bb" \
    "
mqtt_nodes = [n for n in data if n.get('type') in ('mqtt in', 'mqtt out') and n.get('z') == '$TAB_ID']
all_shared = all(n.get('broker') == 'pn01a0b0c0d0e0bb' for n in mqtt_nodes)
print(all_shared)
" \
    "True"

# --- Error handling ---
echo ""
echo "--- Error Handling ---"

check_json_exists "Has catch node" \
    "nodes = [n for n in data if n.get('type') == 'catch' and n.get('z') == '$TAB_ID']; print(len(nodes))"

check_json_exists "Has error-log function" \
    "nodes = [n for n in data if n.get('type') == 'function' and n.get('name') == 'error-log' and n.get('z') == '$TAB_ID']; print(len(nodes))"

check_json_contains "error-log uses [modbus-writeback] prefix" \
    "node = next(n for n in data if n.get('name') == 'error-log' and n.get('z') == '$TAB_ID'); print(node.get('func', ''))" \
    "modbus-writeback"

check_json_contains "error-log publishes to writeback-errors topic" \
    "node = next(n for n in data if n.get('name') == 'error-log' and n.get('z') == '$TAB_ID'); print(node.get('func', ''))" \
    "writeback-errors"

# --- Debug nodes ---
echo ""
echo "--- Debug Nodes ---"

DEBUG_COUNT=$(python3 -c "
import json
with open('$FLOW_FILE') as f:
    data = json.load(f)
count = len([n for n in data if n.get('type') == 'debug' and n.get('z') == '$TAB_ID'])
print(count)
" 2>/dev/null)

if [ "$DEBUG_COUNT" -ge 2 ]; then
    pass "Has at least 2 debug nodes (confirmation + error)"
else
    fail "Has at least 2 debug nodes (expected >=2, got $DEBUG_COUNT)"
fi

# --- Confirmation function ---
echo ""
echo "--- Confirmation & Telemetry ---"

check_json_exists "Has build-confirmation function" \
    "nodes = [n for n in data if n.get('type') == 'function' and 'build-confirmation' in n.get('name', '')]; print(len(nodes))"

check_json "build-confirmation has 2 outputs (status, telemetry)" \
    "node = next(n for n in data if n.get('name') == 'build-confirmation'); print(node.get('outputs'))" \
    "2"

check_json_contains "build-confirmation publishes to writeback-status topic" \
    "node = next(n for n in data if n.get('name') == 'build-confirmation'); print(node.get('func', ''))" \
    "writeback-status"

check_json_contains "build-confirmation publishes telemetry with export_limit_kw" \
    "node = next(n for n in data if n.get('name') == 'build-confirmation'); print(node.get('func', ''))" \
    "export_limit_kw"

# --- Docker Compose env vars ---
echo ""
echo "--- Docker Compose Environment ---"

if [ -f "$DOCKER_COMPOSE" ]; then
    if grep -q "MODBUS_EXPORT_LIMIT_MIN" "$DOCKER_COMPOSE"; then
        pass "docker-compose.yml has MODBUS_EXPORT_LIMIT_MIN"
    else
        fail "docker-compose.yml has MODBUS_EXPORT_LIMIT_MIN"
    fi

    if grep -q "MODBUS_EXPORT_LIMIT_MAX" "$DOCKER_COMPOSE"; then
        pass "docker-compose.yml has MODBUS_EXPORT_LIMIT_MAX"
    else
        fail "docker-compose.yml has MODBUS_EXPORT_LIMIT_MAX"
    fi

    # MODBUS_WRITE_TIMEOUT_MS removed — env var was unused (code review fix H2)

    if python3 -c "
import json
with open('$FLOW_FILE') as f:
    data = json.load(f)
nodes = [n for n in data if n.get('type') == 'function' and 'prepare-readback' in n.get('name', '')]
print(len(nodes))
" 2>/dev/null | grep -q "1"; then
        pass "Has prepare-readback function node (review fix H3)"
    else
        fail "Has prepare-readback function node (review fix H3)"
    fi
else
    fail "docker-compose.yml not found"
fi

# --- Node wiring validation ---
echo ""
echo "--- Node Wiring ---"

check_json_exists "IEC104 Commands MQTT In is wired to normalize-iec104-cmd" \
    "
mqtt_in = next(n for n in data if n.get('type') == 'mqtt in' and 'iec104' in n.get('name', '').lower())
target_id = mqtt_in.get('wires', [[]])[0][0] if mqtt_in.get('wires', [[]]) and mqtt_in['wires'][0] else ''
target = next((n for n in data if n.get('id') == target_id), None)
print(target.get('name', '') if target else '')
"

check_json_exists "Device Commands MQTT In is wired to normalize-device-cmd" \
    "
mqtt_in = next(n for n in data if n.get('type') == 'mqtt in' and 'Device' in n.get('name', ''))
target_id = mqtt_in.get('wires', [[]])[0][0] if mqtt_in.get('wires', [[]]) and mqtt_in['wires'][0] else ''
target = next((n for n in data if n.get('id') == target_id), None)
print(target.get('name', '') if target else '')
"

# --- Summary ---
echo ""
echo "=== Results ==="
echo "Passed: $PASS / $TOTAL"
echo "Failed: $FAIL / $TOTAL"
echo ""

if [ "$FAIL" -gt 0 ]; then
    echo "❌ SOME TESTS FAILED"
    exit 1
else
    echo "✅ ALL TESTS PASSED"
    exit 0
fi
