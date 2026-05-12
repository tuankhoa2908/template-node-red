#!/usr/bin/env bash
# Test: IEC104-to-Modbus Command Bridge (Story 2.4)
# Validates flow JSON structure, node wiring, event_id passthrough, and audit trail
set -euo pipefail

PASS=0
FAIL=0
IEC_FLOW="$(dirname "$0")/../nodered/flows/flow-iec104-server.json"
MW_FLOW="$(dirname "$0")/../nodered/flows/flow-modbus-writeback.json"

pass() { PASS=$((PASS + 1)); echo "  ✅ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ❌ $1"; }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }

echo "=== IEC104-to-Modbus Command Bridge Tests (Story 2.4) ==="
echo ""

# --- Flow JSON structure validation ---
echo "📄 Flow file structure:"
check "IEC104 flow file exists" "[ -f '$IEC_FLOW' ]"
check "IEC104 flow JSON is valid" "python3 -m json.tool '$IEC_FLOW' > /dev/null 2>&1"
check "Writeback flow file exists" "[ -f '$MW_FLOW' ]"
check "Writeback flow JSON is valid" "python3 -m json.tool '$MW_FLOW' > /dev/null 2>&1"

# --- Task 1: Writeback feedback subscription ---
echo ""
echo "🔧 Task 1: Writeback feedback subscription in IEC104 flow:"
check "MQTT In node for writeback-status" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
subs = [n for n in nodes if n.get('type') == 'mqtt in' and n.get('topic') == 'nexus/internal/writeback-status']
assert len(subs) >= 1, 'No writeback-status subscription found'
\""

check "MQTT In node for writeback-errors" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
subs = [n for n in nodes if n.get('type') == 'mqtt in' and n.get('topic') == 'nexus/internal/writeback-errors']
assert len(subs) >= 1, 'No writeback-errors subscription found'
\""

check "build-iec104-ack function node exists" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
funcs = [n for n in nodes if n.get('type') == 'function' and n.get('name') == 'build-iec104-ack']
assert len(funcs) == 1, 'build-iec104-ack not found'
\""

check "build-iec104-nack function node exists" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
funcs = [n for n in nodes if n.get('type') == 'function' and n.get('name') == 'build-iec104-nack']
assert len(funcs) == 1, 'build-iec104-nack not found'
\""

check "build-iec104-ack has 2 outputs (daemon + audit)" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
func = [n for n in nodes if n.get('name') == 'build-iec104-ack'][0]
assert func.get('outputs') == 2, 'Expected 2 outputs, got ' + str(func.get('outputs'))
\""

check "build-iec104-nack has 2 outputs (daemon + audit)" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
func = [n for n in nodes if n.get('name') == 'build-iec104-nack'][0]
assert func.get('outputs') == 2, 'Expected 2 outputs, got ' + str(func.get('outputs'))
\""

# --- Task 1.5: Wiring to daemon ---
echo ""
echo "🔌 Task 1.5: Ack/nack wiring to daemon:"
check "build-iec104-ack output 1 wires to daemon" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
func = [n for n in nodes if n.get('name') == 'build-iec104-ack'][0]
daemon = [n for n in nodes if n.get('type') == 'daemon'][0]
assert daemon['id'] in func['wires'][0], 'ack output 1 not wired to daemon'
\""

check "build-iec104-nack output 1 wires to daemon" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
func = [n for n in nodes if n.get('name') == 'build-iec104-nack'][0]
daemon = [n for n in nodes if n.get('type') == 'daemon'][0]
assert daemon['id'] in func['wires'][0], 'nack output 1 not wired to daemon'
\""

# --- Task 1.6: Debug nodes ---
check "debug node for ack output exists" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
debugs = [n for n in nodes if n.get('type') == 'debug' and 'Ack' in n.get('name', '')]
assert len(debugs) >= 1, 'No ack debug node found'
\""

check "debug node for nack output exists" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
debugs = [n for n in nodes if n.get('type') == 'debug' and 'Nack' in n.get('name', '')]
assert len(debugs) >= 1, 'No nack debug node found'
\""

# --- Task 2: IEC104 acknowledgment message format ---
echo ""
echo "📋 Task 2: IEC104 ack/nack message format:"
check "build-iec104-ack uses C_SE_NC_1 type 50" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
func = [n for n in nodes if n.get('name') == 'build-iec104-ack'][0]
code = func['func']
assert 'type' in code and '50' in code, 'type 50 not found in ack function'
\""

check "build-iec104-ack uses COT=7 (activation confirm)" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
func = [n for n in nodes if n.get('name') == 'build-iec104-ack'][0]
code = func['func']
assert 'cot' in code and str(7) in code, 'COT 7 not found in ack function'
\""

check "build-iec104-nack uses COT=47 (negative confirm)" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
func = [n for n in nodes if n.get('name') == 'build-iec104-nack'][0]
code = func['func']
assert 'cot' in code and '47' in code, 'COT 47 not found in nack function'
\""

check "build-iec104-ack has reverse IOA mapping (actionToIoa)" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
func = [n for n in nodes if n.get('name') == 'build-iec104-ack'][0]
code = func['func']
assert 'actionToIoa' in code, 'actionToIoa mapping not found'
assert 'set_export_limit_kw' in code, 'set_export_limit_kw not in IOA mapping'
\""

check "build-iec104-nack has reverse IOA mapping (actionToIoa)" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
func = [n for n in nodes if n.get('name') == 'build-iec104-nack'][0]
code = func['func']
assert 'actionToIoa' in code, 'actionToIoa mapping not found'
\""

check "ack/nack filter for iec104 source only" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
ack = [n for n in nodes if n.get('name') == 'build-iec104-ack'][0]
nack = [n for n in nodes if n.get('name') == 'build-iec104-nack'][0]
assert 'source' in ack['func'] and 'iec104' in ack['func'], 'ack missing source filter'
assert 'source' in nack['func'] and 'iec104' in nack['func'], 'nack missing source filter'
\""

# --- Task 3: Command audit trail ---
echo ""
echo "📝 Task 3: Command audit trail:"
check "MQTT Out node for command-audit topic exists" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
# Check for mqtt out node named 'Publish Command Audit'
audits = [n for n in nodes if n.get('type') == 'mqtt out' and 'Audit' in n.get('name', '')]
assert len(audits) >= 1, 'No command-audit MQTT out found'
\""

check "audit uses shared MQTT broker" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
audit = [n for n in nodes if n.get('type') == 'mqtt out' and 'Audit' in n.get('name', '')][0]
assert audit.get('broker') == 'pn01a0b0c0d0e0bb', 'Wrong broker: ' + str(audit.get('broker'))
\""

check "build-iec104-ack output 2 wires to audit MQTT" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
func = [n for n in nodes if n.get('name') == 'build-iec104-ack'][0]
audit = [n for n in nodes if n.get('type') == 'mqtt out' and 'Audit' in n.get('name', '')][0]
assert audit['id'] in func['wires'][1], 'ack output 2 not wired to audit MQTT'
\""

check "build-iec104-nack output 2 wires to audit MQTT" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
func = [n for n in nodes if n.get('name') == 'build-iec104-nack'][0]
audit = [n for n in nodes if n.get('type') == 'mqtt out' and 'Audit' in n.get('name', '')][0]
assert audit['id'] in func['wires'][1], 'nack output 2 not wired to audit MQTT'
\""

check "ack audit entry includes lifecycle_stage write_confirmed" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
func = [n for n in nodes if n.get('name') == 'build-iec104-ack'][0]
assert 'write_confirmed' in func['func'], 'lifecycle_stage write_confirmed not found'
\""

check "nack audit entry includes lifecycle_stage write_failed" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
func = [n for n in nodes if n.get('name') == 'build-iec104-nack'][0]
assert 'write_failed' in func['func'], 'lifecycle_stage write_failed not found'
\""

# --- Task 4: Command-receipt audit ---
echo ""
echo "📤 Task 4: Command-receipt audit in process-iec104-message:"
check "process-iec104-message has 4 outputs" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
func = [n for n in nodes if n.get('name') == 'process-iec104-message'][0]
assert func.get('outputs') == 4, 'Expected 4 outputs, got ' + str(func.get('outputs'))
\""

check "process-iec104-message generates event_id" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
func = [n for n in nodes if n.get('name') == 'process-iec104-message'][0]
assert 'event_id' in func['func'], 'event_id not found in process-iec104-message'
assert 'eventId' in func['func'] or 'event_id' in func['func'], 'event_id generation not found'
\""

check "process-iec104-message includes event_id in command payload" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
func = [n for n in nodes if n.get('name') == 'process-iec104-message'][0]
code = func['func']
assert 'event_id: eventId' in code or 'event_id' in code, 'event_id not in command payload'
\""

check "process-iec104-message output 4 includes command_received audit" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
func = [n for n in nodes if n.get('name') == 'process-iec104-message'][0]
assert 'command_received' in func['func'], 'command_received lifecycle_stage not found'
assert 'command-audit' in func['func'], 'command-audit topic not found'
\""

check "process-iec104-message output 4 wires to audit MQTT" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
func = [n for n in nodes if n.get('name') == 'process-iec104-message'][0]
audit = [n for n in nodes if n.get('type') == 'mqtt out' and 'Audit' in n.get('name', '')][0]
assert len(func['wires']) >= 4, 'Less than 4 wire arrays: ' + str(len(func['wires']))
assert audit['id'] in func['wires'][3], 'output 4 not wired to audit MQTT'
\""

# --- Task 5: event_id passthrough in writeback flow ---
echo ""
echo "🔗 Task 5: event_id passthrough in Modbus writeback flow:"
check "normalize-iec104-cmd preserves event_id" "python3 -c \"
import json
nodes = json.load(open('$MW_FLOW'))
func = [n for n in nodes if n.get('name') == 'normalize-iec104-cmd'][0]
assert 'event_id' in func['func'], 'event_id not found in normalize-iec104-cmd'
\""

check "build-confirmation includes event_id" "python3 -c \"
import json
nodes = json.load(open('$MW_FLOW'))
func = [n for n in nodes if n.get('name') == 'build-confirmation'][0]
assert 'event_id' in func['func'], 'event_id not found in build-confirmation'
\""

check "retry-handler includes event_id in error output" "python3 -c \"
import json
nodes = json.load(open('$MW_FLOW'))
func = [n for n in nodes if n.get('name') == 'retry-handler'][0]
assert 'event_id' in func['func'], 'event_id not found in retry-handler'
\""

check "error-log includes event_id in error output" "python3 -c \"
import json
nodes = json.load(open('$MW_FLOW'))
func = [n for n in nodes if n.get('name') == 'error-log'][0]
assert 'event_id' in func['func'], 'event_id not found in error-log'
\""

check "validate-command includes event_id in error outputs" "python3 -c \"
import json
nodes = json.load(open('$MW_FLOW'))
func = [n for n in nodes if n.get('name') == 'validate-command'][0]
assert 'event_id' in func['func'], 'event_id not found in validate-command'
\""

check "retry-handler includes source in error output" "python3 -c \"
import json
nodes = json.load(open('$MW_FLOW'))
func = [n for n in nodes if n.get('name') == 'retry-handler'][0]
assert 'source: cmd.source' in func['func'], 'source field not found in retry-handler error'
\""

# --- End-to-end wiring validation ---
echo ""
echo "🔀 End-to-end wiring:"
check "writeback-status MQTT In → build-iec104-ack wiring" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
mqtt_in = [n for n in nodes if n.get('type') == 'mqtt in' and n.get('topic') == 'nexus/internal/writeback-status'][0]
ack = [n for n in nodes if n.get('name') == 'build-iec104-ack'][0]
assert ack['id'] in mqtt_in['wires'][0], 'writeback-status not wired to build-iec104-ack'
\""

check "writeback-errors MQTT In → build-iec104-nack wiring" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
mqtt_in = [n for n in nodes if n.get('type') == 'mqtt in' and n.get('topic') == 'nexus/internal/writeback-errors'][0]
nack = [n for n in nodes if n.get('name') == 'build-iec104-nack'][0]
assert nack['id'] in mqtt_in['wires'][0], 'writeback-errors not wired to build-iec104-nack'
\""

check "IEC104 command MQTT Out exists (forward path)" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
cmd_out = [n for n in nodes if n.get('type') == 'mqtt out' and 'Command' in n.get('name', '')]
assert len(cmd_out) >= 1, 'No IEC104 command MQTT out found'
\""

check "all new MQTT nodes use shared broker pn01a0b0c0d0e0bb" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
mqtt_nodes = [n for n in nodes if n.get('type') in ('mqtt in', 'mqtt out') and n.get('broker')]
for n in mqtt_nodes:
    assert n['broker'] == 'pn01a0b0c0d0e0bb', 'Node ' + n.get('name', n['id']) + ' uses wrong broker: ' + n['broker']
\""

# --- Regression: existing tests still hold ---
echo ""
echo "🔄 Regression checks:"
check "daemon node still exists and configured" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
daemon = [n for n in nodes if n.get('type') == 'daemon'][0]
assert daemon['command'] == '/usr/local/bin/json-iec104-server'
assert daemon['autorun'] == True
assert daemon['cr'] == True
assert daemon['op'] == 'string'
assert daemon['closer'] == 'SIGINT'
\""

check "daemon still has 3 outputs" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
daemon = [n for n in nodes if n.get('type') == 'daemon'][0]
assert len(daemon['wires']) == 3
\""

check "process-iec104-message IOA mapping preserved" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
func = [n for n in nodes if n.get('name') == 'process-iec104-message'][0]
code = func['func']
assert 'power_draw_kw' in code
assert 'export_limit_kw' in code
assert 'inverter_status' in code
\""

check "link in (IEC-Server-In) preserved" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
link_in = [n for n in nodes if n.get('type') == 'link in' and n.get('name') == 'IEC-Server-In']
assert len(link_in) == 1
\""

check "link out (IEC-Server-Out) preserved" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
link_out = [n for n in nodes if n.get('type') == 'link out' and n.get('name') == 'IEC-Server-Out']
assert len(link_out) == 1
\""

check "catch node for error handling preserved" "python3 -c \"
import json
nodes = json.load(open('$IEC_FLOW'))
catch_nodes = [n for n in nodes if n.get('type') == 'catch']
assert len(catch_nodes) >= 1
\""

check "writeback flow: 2 MQTT In nodes preserved" "python3 -c \"
import json
nodes = json.load(open('$MW_FLOW'))
mqtt_in = [n for n in nodes if n.get('type') == 'mqtt in']
assert len(mqtt_in) == 2
\""

check "writeback flow: modbus-write node preserved" "python3 -c \"
import json
nodes = json.load(open('$MW_FLOW'))
write = [n for n in nodes if n.get('type') == 'modbus-write']
assert len(write) >= 1
\""

check "writeback flow: modbus-read node preserved" "python3 -c \"
import json
nodes = json.load(open('$MW_FLOW'))
read = [n for n in nodes if n.get('type') == 'modbus-read']
assert len(read) >= 1
\""

# --- Summary ---
echo ""
echo "=== Results ==="
TOTAL=$((PASS + FAIL))
echo "Total: $TOTAL | ✅ Passed: $PASS | ❌ Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    echo "❌ SOME TESTS FAILED"
    exit 1
else
    echo "✅ ALL TESTS PASSED"
    exit 0
fi
