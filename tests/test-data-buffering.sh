#!/usr/bin/env bash
# Test suite for flow-data-buffering.json (Story 1.5)
# Validates Node-RED flow JSON structure, required nodes, broker reuse, and wiring.
# Usage: bash edge/tests/test-data-buffering.sh

set -euo pipefail

FLOW_FILE="edge/nodered/flows/flow-data-buffering.json"
PROTO_FLOW_FILE="edge/nodered/flows/flow-protocol-normalization.json"
TP_FLOW_FILE="edge/nodered/flows/flow-telemetry-publish.json"
LOCAL_BROKER_ID="pn01a0b0c0d0e0bb"
CLOUD_BROKER_ID="tp01a0b0c0d0e0tb"

PASS=0
FAIL=0

pass() { ((PASS++)); echo "  PASS: $1"; }
fail() { ((FAIL++)); echo "  FAIL: $1"; }

echo "=== Data Buffering Flow Tests (Story 1.5) ==="
echo ""

# --- JSON Structure Tests ---
echo "-- JSON Structure --"

# Test: Valid JSON
if python3 -c "import json; json.load(open('$FLOW_FILE'))" 2>/dev/null; then
    pass "Flow file is valid JSON"
else
    fail "Flow file is NOT valid JSON"
fi

# Test: JSON is an array
if python3 -c "import json; d=json.load(open('$FLOW_FILE')); assert isinstance(d, list)" 2>/dev/null; then
    pass "Flow file is a JSON array"
else
    fail "Flow file is NOT a JSON array"
fi

# Test: Has tab node with correct label
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tabs = [n for n in nodes if n.get('type') == 'tab']
assert len(tabs) == 1, f'Expected 1 tab, found {len(tabs)}'
assert tabs[0]['label'] == 'data-buffering', f'Tab label is {tabs[0][\"label\"]}'
" 2>/dev/null; then
    pass "Single 'data-buffering' tab exists"
else
    fail "Missing or incorrect 'data-buffering' tab"
fi

# Test: Has comment node
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tab_id = [n['id'] for n in nodes if n.get('type') == 'tab'][0]
comments = [n for n in nodes if n.get('type') == 'comment' and n.get('z') == tab_id]
assert len(comments) >= 1, 'No comment node found'
" 2>/dev/null; then
    pass "Comment/description node exists"
else
    fail "Missing comment/description node"
fi

# Test: Has catch node scoped to tab
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tab_id = [n['id'] for n in nodes if n.get('type') == 'tab'][0]
catches = [n for n in nodes if n.get('type') == 'catch' and n.get('z') == tab_id]
assert len(catches) >= 1, 'No catch node found'
assert tab_id in catches[0].get('scope', []), 'Catch not scoped to tab'
" 2>/dev/null; then
    pass "Catch node exists and scoped to data-buffering tab"
else
    fail "Missing or incorrectly scoped catch node"
fi

echo ""
echo "-- MQTT Subscription Tests --"

# Test: Subscribes to cloud-connection-status on Local Mosquitto
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tab_id = [n['id'] for n in nodes if n.get('type') == 'tab'][0]
mqtt_ins = [n for n in nodes if n.get('type') == 'mqtt in' and n.get('z') == tab_id]
status_sub = [n for n in mqtt_ins if n.get('topic') == 'nexus/internal/cloud-connection-status']
assert len(status_sub) >= 1, 'No subscription to nexus/internal/cloud-connection-status'
assert status_sub[0].get('broker') == '$LOCAL_BROKER_ID', f'Wrong broker: {status_sub[0].get(\"broker\")}'
" 2>/dev/null; then
    pass "Subscribes to nexus/internal/cloud-connection-status on Local Mosquitto ($LOCAL_BROKER_ID)"
else
    fail "Missing subscription to nexus/internal/cloud-connection-status on Local Mosquitto"
fi

# Test: Subscribes to normalized telemetry on Local Mosquitto
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tab_id = [n['id'] for n in nodes if n.get('type') == 'tab'][0]
mqtt_ins = [n for n in nodes if n.get('type') == 'mqtt in' and n.get('z') == tab_id]
telemetry_sub = [n for n in mqtt_ins if n.get('topic') == 'nexus/+/+/telemetry']
assert len(telemetry_sub) >= 1, 'No subscription to nexus/+/+/telemetry'
assert telemetry_sub[0].get('broker') == '$LOCAL_BROKER_ID', f'Wrong broker: {telemetry_sub[0].get(\"broker\")}'
" 2>/dev/null; then
    pass "Subscribes to nexus/+/+/telemetry on Local Mosquitto ($LOCAL_BROKER_ID)"
else
    fail "Missing subscription to nexus/+/+/telemetry on Local Mosquitto"
fi

# Test: QoS 1 on both subscriptions
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tab_id = [n['id'] for n in nodes if n.get('type') == 'tab'][0]
mqtt_ins = [n for n in nodes if n.get('type') == 'mqtt in' and n.get('z') == tab_id]
for n in mqtt_ins:
    assert n.get('qos') == '1', f'Node {n.get(\"name\")} has QoS {n.get(\"qos\")}, expected 1'
" 2>/dev/null; then
    pass "All MQTT-in nodes use QoS 1"
else
    fail "MQTT-in nodes not all using QoS 1"
fi

echo ""
echo "-- Buffer Storage & Replay Tests --"

# Test: Has buffer-router function node
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tab_id = [n['id'] for n in nodes if n.get('type') == 'tab'][0]
funcs = [n for n in nodes if n.get('type') == 'function' and n.get('z') == tab_id]
buffer_router = [n for n in funcs if 'buffer-router' in n.get('name', '')]
assert len(buffer_router) >= 1, 'No buffer-router function node'
assert 'cloudConnected' in buffer_router[0].get('func', ''), 'buffer-router does not check cloudConnected'
assert 'bufferQueue' in buffer_router[0].get('func', ''), 'buffer-router does not use bufferQueue'
" 2>/dev/null; then
    pass "buffer-router function exists and checks cloudConnected/bufferQueue"
else
    fail "Missing or incomplete buffer-router function"
fi

# Test: Has replay-forwarder function node
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tab_id = [n['id'] for n in nodes if n.get('type') == 'tab'][0]
funcs = [n for n in nodes if n.get('type') == 'function' and n.get('z') == tab_id]
replay = [n for n in funcs if 'replay' in n.get('name', '').lower()]
assert len(replay) >= 1, 'No replay-forwarder function node'
assert 'bufferQueue' in replay[0].get('func', ''), 'replay-forwarder does not use bufferQueue'
assert 'v1/devices/me/telemetry' in replay[0].get('func', ''), 'replay-forwarder does not publish to ThingsBoard topic'
" 2>/dev/null; then
    pass "replay-forwarder function exists and publishes to v1/devices/me/telemetry"
else
    fail "Missing or incomplete replay-forwarder function"
fi

# Test: Replay publishes to ThingsBoard Cloud broker
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tab_id = [n['id'] for n in nodes if n.get('type') == 'tab'][0]
mqtt_outs = [n for n in nodes if n.get('type') == 'mqtt out' and n.get('z') == tab_id]
cloud_outs = [n for n in mqtt_outs if n.get('broker') == '$CLOUD_BROKER_ID']
assert len(cloud_outs) >= 1, 'No MQTT-out node using ThingsBoard Cloud broker ($CLOUD_BROKER_ID)'
" 2>/dev/null; then
    pass "MQTT-out node publishes to ThingsBoard Cloud broker ($CLOUD_BROKER_ID)"
else
    fail "No MQTT-out node using ThingsBoard Cloud broker for replay"
fi

# Test: Has delay node for replay timing
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tab_id = [n['id'] for n in nodes if n.get('type') == 'tab'][0]
delays = [n for n in nodes if n.get('type') == 'delay' and n.get('z') == tab_id]
assert len(delays) >= 1, 'No delay node found'
assert delays[0].get('timeout') == '2', f'Delay is {delays[0].get(\"timeout\")}s, expected 2s'
" 2>/dev/null; then
    pass "Delay node exists with 2-second timeout"
else
    fail "Missing or incorrect delay node for replay timing"
fi

echo ""
echo "-- Connection State & Debounce Tests --"

# Test: connection-state-manager has debounce logic
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tab_id = [n['id'] for n in nodes if n.get('type') == 'tab'][0]
funcs = [n for n in nodes if n.get('type') == 'function' and n.get('z') == tab_id]
csm = [n for n in funcs if 'connection-state' in n.get('name', '')]
assert len(csm) >= 1, 'No connection-state-manager function'
func_code = csm[0].get('func', '')
assert 'debounce' in func_code.lower() or 'setTimeout' in func_code, 'No debounce logic in connection-state-manager'
assert '3000' in func_code, 'Debounce timeout should be 3000ms'
" 2>/dev/null; then
    pass "connection-state-manager has debounce logic (3000ms)"
else
    fail "Missing or incorrect debounce in connection-state-manager"
fi

# Test: connection-state-manager has initialize for startup handling
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tab_id = [n['id'] for n in nodes if n.get('type') == 'tab'][0]
funcs = [n for n in nodes if n.get('type') == 'function' and n.get('z') == tab_id]
csm = [n for n in funcs if 'connection-state' in n.get('name', '')]
assert len(csm) >= 1, 'No connection-state-manager function'
init_code = csm[0].get('initialize', '')
assert 'cloudConnected' in init_code, 'Initialize does not set cloudConnected'
assert 'bufferQueue' in init_code, 'Initialize does not set bufferQueue'
" 2>/dev/null; then
    pass "connection-state-manager initializes state on startup"
else
    fail "Missing startup initialization in connection-state-manager"
fi

# Test: connection-state-manager publishes to buffer-status and telemetry-publish-control
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tab_id = [n['id'] for n in nodes if n.get('type') == 'tab'][0]
funcs = [n for n in nodes if n.get('type') == 'function' and n.get('z') == tab_id]
csm = [n for n in funcs if 'connection-state' in n.get('name', '')]
func_code = csm[0].get('func', '')
assert 'nexus/internal/buffer-status' in func_code, 'Does not publish to buffer-status'
assert 'nexus/internal/telemetry-publish-control' in func_code, 'Does not publish to telemetry-publish-control'
" 2>/dev/null; then
    pass "connection-state-manager publishes to buffer-status and telemetry-publish-control"
else
    fail "Missing buffer-status or telemetry-publish-control in connection-state-manager"
fi

echo ""
echo "-- Error Handling Tests --"

# Test: error-log function uses [data-buffering] prefix
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tab_id = [n['id'] for n in nodes if n.get('type') == 'tab'][0]
funcs = [n for n in nodes if n.get('type') == 'function' and n.get('z') == tab_id and 'error' in n.get('name', '').lower()]
assert len(funcs) >= 1, 'No error-log function node'
assert '[data-buffering]' in funcs[0].get('func', ''), 'error-log does not use [data-buffering] prefix'
" 2>/dev/null; then
    pass "error-log function uses [data-buffering] prefix"
else
    fail "Missing [data-buffering] prefix in error-log function"
fi

# Test: error-log publishes to nexus/internal/data-buffering-errors
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tab_id = [n['id'] for n in nodes if n.get('type') == 'tab'][0]
funcs = [n for n in nodes if n.get('type') == 'function' and n.get('z') == tab_id and 'error' in n.get('name', '').lower()]
assert 'nexus/internal/data-buffering-errors' in funcs[0].get('func', ''), 'Does not publish to data-buffering-errors'
" 2>/dev/null; then
    pass "error-log publishes to nexus/internal/data-buffering-errors"
else
    fail "Missing nexus/internal/data-buffering-errors topic in error-log"
fi

# Test: Debug node exists for error sidebar output
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tab_id = [n['id'] for n in nodes if n.get('type') == 'tab'][0]
debugs = [n for n in nodes if n.get('type') == 'debug' and n.get('z') == tab_id]
assert len(debugs) >= 1, 'No debug node found'
assert debugs[0].get('tosidebar') == True, 'Debug not outputting to sidebar'
" 2>/dev/null; then
    pass "Debug node exists for error sidebar output"
else
    fail "Missing debug node for error output"
fi

echo ""
echo "-- No Duplicate Broker Config Tests --"

# Test: Flow does NOT create a new mqtt-broker node (reuses from Stories 1.3, 1.4)
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
brokers = [n for n in nodes if n.get('type') == 'mqtt-broker']
assert len(brokers) == 0, f'Found {len(brokers)} mqtt-broker node(s) — should reuse existing, not create new'
" 2>/dev/null; then
    pass "No duplicate mqtt-broker config nodes created (reuses from Stories 1.3, 1.4)"
else
    fail "Flow creates mqtt-broker config node(s) — should reuse existing"
fi

# Test: Flow does NOT create a new tls-config node
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tls = [n for n in nodes if n.get('type') == 'tls-config']
assert len(tls) == 0, f'Found {len(tls)} tls-config node(s) — should reuse existing'
" 2>/dev/null; then
    pass "No duplicate tls-config nodes created"
else
    fail "Flow creates tls-config node(s) — should reuse existing"
fi

# Test: All Local Mosquitto MQTT nodes reference correct broker ID
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tab_id = [n['id'] for n in nodes if n.get('type') == 'tab'][0]
mqtt_nodes = [n for n in nodes if n.get('type') in ('mqtt in', 'mqtt out') and n.get('z') == tab_id]
local_nodes = [n for n in mqtt_nodes if n.get('broker') == '$LOCAL_BROKER_ID']
cloud_nodes = [n for n in mqtt_nodes if n.get('broker') == '$CLOUD_BROKER_ID']
other_nodes = [n for n in mqtt_nodes if n.get('broker') not in ('$LOCAL_BROKER_ID', '$CLOUD_BROKER_ID')]
assert len(other_nodes) == 0, f'Found {len(other_nodes)} MQTT node(s) with unknown broker: {[n.get(\"name\") for n in other_nodes]}'
assert len(local_nodes) >= 4, f'Expected at least 4 local MQTT nodes, found {len(local_nodes)}'
assert len(cloud_nodes) >= 1, f'Expected at least 1 cloud MQTT node, found {len(cloud_nodes)}'
" 2>/dev/null; then
    pass "All MQTT nodes reference correct broker IDs (local: $LOCAL_BROKER_ID, cloud: $CLOUD_BROKER_ID)"
else
    fail "MQTT node(s) reference incorrect broker IDs"
fi

echo ""
echo "-- Wiring Tests --"

# Test: MQTT-in (cloud-status) wired to connection-state-manager
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tab_id = [n['id'] for n in nodes if n.get('type') == 'tab'][0]
mqtt_in = [n for n in nodes if n.get('type') == 'mqtt in' and n.get('z') == tab_id and 'cloud' in n.get('name', '').lower()][0]
target_id = mqtt_in['wires'][0][0]
target = [n for n in nodes if n['id'] == target_id][0]
assert 'connection-state' in target.get('name', '').lower(), f'Cloud status MQTT-in wired to {target.get(\"name\")}, expected connection-state-manager'
" 2>/dev/null; then
    pass "Cloud connection status MQTT-in wired to connection-state-manager"
else
    fail "Cloud connection status MQTT-in NOT wired to connection-state-manager"
fi

# Test: MQTT-in (telemetry) wired to buffer-router
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tab_id = [n['id'] for n in nodes if n.get('type') == 'tab'][0]
mqtt_in = [n for n in nodes if n.get('type') == 'mqtt in' and n.get('z') == tab_id and 'telemetry' in n.get('name', '').lower()][0]
target_id = mqtt_in['wires'][0][0]
target = [n for n in nodes if n['id'] == target_id][0]
assert 'buffer-router' in target.get('name', '').lower(), f'Telemetry MQTT-in wired to {target.get(\"name\")}, expected buffer-router'
" 2>/dev/null; then
    pass "Telemetry MQTT-in wired to buffer-router"
else
    fail "Telemetry MQTT-in NOT wired to buffer-router"
fi

# Test: connection-state-manager output 2 wired to delay node
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tab_id = [n['id'] for n in nodes if n.get('type') == 'tab'][0]
csm = [n for n in nodes if n.get('type') == 'function' and 'connection-state' in n.get('name', '')][0]
# Output 2 (index 1) should wire to delay node
out2_target_id = csm['wires'][1][0]
out2_target = [n for n in nodes if n['id'] == out2_target_id][0]
assert out2_target.get('type') == 'delay', f'connection-state-manager output 2 wired to {out2_target.get(\"type\")}, expected delay'
" 2>/dev/null; then
    pass "connection-state-manager output 2 wired to delay node"
else
    fail "connection-state-manager output 2 NOT wired to delay node"
fi

# Test: delay node wired to replay-forwarder
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
delay_node = [n for n in nodes if n.get('type') == 'delay'][0]
target_id = delay_node['wires'][0][0]
target = [n for n in nodes if n['id'] == target_id][0]
assert 'replay' in target.get('name', '').lower(), f'Delay wired to {target.get(\"name\")}, expected replay-forwarder'
" 2>/dev/null; then
    pass "Delay node wired to replay-forwarder"
else
    fail "Delay node NOT wired to replay-forwarder"
fi

# Test: replay-forwarder output 1 wired to ThingsBoard MQTT-out
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
replay = [n for n in nodes if n.get('type') == 'function' and 'replay' in n.get('name', '').lower()][0]
out1_target_id = replay['wires'][0][0]
out1_target = [n for n in nodes if n['id'] == out1_target_id][0]
assert out1_target.get('type') == 'mqtt out', f'replay output 1 wired to {out1_target.get(\"type\")}, expected mqtt out'
assert out1_target.get('broker') == '$CLOUD_BROKER_ID', f'replay output 1 broker is {out1_target.get(\"broker\")}, expected $CLOUD_BROKER_ID'
" 2>/dev/null; then
    pass "replay-forwarder output 1 wired to ThingsBoard MQTT-out"
else
    fail "replay-forwarder output 1 NOT wired to ThingsBoard MQTT-out"
fi

# Test: catch node wired to error-log function
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tab_id = [n['id'] for n in nodes if n.get('type') == 'tab'][0]
catch_node = [n for n in nodes if n.get('type') == 'catch' and n.get('z') == tab_id][0]
target_id = catch_node['wires'][0][0]
target = [n for n in nodes if n['id'] == target_id][0]
assert 'error' in target.get('name', '').lower(), f'Catch wired to {target.get(\"name\")}, expected error-log'
" 2>/dev/null; then
    pass "Catch node wired to error-log function"
else
    fail "Catch node NOT wired to error-log function"
fi

echo ""
echo "-- Replay Abort Safety Test --"

# Test: replay-forwarder checks cloudConnected before replaying
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
replay = [n for n in nodes if n.get('type') == 'function' and 'replay' in n.get('name', '').lower()][0]
func_code = replay.get('func', '')
assert 'cloudConnected' in func_code, 'replay-forwarder does not check cloudConnected'
assert 'aborting' in func_code.lower() or 'abort' in func_code.lower(), 'replay-forwarder has no abort logic'
" 2>/dev/null; then
    pass "replay-forwarder checks cloudConnected and can abort replay"
else
    fail "replay-forwarder missing cloudConnected check or abort logic"
fi

echo ""
echo "-- Node Integrity Tests --"

# Test: All node IDs are unique
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
ids = [n['id'] for n in nodes if 'id' in n]
assert len(ids) == len(set(ids)), f'Duplicate IDs found: {[x for x in ids if ids.count(x) > 1]}'
" 2>/dev/null; then
    pass "All node IDs are unique"
else
    fail "Duplicate node IDs found"
fi

# Test: All scoped nodes reference correct tab ID
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tab_id = [n['id'] for n in nodes if n.get('type') == 'tab'][0]
scoped = [n for n in nodes if n.get('z') and n.get('z') != tab_id]
assert len(scoped) == 0, f'{len(scoped)} node(s) reference wrong tab: {[n.get(\"name\") for n in scoped]}'
" 2>/dev/null; then
    pass "All scoped nodes reference correct tab ID"
else
    fail "Node(s) reference incorrect tab ID"
fi

# Test: buffer-router enforces max buffer size
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tab_id = [n['id'] for n in nodes if n.get('type') == 'tab'][0]
funcs = [n for n in nodes if n.get('type') == 'function' and n.get('z') == tab_id]
buffer_router = [n for n in funcs if 'buffer-router' in n.get('name', '')]
func_code = buffer_router[0].get('func', '')
assert 'MAX_BUFFER_SIZE' in func_code, 'buffer-router has no max buffer size limit'
assert 'shift()' in func_code, 'buffer-router does not drop oldest when full'
" 2>/dev/null; then
    pass "buffer-router enforces max buffer size with oldest-drop strategy"
else
    fail "buffer-router missing max buffer size enforcement"
fi

# Test: All buffer-status MQTT-out nodes use consistent retain flag
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tab_id = [n['id'] for n in nodes if n.get('type') == 'tab'][0]
mqtt_outs = [n for n in nodes if n.get('type') == 'mqtt out' and n.get('z') == tab_id]
# Exclude error publisher — only check status/control publishers
status_outs = [n for n in mqtt_outs if n.get('broker') == '$LOCAL_BROKER_ID' and 'error' not in n.get('name', '').lower()]
retain_values = set(n.get('retain') for n in status_outs)
assert len(retain_values) == 1, f'Inconsistent retain flags on local MQTT-out nodes: {[(n.get(\"name\"), n.get(\"retain\")) for n in status_outs]}'
" 2>/dev/null; then
    pass "All buffer-status MQTT-out nodes use consistent retain flag"
else
    fail "Inconsistent retain flags on buffer-status MQTT-out nodes"
fi

echo ""
echo "-- Story 1.3 & 1.4 Regression --"

# Test: Story 1.3 flow still valid
if python3 -c "import json; json.load(open('$PROTO_FLOW_FILE'))" 2>/dev/null; then
    pass "Story 1.3 flow-protocol-normalization.json still valid JSON"
else
    fail "Story 1.3 flow-protocol-normalization.json is invalid"
fi

# Test: Story 1.4 flow still valid
if python3 -c "import json; json.load(open('$TP_FLOW_FILE'))" 2>/dev/null; then
    pass "Story 1.4 flow-telemetry-publish.json still valid JSON"
else
    fail "Story 1.4 flow-telemetry-publish.json is invalid"
fi

echo ""
echo "=== Results ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
echo "TOTAL: $((PASS + FAIL))"

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "SOME TESTS FAILED"
    exit 1
else
    echo ""
    echo "ALL TESTS PASSED"
    exit 0
fi
