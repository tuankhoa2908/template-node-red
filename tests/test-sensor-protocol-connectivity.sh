#!/usr/bin/env bash
# Test script for Story 1.7: Sensor-to-Edge Protocol Connectivity
# Validates OPC-UA, BACnet, Serial/Modbus RTU, LwM2M/SNMP nodes in flow JSON
#
# Usage:
#   ./edge/tests/test-sensor-protocol-connectivity.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EDGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FLOWS_DIR="$EDGE_DIR/nodered/flows"
FLOW_FILE="$FLOWS_DIR/flow-protocol-normalization.json"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== Story 1.7: Sensor-to-Edge Protocol Connectivity Tests ==="
echo ""

# -------------------------------------------------------
# 1. OPC-UA Tests
# -------------------------------------------------------
echo "--- OPC-UA Validation ---"

# Test 6.2: OpcUa-Endpoint config node exists
if python3 -c "
import json, sys
with open('$FLOW_FILE') as f:
    nodes = json.load(f)
eps = [n for n in nodes if n.get('type') == 'OpcUa-Endpoint']
sys.exit(0 if len(eps) >= 1 else 1)
" 2>/dev/null; then
    pass "OpcUa-Endpoint config node exists"
else
    fail "OpcUa-Endpoint config node missing"
fi

# Test 6.2: OpcUa-Client node exists with subscribe action
if python3 -c "
import json, sys
with open('$FLOW_FILE') as f:
    nodes = json.load(f)
clients = [n for n in nodes if n.get('type') == 'OpcUa-Client' and n.get('action') == 'subscribe']
sys.exit(0 if len(clients) >= 1 else 1)
" 2>/dev/null; then
    pass "OpcUa-Client node exists with subscribe action"
else
    fail "OpcUa-Client node missing or wrong action"
fi

# Test: OPC-UA nodes are disabled by default
if python3 -c "
import json, sys
with open('$FLOW_FILE') as f:
    nodes = json.load(f)
clients = [n for n in nodes if n.get('type') == 'OpcUa-Client']
for c in clients:
    if not c.get('d', False):
        sys.exit(1)
sys.exit(0)
" 2>/dev/null; then
    pass "OpcUa-Client node is disabled by default"
else
    fail "OpcUa-Client node should be disabled (d: true)"
fi

# -------------------------------------------------------
# 2. BACnet Tests
# -------------------------------------------------------
echo ""
echo "--- BACnet Validation ---"

# Test 6.3: bacnet-client config node exists
if python3 -c "
import json, sys
with open('$FLOW_FILE') as f:
    nodes = json.load(f)
clients = [n for n in nodes if n.get('type') == 'bacnet-client']
sys.exit(0 if len(clients) >= 1 else 1)
" 2>/dev/null; then
    pass "bacnet-client config node exists"
else
    fail "bacnet-client config node missing"
fi

# Test 6.3: bacnet-read node exists
if python3 -c "
import json, sys
with open('$FLOW_FILE') as f:
    nodes = json.load(f)
readers = [n for n in nodes if n.get('type') == 'bacnet-read']
sys.exit(0 if len(readers) >= 1 else 1)
" 2>/dev/null; then
    pass "bacnet-read node exists"
else
    fail "bacnet-read node missing"
fi

# Test: BACnet nodes are disabled by default
if python3 -c "
import json, sys
with open('$FLOW_FILE') as f:
    nodes = json.load(f)
readers = [n for n in nodes if n.get('type') == 'bacnet-read']
for r in readers:
    if not r.get('d', False):
        sys.exit(1)
sys.exit(0)
" 2>/dev/null; then
    pass "bacnet-read node is disabled by default"
else
    fail "bacnet-read node should be disabled (d: true)"
fi

# -------------------------------------------------------
# 3. Serial/Modbus RTU Tests
# -------------------------------------------------------
echo ""
echo "--- Serial/Modbus RTU Validation ---"

# Test 6.4: serial-port config node exists (disabled)
if python3 -c "
import json, sys
with open('$FLOW_FILE') as f:
    nodes = json.load(f)
serials = [n for n in nodes if n.get('type') == 'serial-port']
sys.exit(0 if len(serials) >= 1 else 1)
" 2>/dev/null; then
    pass "serial-port config node exists"
else
    fail "serial-port config node missing"
fi

# Test 6.4: modbus-read node for RTU exists (with serial transport, disabled)
if python3 -c "
import json, sys
with open('$FLOW_FILE') as f:
    nodes = json.load(f)
# Find modbus-client with serial type
serial_clients = [n for n in nodes if n.get('type') == 'modbus-client' and n.get('clienttype') == 'serial']
sys.exit(0 if len(serial_clients) >= 1 else 1)
" 2>/dev/null; then
    pass "modbus-client config node for RTU (serial) exists"
else
    fail "modbus-client config node for RTU (serial) missing"
fi

# Test: Modbus RTU read node is disabled
if python3 -c "
import json, sys
with open('$FLOW_FILE') as f:
    nodes = json.load(f)
# Find the RTU modbus-client ID
serial_client_ids = [n['id'] for n in nodes if n.get('type') == 'modbus-client' and n.get('clienttype') == 'serial']
if not serial_client_ids:
    sys.exit(1)
# Find modbus-read nodes using the serial client
rtu_reads = [n for n in nodes if n.get('type') == 'modbus-read' and n.get('server') in serial_client_ids]
if not rtu_reads:
    sys.exit(1)
for r in rtu_reads:
    if not r.get('d', False):
        sys.exit(1)
sys.exit(0)
" 2>/dev/null; then
    pass "Modbus RTU read node is disabled by default"
else
    fail "Modbus RTU read node should be disabled (d: true)"
fi

# -------------------------------------------------------
# 4. LwM2M/SNMP Key Mappings Tests
# -------------------------------------------------------
echo ""
echo "--- LwM2M/SNMP Key Mappings Validation ---"

# Test 6.5: generic-normalize contains lwm2m protocol mappings
if python3 -c "
import json, sys
with open('$FLOW_FILE') as f:
    nodes = json.load(f)
funcs = [n for n in nodes if n.get('type') == 'function' and n.get('name') == 'generic-normalize']
if not funcs:
    sys.exit(1)
func_code = funcs[0].get('func', '')
sys.exit(0 if 'lwm2m' in func_code else 1)
" 2>/dev/null; then
    pass "generic-normalize contains lwm2m protocol mappings"
else
    fail "generic-normalize missing lwm2m protocol mappings"
fi

# Test 6.5: generic-normalize contains snmp protocol mappings
if python3 -c "
import json, sys
with open('$FLOW_FILE') as f:
    nodes = json.load(f)
funcs = [n for n in nodes if n.get('type') == 'function' and n.get('name') == 'generic-normalize']
if not funcs:
    sys.exit(1)
func_code = funcs[0].get('func', '')
sys.exit(0 if 'snmp' in func_code else 1)
" 2>/dev/null; then
    pass "generic-normalize contains snmp protocol mappings"
else
    fail "generic-normalize missing snmp protocol mappings"
fi

# -------------------------------------------------------
# 5. Node ID Prefix Tests
# -------------------------------------------------------
echo ""
echo "--- Node ID Prefix Validation ---"

# Test 6.6: All new nodes use pn01 prefix
if python3 -c "
import json, sys
with open('$FLOW_FILE') as f:
    nodes = json.load(f)
tab_id = None
for n in nodes:
    if n.get('type') == 'tab' and n.get('label') == 'protocol-normalization':
        tab_id = n['id']
        break
# Get subflow IDs to exclude internal subflow nodes
sf_ids = [n['id'] for n in nodes if n.get('type') == 'subflow']
# Check all nodes belonging to this flow tab or config nodes
for n in nodes:
    nid = n.get('id', '')
    ntype = n.get('type', '')
    z = n.get('z', '')
    # Skip subflow definition and internal subflow nodes
    if ntype == 'subflow' or z in sf_ids:
        continue
    # Config nodes (no z) and flow nodes (z == tab_id) should have pn01 prefix
    if ntype == 'tab':
        continue
    if z == tab_id or (z == '' and ntype not in ('subflow',)):
        if not nid.startswith('pn01'):
            print(f'Node {nid} ({ntype}) does not have pn01 prefix', file=sys.stderr)
            sys.exit(1)
sys.exit(0)
" 2>/dev/null; then
    pass "All flow/config nodes use pn01 prefix"
else
    fail "Some nodes missing pn01 prefix"
fi

# -------------------------------------------------------
# 6. Wiring Tests
# -------------------------------------------------------
echo ""
echo "--- Wiring Validation ---"

# Test 6.7: All protocol normalize functions wire to normalize-output subflow
if python3 -c "
import json, sys
with open('$FLOW_FILE') as f:
    nodes = json.load(f)
# Find normalize-output subflow instance
subflow_inst = [n for n in nodes if 'subflow:' in n.get('type', '') and n.get('name') == 'normalize-output']
if not subflow_inst:
    sys.exit(1)
sf_id = subflow_inst[0]['id']
# Get subflow definition IDs to exclude internal nodes
sf_def_ids = {n['id'] for n in nodes if n.get('type') == 'subflow'}
# Get the flow tab ID
tab_id = None
for n in nodes:
    if n.get('type') == 'tab' and n.get('label') == 'protocol-normalization':
        tab_id = n['id']
        break
# Find normalize function nodes on the flow tab (exclude subflow internals)
normalize_funcs = [n for n in nodes if n.get('type') == 'function' and 'normalize' in n.get('name', '') and n.get('z') == tab_id]
if len(normalize_funcs) < 4:
    sys.exit(1)
# Check each wires to the subflow instance
for func in normalize_funcs:
    wires = func.get('wires', [[]])
    all_targets = []
    for w in wires:
        all_targets.extend(w)
    if sf_id not in all_targets:
        print(f'Function {func[\"name\"]} does not wire to normalize-output subflow', file=sys.stderr)
        sys.exit(1)
sys.exit(0)
" 2>/dev/null; then
    pass "All normalize functions wire to normalize-output subflow"
else
    fail "Not all normalize functions wire to normalize-output subflow"
fi

# -------------------------------------------------------
# 7. No Duplicate Broker Config Tests
# -------------------------------------------------------
echo ""
echo "--- No Duplicate Broker Config ---"

# Test 6.8: No new Local Mosquitto broker config nodes
if python3 -c "
import json, sys
with open('$FLOW_FILE') as f:
    nodes = json.load(f)
brokers = [n for n in nodes if n.get('type') == 'mqtt-broker']
sys.exit(0 if len(brokers) == 1 else 1)
" 2>/dev/null; then
    pass "Exactly one MQTT broker config (no duplicates)"
else
    fail "Multiple MQTT broker configs found (should be exactly 1)"
fi

# -------------------------------------------------------
# 8. Flow Tab Comment Tests
# -------------------------------------------------------
echo ""
echo "--- Flow Tab Comment Validation ---"

# Test 6.9: Comment node documents all protocols
if python3 -c "
import json, sys
with open('$FLOW_FILE') as f:
    nodes = json.load(f)
comments = [n for n in nodes if n.get('type') == 'comment']
if not comments:
    sys.exit(1)
info = comments[0].get('info', '')
required_protocols = ['OPC-UA', 'BACnet', 'Modbus', 'LoRaWAN', 'Zigbee', 'Z-Wave', 'LwM2M', 'SNMP']
for p in required_protocols:
    if p.lower() not in info.lower():
        print(f'Comment missing protocol: {p}', file=sys.stderr)
        sys.exit(1)
sys.exit(0)
" 2>/dev/null; then
    pass "Flow comment documents all supported protocols"
else
    fail "Flow comment missing protocol documentation"
fi

# -------------------------------------------------------
# 9. Flow tab info updated
# -------------------------------------------------------
echo ""
echo "--- Flow Tab Info Validation ---"

if python3 -c "
import json, sys
with open('$FLOW_FILE') as f:
    nodes = json.load(f)
tabs = [n for n in nodes if n.get('type') == 'tab' and n.get('label') == 'protocol-normalization']
if not tabs:
    sys.exit(1)
info = tabs[0].get('info', '')
# Should mention OPC-UA, BACnet as supported (not just scaffolded)
sys.exit(0 if 'OPC-UA' in info and 'BACnet' in info and 'Scaffolded' not in info else 1)
" 2>/dev/null; then
    pass "Flow tab info updated (no longer says Scaffolded)"
else
    fail "Flow tab info still says Scaffolded for OPC-UA/BACnet"
fi

# -------------------------------------------------------
# 10. Environment Variable Validation
# -------------------------------------------------------
echo ""
echo "--- Environment Variable Validation ---"

ENV_FILE="$EDGE_DIR/.env.example"

for var in OPCUA_HOST OPCUA_PORT BACNET_INTERFACE BACNET_PORT SERIAL_PORT SERIAL_BAUD MODBUS_RTU_UNIT_ID MODBUS_RTU_POLL_INTERVAL_MS; do
    if grep -q "^${var}=" "$ENV_FILE" 2>/dev/null; then
        pass ".env.example contains $var"
    else
        fail ".env.example missing $var"
    fi
done

# Test: docker-compose.yml passes new env vars
COMPOSE_FILE="$EDGE_DIR/docker-compose.yml"
for var in OPCUA_HOST OPCUA_PORT BACNET_INTERFACE BACNET_PORT SERIAL_PORT SERIAL_BAUD MODBUS_RTU_UNIT_ID MODBUS_RTU_POLL_INTERVAL_MS; do
    if grep -q "$var" "$COMPOSE_FILE" 2>/dev/null; then
        pass "docker-compose.yml passes $var"
    else
        fail "docker-compose.yml missing $var"
    fi
done

# -------------------------------------------------------
# 11. Regression: Story 1.3 nodes still present
# -------------------------------------------------------
echo ""
echo "--- Regression: Story 1.3 Core Nodes ---"

if python3 -c "
import json, sys
with open('$FLOW_FILE') as f:
    nodes = json.load(f)
ids = {n['id'] for n in nodes}
required = [
    'pn01a0b0c0d0e000',  # tab
    'pn01a0b0c0d0e001',  # comment
    'pn01a0b0c0d0e0bb',  # broker
    'pn01a0b0c0d0e010',  # mqtt-in
    'pn01a0b0c0d0e011',  # parse-topic
    'pn01a0b0c0d0e012',  # generic-normalize
    'pn01a0b0c0d0e0cc',  # modbus-client
    'pn01a0b0c0d0e020',  # modbus-read
    'pn01a0b0c0d0e021',  # modbus-normalize
    'pn01a0b0c0d0e030',  # normalize-output subflow instance
    'pn01a0b0c0d0e031',  # publish normalized
    'pn01a0b0c0d0e040',  # catch
    'pn01a0b0c0d0e041',  # error-log
]
for rid in required:
    if rid not in ids:
        print(f'Missing Story 1.3 node: {rid}', file=sys.stderr)
        sys.exit(1)
sys.exit(0)
" 2>/dev/null; then
    pass "All Story 1.3 core nodes still present"
else
    fail "Some Story 1.3 core nodes are missing (regression)"
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
