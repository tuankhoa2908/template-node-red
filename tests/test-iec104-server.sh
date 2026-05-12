#!/usr/bin/env bash
# Test: IEC 60870-5-104 SCADA Server Flow (Story 2.1)
# Validates flow JSON structure, required nodes, and MQTT topic patterns
set -euo pipefail

PASS=0
FAIL=0
FLOW_FILE="$(dirname "$0")/../nodered/flows/flow-iec104-server.json"
HEALTH_FLOW="$(dirname "$0")/../nodered/flows/flow-gateway-health.json"
PACKAGE_FILE="$(dirname "$0")/../nodered/package.json"
DOCKERFILE="$(dirname "$0")/../nodered/Dockerfile"
COMPOSE_FILE="$(dirname "$0")/../docker-compose.yml"

pass() { PASS=$((PASS + 1)); echo "  ✅ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ❌ $1"; }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }

echo "=== IEC104 Server Flow Tests (Story 2.1) ==="
echo ""

# --- Flow JSON structure validation ---
echo "📄 Flow file structure:"
check "flow file exists" "[ -f '$FLOW_FILE' ]"
check "flow JSON is valid" "python3 -m json.tool '$FLOW_FILE' > /dev/null 2>&1"

# --- Required node types ---
echo ""
echo "🔧 Required nodes:"
check "tab node (iec104-server)" "python3 -c \"
import json
nodes = json.load(open('$FLOW_FILE'))
tabs = [n for n in nodes if n.get('type') == 'tab' and n.get('label') == 'iec104-server']
assert len(tabs) == 1
\""

check "daemon node (json-iec104-server)" "python3 -c \"
import json
nodes = json.load(open('$FLOW_FILE'))
daemons = [n for n in nodes if n.get('type') == 'daemon']
assert len(daemons) >= 1
assert daemons[0].get('command') == '/usr/local/bin/json-iec104-server'
\""

check "daemon has 3 outputs (stdout, stderr, rc)" "python3 -c \"
import json
nodes = json.load(open('$FLOW_FILE'))
daemon = [n for n in nodes if n.get('type') == 'daemon'][0]
assert len(daemon.get('wires', [])) == 3
\""

check "daemon autorun enabled" "python3 -c \"
import json
nodes = json.load(open('$FLOW_FILE'))
daemon = [n for n in nodes if n.get('type') == 'daemon'][0]
assert daemon.get('autorun') == True
assert daemon.get('cr') == True
assert daemon.get('redo') == True
assert daemon.get('op') == 'string'
assert daemon.get('closer') == 'SIGINT'
\""

check "start inject node" "python3 -c \"
import json
nodes = json.load(open('$FLOW_FILE'))
starts = [n for n in nodes if n.get('type') == 'inject' and 'Start' in n.get('name', '')]
assert len(starts) >= 1
\""

check "stop inject node" "python3 -c \"
import json
nodes = json.load(open('$FLOW_FILE'))
stops = [n for n in nodes if n.get('type') == 'inject' and 'Stop' in n.get('name', '')]
assert len(stops) >= 1
\""

check "link in node (IEC-Server-In)" "python3 -c \"
import json
nodes = json.load(open('$FLOW_FILE'))
links = [n for n in nodes if n.get('type') == 'link in' and 'IEC-Server-In' in n.get('name', '')]
assert len(links) >= 1
\""

check "link out node (IEC-Server-Out)" "python3 -c \"
import json
nodes = json.load(open('$FLOW_FILE'))
links = [n for n in nodes if n.get('type') == 'link out' and 'IEC-Server-Out' in n.get('name', '')]
assert len(links) >= 1
\""

check "check-and-split-data function node" "python3 -c \"
import json
nodes = json.load(open('$FLOW_FILE'))
funcs = [n for n in nodes if n.get('name') == 'check-and-split-data']
assert len(funcs) >= 1
assert 'split' in funcs[0].get('func', '').lower()
\""

check "json parse node" "python3 -c \"
import json
nodes = json.load(open('$FLOW_FILE'))
jsons = [n for n in nodes if n.get('type') == 'json']
assert len(jsons) >= 1
\""

check "process-iec104-message function node" "python3 -c \"
import json
nodes = json.load(open('$FLOW_FILE'))
funcs = [n for n in nodes if n.get('name') == 'process-iec104-message']
assert len(funcs) >= 1
assert funcs[0].get('outputs') >= 3  # Story 2.4 adds output 4 (audit)
\""

check "catch node for error handling" "python3 -c \"
import json
nodes = json.load(open('$FLOW_FILE'))
catches = [n for n in nodes if n.get('type') == 'catch']
assert len(catches) >= 1
\""

# --- MQTT topic validation ---
echo ""
echo "📡 MQTT topics:"
check "iec104-status MQTT out (retained)" "python3 -c \"
import json
nodes = json.load(open('$FLOW_FILE'))
func = [n for n in nodes if n.get('name') == 'process-iec104-message'][0]
assert 'nexus/internal/iec104-status' in func.get('func', '')
mqttOuts = [n for n in nodes if n.get('type') == 'mqtt out' and 'Status' in n.get('name', '')]
assert len(mqttOuts) >= 1
assert mqttOuts[0].get('retain') == 'true'
\""

check "iec104-command MQTT out" "python3 -c \"
import json
nodes = json.load(open('$FLOW_FILE'))
func = [n for n in nodes if n.get('name') == 'process-iec104-message'][0]
assert 'nexus/internal/iec104-command' in func.get('func', '')
mqttOuts = [n for n in nodes if n.get('type') == 'mqtt out' and 'Command' in n.get('name', '')]
assert len(mqttOuts) >= 1
\""

check "telemetry MQTT in (nexus/+/+/telemetry)" "python3 -c \"
import json
nodes = json.load(open('$FLOW_FILE'))
mqttIns = [n for n in nodes if n.get('type') == 'mqtt in' and n.get('topic') == 'nexus/+/+/telemetry']
assert len(mqttIns) >= 1
\""

check "iec104-errors MQTT out" "python3 -c \"
import json
nodes = json.load(open('$FLOW_FILE'))
func = [n for n in nodes if n.get('name') == 'error-log'][0]
assert 'nexus/internal/iec104-errors' in func.get('func', '')
\""

check "all MQTT nodes use local broker (pn01a0b0c0d0e0bb)" "python3 -c \"
import json
nodes = json.load(open('$FLOW_FILE'))
mqtt_nodes = [n for n in nodes if n.get('type') in ('mqtt in', 'mqtt out')]
for n in mqtt_nodes:
    assert n.get('broker') == 'pn01a0b0c0d0e0bb', f'{n.get(\"name\")} uses wrong broker'
\""

# --- Node ID pattern validation ---
echo ""
echo "🔢 Node ID conventions:"
check "all node IDs follow ie01a0b0c0d0e pattern" "python3 -c \"
import json
nodes = json.load(open('$FLOW_FILE'))
for n in nodes:
    nid = n.get('id', '')
    assert nid.startswith('ie01a0b0c0d0e'), f'Bad ID: {nid}'
\""

# --- IOA mapping validation ---
echo ""
echo "📊 IOA mapping:"
check "IOA mapping includes power_draw_kw, export_limit_kw, inverter_status" "python3 -c \"
import json
nodes = json.load(open('$FLOW_FILE'))
func = [n for n in nodes if n.get('name') == 'process-iec104-message'][0]
code = func.get('func', '')
assert 'power_draw_kw' in code
assert 'export_limit_kw' in code
assert 'inverter_status' in code
\""

# --- Command message format validation ---
echo ""
echo "📨 Command message format:"
check "command message has required fields (device_id, zone_id, action, value, unit, source, timestamp)" "python3 -c \"
import json
nodes = json.load(open('$FLOW_FILE'))
func = [n for n in nodes if n.get('name') == 'process-iec104-message'][0]
code = func.get('func', '')
for field in ['device_id', 'zone_id', 'action', 'value', 'unit', 'source', 'timestamp']:
    assert field in code, f'Missing field: {field}'
\""

# --- Infrastructure validation ---
echo ""
echo "🏗️ Infrastructure:"
check "package.json includes node-red-contrib-daemon" "python3 -c \"
import json
pkg = json.load(open('$PACKAGE_FILE'))
assert 'node-red-contrib-daemon' in pkg.get('dependencies', {})
\""

check "Dockerfile exists" "[ -f '$DOCKERFILE' ]"
check "Dockerfile copies binary" "grep -q 'json-iec104-server' '$DOCKERFILE'"
check "Dockerfile sets executable permissions" "grep -q 'chmod +x' '$DOCKERFILE'"

check "docker-compose exposes IEC104 port" "grep -q '2404' '$COMPOSE_FILE'"
check "docker-compose has IEC104_PORT env var" "grep -q 'IEC104_PORT' '$COMPOSE_FILE'"
check "docker-compose has IEC104_COMMON_ADDRESS env var" "grep -q 'IEC104_COMMON_ADDRESS' '$COMPOSE_FILE'"

# --- Gateway health integration ---
echo ""
echo "🏥 Gateway health integration:"
check "gateway-health subscribes to iec104-status" "python3 -c \"
import json
nodes = json.load(open('$HEALTH_FLOW'))
iec_subs = [n for n in nodes if n.get('type') == 'mqtt in' and 'iec104-status' in n.get('topic', '')]
assert len(iec_subs) >= 1
\""

check "gateway-health includes iec104_connected in payload" "python3 -c \"
import json
nodes = json.load(open('$HEALTH_FLOW'))
agg = [n for n in nodes if n.get('name') == 'health-aggregator'][0]
assert 'iec104_connected' in agg.get('func', '')
\""

# --- Debug nodes validation ---
echo ""
echo "🐛 Debug nodes:"
check "debug nodes for daemon stderr and return code" "python3 -c \"
import json
nodes = json.load(open('$FLOW_FILE'))
debugs = [n for n in nodes if n.get('type') == 'debug']
names = [n.get('name', '') for n in debugs]
assert any('stderr' in n.lower() for n in names)
assert any('return code' in n.lower() for n in names)
\""

check "debug node for parsed IEC104 output" "python3 -c \"
import json
nodes = json.load(open('$FLOW_FILE'))
debugs = [n for n in nodes if n.get('type') == 'debug' and 'Parsed' in n.get('name', '')]
assert len(debugs) >= 1
\""

# --- Summary ---
echo ""
echo "=== Results ==="
TOTAL=$((PASS + FAIL))
echo "Total: $TOTAL | Passed: $PASS | Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    echo "❌ SOME TESTS FAILED"
    exit 1
else
    echo "✅ ALL TESTS PASSED"
    exit 0
fi
