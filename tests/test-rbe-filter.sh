#!/usr/bin/env bash
# test-rbe-filter.sh — Structure validation for subflow-rbe-filter.json and integration
# Tests validate JSON structure, subflow definition, wiring, and configuration.
# Does NOT require running Node-RED.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBFLOW_FILE="$SCRIPT_DIR/../nodered/flows/subflows/subflow-rbe-filter.json"
NORM_FLOW_FILE="$SCRIPT_DIR/../nodered/flows/flow-protocol-normalization.json"
HEALTH_FLOW_FILE="$SCRIPT_DIR/../nodered/flows/flow-gateway-health.json"
DOCKER_COMPOSE="$SCRIPT_DIR/../docker-compose.yml"

PASS=0
FAIL=0
TOTAL=0

pass() { ((PASS++)); ((TOTAL++)); echo "  ✅ $1"; }
fail() { ((FAIL++)); ((TOTAL++)); echo "  ❌ $1"; }

# Generic JSON check helper using python3
check_json() {
    local desc="$1"
    local file="$2"
    local query="$3"
    local expected="$4"
    local result
    result=$(python3 -c "
import json, sys
with open('$file') as f:
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
    local file="$2"
    local query="$3"
    local expected="$4"
    local result
    result=$(python3 -c "
import json, sys
with open('$file') as f:
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
    local file="$2"
    local query="$3"
    local result
    result=$(python3 -c "
import json, sys
with open('$file') as f:
    data = json.load(f)
$query
" 2>/dev/null) || { fail "$desc (python error)"; return; }
    if [ "$result" = "True" ]; then
        pass "$desc"
    else
        fail "$desc (not found)"
    fi
}

echo ""
echo "========================================="
echo "  RBE Filter — Structure Validation"
echo "========================================="
echo ""

# ─── Section 1: Subflow file exists and is valid JSON ───
echo "── Section 1: Subflow File Structure ──"

if [ -f "$SUBFLOW_FILE" ]; then
    pass "Subflow file exists at subflows/subflow-rbe-filter.json"
else
    fail "Subflow file missing at subflows/subflow-rbe-filter.json"
    echo ""
    echo "FATAL: Cannot continue without subflow file"
    echo "Results: $PASS passed, $FAIL failed, $TOTAL total"
    exit 1
fi

python3 -c "import json; json.load(open('$SUBFLOW_FILE'))" 2>/dev/null && \
    pass "Subflow file is valid JSON" || fail "Subflow file is invalid JSON"

# ─── Section 2: Subflow definition ───
echo ""
echo "── Section 2: Subflow Definition ──"

check_json "Subflow ID is sf02a0b0c0d0e0f0" "$SUBFLOW_FILE" \
    "print([n['id'] for n in data if n.get('type') == 'subflow'][0])" \
    "sf02a0b0c0d0e0f0"

check_json "Subflow type is 'subflow'" "$SUBFLOW_FILE" \
    "print([n['type'] for n in data if n['id'] == 'sf02a0b0c0d0e0f0'][0])" \
    "subflow"

check_json "Subflow name is 'rbe-filter'" "$SUBFLOW_FILE" \
    "print([n['name'] for n in data if n['id'] == 'sf02a0b0c0d0e0f0'][0])" \
    "rbe-filter"

check_json "Subflow category is 'template-node-red-pi'" "$SUBFLOW_FILE" \
    "print([n['category'] for n in data if n['id'] == 'sf02a0b0c0d0e0f0'][0])" \
    "template-node-red-pi"

check_json "Subflow icon is font-awesome/fa-filter" "$SUBFLOW_FILE" \
    "print([n['icon'] for n in data if n['id'] == 'sf02a0b0c0d0e0f0'][0])" \
    "font-awesome/fa-filter"

check_json "Subflow has single input port" "$SUBFLOW_FILE" \
    "sf = [n for n in data if n['id'] == 'sf02a0b0c0d0e0f0'][0]
print(len(sf.get('in', [])))" \
    "1"

check_json "Subflow has single output port" "$SUBFLOW_FILE" \
    "sf = [n for n in data if n['id'] == 'sf02a0b0c0d0e0f0'][0]
print(len(sf.get('out', [])))" \
    "1"

check_json "Subflow input wires to rbe-evaluate function" "$SUBFLOW_FILE" \
    "sf = [n for n in data if n['id'] == 'sf02a0b0c0d0e0f0'][0]
print(sf['in'][0]['wires'][0]['id'])" \
    "sf02a0b0c0d0e0f1"

check_json "Subflow output wires from rbe-evaluate function" "$SUBFLOW_FILE" \
    "sf = [n for n in data if n['id'] == 'sf02a0b0c0d0e0f0'][0]
print(sf['out'][0]['wires'][0]['id'])" \
    "sf02a0b0c0d0e0f1"

check_json_contains "Subflow has info/description" "$SUBFLOW_FILE" \
    "sf = [n for n in data if n['id'] == 'sf02a0b0c0d0e0f0'][0]
print(sf.get('info', ''))" \
    "Report By Exception"

check_json "Subflow has meta.module = template-node-red-pi" "$SUBFLOW_FILE" \
    "sf = [n for n in data if n['id'] == 'sf02a0b0c0d0e0f0'][0]
print(sf.get('meta', {}).get('module', ''))" \
    "template-node-red-pi"

# ─── Section 3: RBE evaluate function node ───
echo ""
echo "── Section 3: RBE Evaluate Function Node ──"

check_json "rbe-evaluate node exists" "$SUBFLOW_FILE" \
    "print(any(n['id'] == 'sf02a0b0c0d0e0f1' for n in data))" \
    "True"

check_json "rbe-evaluate is a function node" "$SUBFLOW_FILE" \
    "print([n['type'] for n in data if n['id'] == 'sf02a0b0c0d0e0f1'][0])" \
    "function"

check_json "rbe-evaluate parent is subflow sf02a0b0c0d0e0f0" "$SUBFLOW_FILE" \
    "print([n['z'] for n in data if n['id'] == 'sf02a0b0c0d0e0f1'][0])" \
    "sf02a0b0c0d0e0f0"

check_json "rbe-evaluate name is 'rbe-evaluate'" "$SUBFLOW_FILE" \
    "print([n['name'] for n in data if n['id'] == 'sf02a0b0c0d0e0f1'][0])" \
    "rbe-evaluate"

check_json "rbe-evaluate has 1 output" "$SUBFLOW_FILE" \
    "print([n['outputs'] for n in data if n['id'] == 'sf02a0b0c0d0e0f1'][0])" \
    "1"

# ─── Section 4: Function logic validation ───
echo ""
echo "── Section 4: RBE Function Logic Checks ──"

check_json_contains "Function checks msg.anomaly bypass (AC #4)" "$SUBFLOW_FILE" \
    "fn = [n for n in data if n['id'] == 'sf02a0b0c0d0e0f1'][0]
print(fn['func'])" \
    "msg.anomaly"

check_json_contains "Function checks msg.critical bypass (AC #4)" "$SUBFLOW_FILE" \
    "fn = [n for n in data if n['id'] == 'sf02a0b0c0d0e0f1'][0]
print(fn['func'])" \
    "msg.critical"

check_json_contains "Function checks for 'alert' key bypass (AC #4)" "$SUBFLOW_FILE" \
    "fn = [n for n in data if n['id'] == 'sf02a0b0c0d0e0f1'][0]
print(fn['func'])" \
    "alert"

check_json_contains "Function checks for 'anomaly' key bypass (AC #4)" "$SUBFLOW_FILE" \
    "fn = [n for n in data if n['id'] == 'sf02a0b0c0d0e0f1'][0]
print(fn['func'])" \
    "anomaly"

check_json_contains "Function reads rbeThresholds from global context (AC #1)" "$SUBFLOW_FILE" \
    "fn = [n for n in data if n['id'] == 'sf02a0b0c0d0e0f1'][0]
print(fn['func'])" \
    "global.get"

check_json_contains "Function reads rbeLastSent from context (AC #1)" "$SUBFLOW_FILE" \
    "fn = [n for n in data if n['id'] == 'sf02a0b0c0d0e0f1'][0]
print(fn['func'])" \
    "rbeLastSent"

check_json_contains "Function uses Math.abs for deadband comparison (AC #2, #3)" "$SUBFLOW_FILE" \
    "fn = [n for n in data if n['id'] == 'sf02a0b0c0d0e0f1'][0]
print(fn['func'])" \
    "Math.abs"

check_json_contains "Function handles first message after restart (AC #5)" "$SUBFLOW_FILE" \
    "fn = [n for n in data if n['id'] == 'sf02a0b0c0d0e0f1'][0]
print(fn['func'])" \
    "undefined"

check_json_contains "Function tracks rbeFilteredCount in global context (AC #6)" "$SUBFLOW_FILE" \
    "fn = [n for n in data if n['id'] == 'sf02a0b0c0d0e0f1'][0]
print(fn['func'])" \
    "global.set"

check_json_contains "Function reads rbeDefaultDeadband (AC #7)" "$SUBFLOW_FILE" \
    "fn = [n for n in data if n['id'] == 'sf02a0b0c0d0e0f1'][0]
print(fn['func'])" \
    "rbeDefaultDeadband"

check_json_contains "Function returns null for all suppressed (AC #3)" "$SUBFLOW_FILE" \
    "fn = [n for n in data if n['id'] == 'sf02a0b0c0d0e0f1'][0]
print(fn['func'])" \
    "return null"

check_json_contains "Function preserves ts in output (AC #2)" "$SUBFLOW_FILE" \
    "fn = [n for n in data if n['id'] == 'sf02a0b0c0d0e0f1'][0]
print(fn['func'])" \
    "payload.ts"

check_json_contains "Function uses error prefix [rbe-filter]" "$SUBFLOW_FILE" \
    "fn = [n for n in data if n['id'] == 'sf02a0b0c0d0e0f1'][0]
print(fn['func'])" \
    "[rbe-filter]"

# ─── Section 5: Protocol-normalization flow integration ───
echo ""
echo "── Section 5: Protocol-Normalization Flow Integration ──"

python3 -c "import json; json.load(open('$NORM_FLOW_FILE'))" 2>/dev/null && \
    pass "Protocol-normalization flow is valid JSON" || fail "Protocol-normalization flow is invalid JSON"

check_json_exists "RBE subflow instance exists in protocol-normalization" "$NORM_FLOW_FILE" \
    "print(any(n['id'] == 'pn01a0b0c0d0e035' for n in data))"

check_json "RBE instance type references subflow sf02a0b0c0d0e0f0" "$NORM_FLOW_FILE" \
    "print([n['type'] for n in data if n['id'] == 'pn01a0b0c0d0e035'][0])" \
    "subflow:sf02a0b0c0d0e0f0"

check_json "RBE instance is on protocol-normalization tab" "$NORM_FLOW_FILE" \
    "print([n['z'] for n in data if n['id'] == 'pn01a0b0c0d0e035'][0])" \
    "pn01a0b0c0d0e000"

check_json "normalize-output wires to RBE filter (not directly to mqtt-out)" "$NORM_FLOW_FILE" \
    "norm = [n for n in data if n['id'] == 'pn01a0b0c0d0e030'][0]
print('pn01a0b0c0d0e035' in norm['wires'][0])" \
    "True"

check_json "RBE filter wires to mqtt-out" "$NORM_FLOW_FILE" \
    "rbe = [n for n in data if n['id'] == 'pn01a0b0c0d0e035'][0]
print('pn01a0b0c0d0e031' in rbe['wires'][0])" \
    "True"

check_json "normalize-output does NOT wire directly to mqtt-out anymore" "$NORM_FLOW_FILE" \
    "norm = [n for n in data if n['id'] == 'pn01a0b0c0d0e030'][0]
print('pn01a0b0c0d0e031' not in norm['wires'][0])" \
    "True"

# ─── Section 6: RBE Config initialization ───
echo ""
echo "── Section 6: RBE Config Initialization ──"

check_json_exists "RBE config inject node exists" "$NORM_FLOW_FILE" \
    "print(any(n['id'] == 'pn01a0b0c0d0e039' for n in data))"

check_json "RBE config inject fires once on deploy" "$NORM_FLOW_FILE" \
    "inj = [n for n in data if n['id'] == 'pn01a0b0c0d0e039'][0]
print(inj.get('once'))" \
    "True"

check_json_exists "RBE config function node exists" "$NORM_FLOW_FILE" \
    "print(any(n['id'] == 'pn01a0b0c0d0e03a' for n in data))"

check_json_contains "Config function reads RBE_DEADBAND_TEMPERATURE_C env var" "$NORM_FLOW_FILE" \
    "fn = [n for n in data if n['id'] == 'pn01a0b0c0d0e03a'][0]
print(fn['func'])" \
    "RBE_DEADBAND_TEMPERATURE_C"

check_json_contains "Config function reads RBE_DEADBAND_VIBRATION_MM_S env var" "$NORM_FLOW_FILE" \
    "fn = [n for n in data if n['id'] == 'pn01a0b0c0d0e03a'][0]
print(fn['func'])" \
    "RBE_DEADBAND_VIBRATION_MM_S"

check_json_contains "Config function reads RBE_DEADBAND_POWER_DRAW_KW env var" "$NORM_FLOW_FILE" \
    "fn = [n for n in data if n['id'] == 'pn01a0b0c0d0e03a'][0]
print(fn['func'])" \
    "RBE_DEADBAND_POWER_DRAW_KW"

check_json_contains "Config function reads RBE_DEADBAND_DEFAULT env var" "$NORM_FLOW_FILE" \
    "fn = [n for n in data if n['id'] == 'pn01a0b0c0d0e03a'][0]
print(fn['func'])" \
    "RBE_DEADBAND_DEFAULT"

check_json_contains "Config function sets rbeThresholds in global context" "$NORM_FLOW_FILE" \
    "fn = [n for n in data if n['id'] == 'pn01a0b0c0d0e03a'][0]
print(fn['func'])" \
    "global.set"

check_json_contains "Config function sets rbeDefaultDeadband in global context" "$NORM_FLOW_FILE" \
    "fn = [n for n in data if n['id'] == 'pn01a0b0c0d0e03a'][0]
print(fn['func'])" \
    "rbeDefaultDeadband"

# ─── Section 7: RBE Stats publishing ───
echo ""
echo "── Section 7: RBE Stats Publishing ──"

check_json_exists "RBE stats inject node exists" "$NORM_FLOW_FILE" \
    "print(any(n['id'] == 'pn01a0b0c0d0e036' for n in data))"

check_json "RBE stats inject repeats every 30s" "$NORM_FLOW_FILE" \
    "inj = [n for n in data if n['id'] == 'pn01a0b0c0d0e036'][0]
print(inj.get('repeat'))" \
    "30"

check_json_exists "RBE stats function node exists" "$NORM_FLOW_FILE" \
    "print(any(n['id'] == 'pn01a0b0c0d0e037' for n in data))"

check_json_contains "Stats function reads rbeFilteredCount from global context" "$NORM_FLOW_FILE" \
    "fn = [n for n in data if n['id'] == 'pn01a0b0c0d0e037'][0]
print(fn['func'])" \
    "rbeFilteredCount"

check_json_contains "Stats function publishes to nexus/internal/rbe-status" "$NORM_FLOW_FILE" \
    "fn = [n for n in data if n['id'] == 'pn01a0b0c0d0e037'][0]
print(fn['func'])" \
    "nexus/internal/rbe-status"

check_json_contains "Stats function resets count after publishing" "$NORM_FLOW_FILE" \
    "fn = [n for n in data if n['id'] == 'pn01a0b0c0d0e037'][0]
print(fn['func'])" \
    "global.set"

check_json_exists "RBE stats MQTT out node exists" "$NORM_FLOW_FILE" \
    "print(any(n['id'] == 'pn01a0b0c0d0e038' for n in data))"

check_json "RBE stats MQTT out uses shared Mosquitto broker" "$NORM_FLOW_FILE" \
    "mqtt = [n for n in data if n['id'] == 'pn01a0b0c0d0e038'][0]
print(mqtt.get('broker'))" \
    "pn01a0b0c0d0e0bb"

# ─── Section 8: Gateway-health flow integration ───
echo ""
echo "── Section 8: Gateway-Health Flow Integration ──"

python3 -c "import json; json.load(open('$HEALTH_FLOW_FILE'))" 2>/dev/null && \
    pass "Gateway-health flow is valid JSON" || fail "Gateway-health flow is invalid JSON"

check_json_exists "RBE status MQTT In node exists in gateway-health" "$HEALTH_FLOW_FILE" \
    "print(any(n['id'] == 'gh01a0b0c0d0e036' for n in data))"

check_json "RBE status MQTT In subscribes to nexus/internal/rbe-status" "$HEALTH_FLOW_FILE" \
    "mqtt = [n for n in data if n['id'] == 'gh01a0b0c0d0e036'][0]
print(mqtt.get('topic'))" \
    "nexus/internal/rbe-status"

check_json "RBE status MQTT In uses shared Mosquitto broker" "$HEALTH_FLOW_FILE" \
    "mqtt = [n for n in data if n['id'] == 'gh01a0b0c0d0e036'][0]
print(mqtt.get('broker'))" \
    "pn01a0b0c0d0e0bb"

check_json_exists "RBE status handler function exists" "$HEALTH_FLOW_FILE" \
    "print(any(n['id'] == 'gh01a0b0c0d0e037' for n in data))"

check_json_contains "RBE status handler stores rbeFilteredCount in global context" "$HEALTH_FLOW_FILE" \
    "fn = [n for n in data if n['id'] == 'gh01a0b0c0d0e037'][0]
print(fn['func'])" \
    "rbeFilteredCount"

check_json_contains "Health aggregator includes rbe_filtered_count in output" "$HEALTH_FLOW_FILE" \
    "fn = [n for n in data if n['id'] == 'gh01a0b0c0d0e020'][0]
print(fn['func'])" \
    "rbe_filtered_count"

check_json_contains "Health aggregator reads rbeFilteredCount from global context" "$HEALTH_FLOW_FILE" \
    "fn = [n for n in data if n['id'] == 'gh01a0b0c0d0e020'][0]
print(fn['func'])" \
    "rbeFilteredCount"

check_json_contains "Health aggregator initializes rbeFilteredCount on deploy" "$HEALTH_FLOW_FILE" \
    "fn = [n for n in data if n['id'] == 'gh01a0b0c0d0e020'][0]
print(fn.get('initialize', ''))" \
    "rbeFilteredCount"

# ─── Section 9: Docker-compose environment variables ───
echo ""
echo "── Section 9: Docker-Compose Environment Variables ──"

grep -q "RBE_DEADBAND_TEMPERATURE_C" "$DOCKER_COMPOSE" && \
    pass "docker-compose has RBE_DEADBAND_TEMPERATURE_C" || fail "docker-compose missing RBE_DEADBAND_TEMPERATURE_C"

grep -q "RBE_DEADBAND_VIBRATION_MM_S" "$DOCKER_COMPOSE" && \
    pass "docker-compose has RBE_DEADBAND_VIBRATION_MM_S" || fail "docker-compose missing RBE_DEADBAND_VIBRATION_MM_S"

grep -q "RBE_DEADBAND_POWER_DRAW_KW" "$DOCKER_COMPOSE" && \
    pass "docker-compose has RBE_DEADBAND_POWER_DRAW_KW" || fail "docker-compose missing RBE_DEADBAND_POWER_DRAW_KW"

grep -q "RBE_DEADBAND_DEFAULT" "$DOCKER_COMPOSE" && \
    pass "docker-compose has RBE_DEADBAND_DEFAULT" || fail "docker-compose missing RBE_DEADBAND_DEFAULT"

grep -q '0\.5' "$DOCKER_COMPOSE" && \
    pass "docker-compose has default value 0.5 for temperature/power deadband" || fail "docker-compose missing default 0.5"

grep -q '0\.1' "$DOCKER_COMPOSE" && \
    pass "docker-compose has default value 0.1 for vibration deadband" || fail "docker-compose missing default 0.1"

# ─── Section 10: No duplicate broker config nodes ───
echo ""
echo "── Section 10: No Duplicate Broker Config Nodes ──"

BROKER_COUNT=$(python3 -c "
import json
with open('$NORM_FLOW_FILE') as f:
    data = json.load(f)
print(len([n for n in data if n.get('type') == 'mqtt-broker']))
" 2>/dev/null)

if [ "$BROKER_COUNT" = "1" ]; then
    pass "Protocol-normalization flow has exactly 1 mqtt-broker config node"
else
    fail "Protocol-normalization flow has $BROKER_COUNT mqtt-broker config nodes (expected 1)"
fi

# Check no new broker nodes in subflow
SUBFLOW_BROKER_COUNT=$(python3 -c "
import json
with open('$SUBFLOW_FILE') as f:
    data = json.load(f)
print(len([n for n in data if n.get('type') == 'mqtt-broker']))
" 2>/dev/null)

if [ "$SUBFLOW_BROKER_COUNT" = "0" ]; then
    pass "RBE subflow has no mqtt-broker config nodes (uses parent flow's broker)"
else
    fail "RBE subflow has $SUBFLOW_BROKER_COUNT mqtt-broker config nodes (expected 0)"
fi

# ─── Section 11: Catch node exists in modified flows ───
echo ""
echo "── Section 11: Error Handling ──"

check_json_exists "Catch node exists in protocol-normalization flow" "$NORM_FLOW_FILE" \
    "print(any(n.get('type') == 'catch' for n in data))"

check_json_exists "Catch node exists in gateway-health flow" "$HEALTH_FLOW_FILE" \
    "print(any(n.get('type') == 'catch' for n in data))"

# ─── Section 12: All normalizer paths converge through RBE ───
echo ""
echo "── Section 12: All Normalizer Paths Converge Through RBE ──"

check_json "generic-normalize wires to normalize-output" "$NORM_FLOW_FILE" \
    "gn = [n for n in data if n['id'] == 'pn01a0b0c0d0e012'][0]
print('pn01a0b0c0d0e030' in gn['wires'][0])" \
    "True"

check_json "modbus-normalize wires to normalize-output" "$NORM_FLOW_FILE" \
    "mn = [n for n in data if n['id'] == 'pn01a0b0c0d0e021'][0]
print('pn01a0b0c0d0e030' in mn['wires'][0])" \
    "True"

check_json "opcua-normalize wires to normalize-output" "$NORM_FLOW_FILE" \
    "on = [n for n in data if n['id'] == 'pn01a0b0c0d0e051'][0]
print('pn01a0b0c0d0e030' in on['wires'][0])" \
    "True"

check_json "bacnet-normalize wires to normalize-output" "$NORM_FLOW_FILE" \
    "bn = [n for n in data if n['id'] == 'pn01a0b0c0d0e061'][0]
print('pn01a0b0c0d0e030' in bn['wires'][0])" \
    "True"

# All paths: normalizer → normalize-output → rbe-filter → mqtt-out
# Already verified: normalize-output → rbe-filter → mqtt-out in Section 5

echo ""
echo "========================================="
echo "  Results: $PASS passed, $FAIL failed, $TOTAL total"
echo "========================================="
echo ""

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
