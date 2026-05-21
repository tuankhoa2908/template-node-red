const fs = require('fs');
const path = require('path');

// Đọc file inverters.config.json
const configFile = path.join(__dirname, 'inverters.config.json');
const config = JSON.parse(fs.readFileSync(configFile, 'utf8'));
const inverters = config.inverters.filter(inv => inv.enabled !== false);

// Bắt đầu tạo JSON của flow
const flow = [];

// Đọc và đưa Subflow definition vào file chung luôn để tránh lỗi 'unknown subflow'
const subflowFile = path.join(__dirname, 'sf_solaredge_inverter_reader.json');
const subflowDef = JSON.parse(fs.readFileSync(subflowFile, 'utf8'));
flow.push(...subflowDef);

const tabId = "flow_generated_parallel";

flow.push({
    "id": tabId,
    "type": "tab",
    "label": `Parallel Inverters (${inverters.length})`,
    "disabled": false,
    "info": "Tự động sinh bởi script. Chạy song song 100% bằng Subflow."
});

// Nút Inject duy nhất để trigger đọc (Poll mỗi 15s)
const injectId = "trigger_all_inverters";
flow.push({
    "id": injectId,
    "type": "inject",
    "z": tabId,
    "name": "Poll every 15s",
    "props": [{ "p": "payload" }],
    "repeat": "15",
    "crontab": "",
    "once": false,
    "onceDelay": 0.1,
    "topic": "",
    "payload": "",
    "payloadType": "date",
    "x": 140,
    "y": 100,
    "wires": [[]]
});

// Nút Join (tổng hợp dữ liệu)
const joinId = "join_all_inverters";
flow.push({
    "id": joinId,
    "type": "join",
    "z": tabId,
    "name": "Aggregate",
    "mode": "auto",
    "build": "array",
    "property": "payload",
    "propertyType": "msg",
    "key": "topic",
    "joiner": "\\n",
    "joinerType": "str",
    "accumulate": false,
    "timeout": "10",
    "count": "",
    "reduceRight": false,
    "reduceExp": "",
    "reduceInit": "",
    "reduceInitType": "",
    "reduceFixup": "",
    "x": 600,
    "y": 100,
    "wires": [["summary_function"]]
});

flow.push({
    "id": "summary_function",
    "type": "function",
    "z": tabId,
    "name": "Build Summary",
    "func": "const results = msg.payload || [];\nlet totalPower = 0;\nlet totalEnergy = 0;\nconst details = [];\n\nfor (const r of results) {\n    if (r && r.name) {\n        totalPower += (r.Pinv_out_kw || 0);\n        totalEnergy += (r.Ainv_total_kWh || 0);\n        details.push({ name: r.name, kW: r.Pinv_out_kw, kWh: r.Ainv_total_kWh });\n    }\n}\n\nconst summary = {\n    ts: Math.floor(Date.now() / 1000),\n    total_inverters: results.length,\n    total_power_kW: Math.round(totalPower * 1000) / 1000,\n    total_energy_kWh: Math.round(totalEnergy * 1000) / 1000,\n    details\n};\n\nglobal.set('INV_SUMMARY', summary);\nmsg.payload = summary;\nmsg.topic = 'inverter/summary';\nnode.status({ fill: 'green', shape: 'dot', text: `${results.length} INV | ${summary.total_power_kW}kW` });\nreturn msg;",
    "outputs": 1,
    "timeout": 0,
    "noerr": 0,
    "initialize": "",
    "finalize": "",
    "libs": [],
    "x": 780,
    "y": 100,
    "wires": [["debug_summary"]]
});

flow.push({
    "id": "debug_summary",
    "type": "debug",
    "z": tabId,
    "name": "Summary / debug",
    "active": true,
    "tosidebar": true,
    "console": false,
    "tostatus": false,
    "complete": "payload",
    "targetType": "msg",
    "x": 980,
    "y": 100,
    "wires": []
});

// Sinh Subflow node cho mỗi Inverter
let startY = 180;
const injectNodeIndex = flow.findIndex(n => n.id === injectId);

inverters.forEach((inv, i) => {
    const subflowId = `subflow_inst_${i}`;
    
    // Nối Inject -> Subflow
    flow[injectNodeIndex].wires[0].push(subflowId);

    // Node Subflow
    flow.push({
        "id": subflowId,
        "type": "subflow:sf_solaredge_inv_reader",
        "z": tabId,
        "name": `Read ${inv.name}`,
        "env": [
            { "name": "INV_NAME", "value": inv.name, "type": "str" },
            { "name": "INV_IP", "value": inv.ip, "type": "str" },
            { "name": "INV_PORT", "value": String(inv.port || 1502), "type": "num" },
            { "name": "INV_UNITID", "value": String(inv.unitid || 1), "type": "num" },
            { "name": "START_PLC", "value": String(inv.startPLC || config.defaults.startPLC || 40070), "type": "num" },
            { "name": "END_PLC", "value": String(inv.endPLC || config.defaults.endPLC || 40096), "type": "num" }
        ],
        "x": 380,
        "y": startY,
        "wires": [
            [joinId], // Output 1 -> Join
            []        // Output 2 -> Lỗi (ko nối)
        ]
    });
    
    startY += 60; // Dịch xuống dòng tiếp theo
});

const outFile = path.join(__dirname, 'generated_parallel_flow.json');
fs.writeFileSync(outFile, JSON.stringify(flow, null, 2));
console.log(`Đã tạo thành công ${inverters.length} subflow(s) vào file ${outFile}`);
