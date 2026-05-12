#!/usr/bin/env bash
# Test suite for flow-telemetry-publish.json (Story 1.4)
# Validates Node-RED flow JSON structure, required nodes, TLS config, and wiring.
# Usage: bash edge/tests/test-telemetry-publish.sh

set -euo pipefail

FLOW_FILE="edge/nodered/flows/flow-telemetry-publish.json"
ENV_FILE="edge/.env.example"
COMPOSE_FILE="edge/docker-compose.yml"

PASS=0
FAIL=0

pass() { ((PASS++)); echo "  PASS: $1"; }
fail() { ((FAIL++)); echo "  FAIL: $1"; }

echo "=== Telemetry Publish Flow Tests ==="
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
assert tabs[0]['label'] == 'telemetry-publish', f'Tab label is {tabs[0][\"label\"]}'
" 2>/dev/null; then
    pass "Single 'telemetry-publish' tab exists"
else
    fail "Missing or incorrect 'telemetry-publish' tab"
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
    pass "Catch node exists and scoped to telemetry-publish tab"
else
    fail "Missing or incorrectly scoped catch node"
fi

echo ""
echo "-- MQTT & TLS Configuration --"

# Test: Has ThingsBoard cloud mqtt-broker config node
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
brokers = [n for n in nodes if n.get('type') == 'mqtt-broker' and 'ThingsBoard' in n.get('name', '')]
assert len(brokers) >= 1, 'No ThingsBoard broker config'
b = brokers[0]
assert b.get('usetls') == True, 'TLS not enabled'
assert '\${TB_CLOUD_HOST}' in b.get('broker', ''), 'broker not using env var'
assert '\${TB_CLOUD_MQTT_PORT}' in str(b.get('port', '')), 'port not using env var'
" 2>/dev/null; then
    pass "ThingsBoard cloud broker config with TLS enabled"
else
    fail "Missing or misconfigured ThingsBoard broker config"
fi

# Test: Has tls-config node
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tls = [n for n in nodes if n.get('type') == 'tls-config']
assert len(tls) >= 1, 'No tls-config node'
assert tls[0].get('verifyservercert') == True, 'Server cert verification not enabled'
" 2>/dev/null; then
    pass "TLS config node with server cert verification"
else
    fail "Missing or misconfigured TLS config node"
fi

# Test: Broker references tls-config node
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tls_id = [n['id'] for n in nodes if n.get('type') == 'tls-config'][0]
brokers = [n for n in nodes if n.get('type') == 'mqtt-broker' and 'ThingsBoard' in n.get('name', '')]
assert brokers[0].get('tls') == tls_id, 'Broker does not reference TLS config'
" 2>/dev/null; then
    pass "Broker config references TLS config node"
else
    fail "Broker config does not reference TLS config node"
fi

# Test: Has LWT configured
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
brokers = [n for n in nodes if n.get('type') == 'mqtt-broker' and 'ThingsBoard' in n.get('name', '')]
b = brokers[0]
assert b.get('willTopic') == 'v1/devices/me/attributes', 'LWT topic wrong'
assert 'cloud_connected' in b.get('willPayload', ''), 'LWT payload missing cloud_connected'
" 2>/dev/null; then
    pass "MQTT LWT configured for disconnect detection"
else
    fail "Missing or incorrect MQTT LWT configuration"
fi

# Test: Has birth message for connection announcement
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
brokers = [n for n in nodes if n.get('type') == 'mqtt-broker' and 'ThingsBoard' in n.get('name', '')]
b = brokers[0]
assert b.get('birthTopic') == 'v1/devices/me/attributes', 'Birth topic wrong'
assert 'cloud_connected' in b.get('birthPayload', ''), 'Birth payload missing'
" 2>/dev/null; then
    pass "MQTT birth message configured for connection announcement"
else
    fail "Missing or incorrect MQTT birth message"
fi

# Test: Has credentials with access token
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
brokers = [n for n in nodes if n.get('type') == 'mqtt-broker' and 'ThingsBoard' in n.get('name', '')]
creds = brokers[0].get('credentials', {})
assert '\${TB_ACCESS_TOKEN}' in creds.get('user', ''), 'Access token not configured'
" 2>/dev/null; then
    pass "Access token credential configured via env var"
else
    fail "Missing access token credential configuration"
fi

echo ""
echo "-- Flow Node Tests --"

# Test: Has mqtt-in node subscribing to local normalized topic
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tab_id = [n['id'] for n in nodes if n.get('type') == 'tab'][0]
mqtt_ins = [n for n in nodes if n.get('type') == 'mqtt in' and n.get('z') == tab_id]
assert len(mqtt_ins) >= 1, 'No mqtt-in node'
assert 'nexus/+/+/telemetry' in mqtt_ins[0].get('topic', ''), 'Wrong subscription topic'
" 2>/dev/null; then
    pass "MQTT-in subscribes to nexus/+/+/telemetry"
else
    fail "Missing or incorrect MQTT-in subscription"
fi

# Test: MQTT-in uses local Mosquitto broker (from protocol-normalization)
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tab_id = [n['id'] for n in nodes if n.get('type') == 'tab'][0]
mqtt_ins = [n for n in nodes if n.get('type') == 'mqtt in' and n.get('z') == tab_id]
assert mqtt_ins[0].get('broker') == 'pn01a0b0c0d0e0bb', 'Not using shared Local Mosquitto broker'
" 2>/dev/null; then
    pass "MQTT-in reuses Local Mosquitto broker config from Story 1.3"
else
    fail "MQTT-in does not reuse Local Mosquitto broker (pn01a0b0c0d0e0bb)"
fi

# Test: Has validate-payload function node
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tab_id = [n['id'] for n in nodes if n.get('type') == 'tab'][0]
funcs = [n for n in nodes if n.get('type') == 'function' and n.get('z') == tab_id and 'validate' in n.get('name', '')]
assert len(funcs) >= 1, 'No validate-payload function'
assert 'v1/devices/me/telemetry' in funcs[0].get('func', ''), 'Function does not set ThingsBoard topic'
" 2>/dev/null; then
    pass "Validate-payload function node exists"
else
    fail "Missing validate-payload function node"
fi

# Test: Has mqtt-out node for ThingsBoard cloud
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tab_id = [n['id'] for n in nodes if n.get('type') == 'tab'][0]
tb_broker_id = [n['id'] for n in nodes if n.get('type') == 'mqtt-broker' and 'ThingsBoard' in n.get('name', '')][0]
mqtt_outs = [n for n in nodes if n.get('type') == 'mqtt out' and n.get('z') == tab_id and n.get('broker') == tb_broker_id]
assert len(mqtt_outs) >= 1, 'No mqtt-out for ThingsBoard'
" 2>/dev/null; then
    pass "MQTT-out node publishes to ThingsBoard cloud broker"
else
    fail "Missing MQTT-out node for ThingsBoard"
fi

# Test: Has status node for connection monitoring
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tab_id = [n['id'] for n in nodes if n.get('type') == 'tab'][0]
status_nodes = [n for n in nodes if n.get('type') == 'status' and n.get('z') == tab_id]
assert len(status_nodes) >= 1, 'No status node'
" 2>/dev/null; then
    pass "Status node monitors cloud connection"
else
    fail "Missing status node for connection monitoring"
fi

# Test: Has error-log function with correct format
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tab_id = [n['id'] for n in nodes if n.get('type') == 'tab'][0]
error_logs = [n for n in nodes if n.get('type') == 'function' and n.get('z') == tab_id and 'error' in n.get('name', '').lower()]
assert len(error_logs) >= 1, 'No error-log function'
assert '[telemetry-publish]' in error_logs[0].get('func', ''), 'Error format missing flow name prefix'
" 2>/dev/null; then
    pass "Error-log function with [telemetry-publish] format"
else
    fail "Missing or incorrect error-log function"
fi

# Test: Has debug node for error output
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tab_id = [n['id'] for n in nodes if n.get('type') == 'tab'][0]
debugs = [n for n in nodes if n.get('type') == 'debug' and n.get('z') == tab_id]
assert len(debugs) >= 1, 'No debug node'
" 2>/dev/null; then
    pass "Debug node for error sidebar output"
else
    fail "Missing debug node"
fi

# Test: All node IDs are unique
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
ids = [n['id'] for n in nodes if 'id' in n]
assert len(ids) == len(set(ids)), f'Duplicate IDs found: {len(ids)} total, {len(set(ids))} unique'
" 2>/dev/null; then
    pass "All node IDs are unique"
else
    fail "Duplicate node IDs found"
fi

# Test: All tab-scoped nodes reference correct tab
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tab_id = [n['id'] for n in nodes if n.get('type') == 'tab'][0]
config_types = {'mqtt-broker', 'tls-config', 'tab', 'subflow'}
scoped = [n for n in nodes if 'z' in n and n.get('type') not in config_types]
for n in scoped:
    assert n['z'] == tab_id, f'Node {n[\"id\"]} ({n.get(\"name\",\"\")}) has wrong tab ref: {n[\"z\"]}'
" 2>/dev/null; then
    pass "All scoped nodes reference correct tab ID"
else
    fail "Some nodes reference wrong tab ID"
fi

echo ""
echo "-- Wiring & QoS Tests --"

# Test: MQTT-in wired to validate-payload
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
mqtt_in = [n for n in nodes if n.get('type') == 'mqtt in'][0]
validate = [n for n in nodes if n.get('type') == 'function' and 'validate' in n.get('name', '')][0]
assert validate['id'] in mqtt_in.get('wires', [[]])[0], 'MQTT-in not wired to validate-payload'
" 2>/dev/null; then
    pass "MQTT-in wired to validate-payload function"
else
    fail "MQTT-in NOT wired to validate-payload"
fi

# Test: validate-payload wired to ThingsBoard MQTT-out
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
validate = [n for n in nodes if n.get('type') == 'function' and 'validate' in n.get('name', '')][0]
tb_broker_id = [n['id'] for n in nodes if n.get('type') == 'mqtt-broker' and 'ThingsBoard' in n.get('name', '')][0]
tb_out = [n for n in nodes if n.get('type') == 'mqtt out' and n.get('broker') == tb_broker_id][0]
assert tb_out['id'] in validate.get('wires', [[]])[0], 'validate-payload not wired to ThingsBoard MQTT-out'
" 2>/dev/null; then
    pass "validate-payload wired to ThingsBoard MQTT-out"
else
    fail "validate-payload NOT wired to ThingsBoard MQTT-out"
fi

# Test: Catch node wired to error-log function
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
catch_node = [n for n in nodes if n.get('type') == 'catch'][0]
error_log = [n for n in nodes if n.get('type') == 'function' and 'error' in n.get('name', '').lower()][0]
assert error_log['id'] in catch_node.get('wires', [[]])[0], 'Catch not wired to error-log'
" 2>/dev/null; then
    pass "Catch node wired to error-log function"
else
    fail "Catch node NOT wired to error-log"
fi

# Test: ThingsBoard MQTT-out QoS is 1 (reliable delivery per NFR2)
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
tb_broker_id = [n['id'] for n in nodes if n.get('type') == 'mqtt-broker' and 'ThingsBoard' in n.get('name', '')][0]
tb_out = [n for n in nodes if n.get('type') == 'mqtt out' and n.get('broker') == tb_broker_id][0]
assert tb_out.get('qos') == '1', f'QoS is {tb_out.get(\"qos\")}, expected 1'
" 2>/dev/null; then
    pass "ThingsBoard MQTT-out QoS set to 1 (at-least-once)"
else
    fail "ThingsBoard MQTT-out QoS not set to 1"
fi

echo ""
echo "-- Environment & Config Tests --"

# Test: .env.example has TB_CLOUD_MQTT_PORT=8883
if grep -q "TB_CLOUD_MQTT_PORT=8883" "$ENV_FILE" 2>/dev/null; then
    pass ".env.example has TB_CLOUD_MQTT_PORT=8883 (TLS default)"
else
    fail ".env.example missing TB_CLOUD_MQTT_PORT=8883"
fi

# Test: docker-compose.yml passes TB env vars to nodered
if grep -q "TB_CLOUD_HOST" "$COMPOSE_FILE" 2>/dev/null && \
   grep -q "TB_ACCESS_TOKEN" "$COMPOSE_FILE" 2>/dev/null && \
   grep -q "TB_CLOUD_MQTT_PORT" "$COMPOSE_FILE" 2>/dev/null; then
    pass "docker-compose.yml passes TB_CLOUD_* vars to nodered service"
else
    fail "docker-compose.yml missing ThingsBoard env vars in nodered service"
fi

# Test: docker-compose.yml passes ZONE_ID to nodered
if grep -q "ZONE_ID" "$COMPOSE_FILE" 2>/dev/null; then
    pass "docker-compose.yml passes ZONE_ID to nodered service"
else
    fail "docker-compose.yml missing ZONE_ID in nodered service"
fi

# Test: No duplicate Local Mosquitto broker config in this flow
if python3 -c "
import json
nodes = json.load(open('$FLOW_FILE'))
local_brokers = [n for n in nodes if n.get('type') == 'mqtt-broker' and 'Mosquitto' in n.get('name', '')]
assert len(local_brokers) == 0, f'Found {len(local_brokers)} duplicate Local Mosquitto broker configs'
" 2>/dev/null; then
    pass "No duplicate Local Mosquitto broker config (reuses Story 1.3)"
else
    fail "Duplicate Local Mosquitto broker config found"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
