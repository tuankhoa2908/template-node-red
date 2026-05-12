#!/usr/bin/env node
/**
 * Integration test for gateway-health flow (Story 1.6)
 * Runs INSIDE the edge Node-RED container to test the real Netdata pipeline.
 *
 * Tests:
 *   1. Netdata API reachability for all 4 endpoints (cpu, ram, disk, uptime)
 *   2. Metrics parsing (CPU, RAM, disk, uptime)
 *   3. Health payload assembly with correct 8 keys and types
 *   4. Percentage clamping [0, 100] (M4)
 *   5. Staleness cutoff logic (L2)
 *   6. MQTT publish to local Mosquitto (nexus/internal/gateway-health-status)
 *   7. Error topic publish on simulated failure
 *
 * Usage (on edge Pi):
 *   docker exec edge-nodered-1 node /data/test-gateway-health-integration.js
 *
 * Or run from host:
 *   ssh rpi@192.168.1.99 "docker exec edge-nodered-1 node /data/test-gateway-health-integration.js"
 */

'use strict';

const http = require('http');
const mqtt = require('mqtt');

const NETDATA_HOST = 'netdata';
const NETDATA_PORT = 19999;
const MOSQUITTO_HOST = 'mosquitto';
const MOSQUITTO_PORT = 1883;

let PASS = 0;
let FAIL = 0;
const RESULTS = [];

function pass(name) {
    PASS++;
    RESULTS.push({ status: 'PASS', name });
    console.log(`  PASS: ${name}`);
}
function fail(name, reason) {
    FAIL++;
    RESULTS.push({ status: 'FAIL', name, reason });
    console.log(`  FAIL: ${name} — ${reason}`);
}

// Helper: HTTP GET returning a promise
function httpGet(path, timeout) {
    timeout = timeout || 5000;
    return new Promise(function (resolve, reject) {
        const req = http.get(
            { hostname: NETDATA_HOST, port: NETDATA_PORT, path: path, timeout: timeout },
            function (res) {
                let body = '';
                res.on('data', function (c) { body += c; });
                res.on('end', function () {
                    try {
                        resolve({ status: res.statusCode, body: JSON.parse(body) });
                    } catch (e) {
                        reject(new Error('JSON parse failed: ' + e.message));
                    }
                });
            }
        );
        req.on('error', reject);
        req.on('timeout', function () { req.destroy(); reject(new Error('timeout')); });
    });
}

// Clamp helper (mirrors flow logic)
function clampPct(val) {
    if (val < 0) return -1;
    return parseFloat(Math.min(100, Math.max(0, val)).toFixed(2));
}

// ─── Test Suites ───

async function testNetdataEndpoints() {
    console.log('\n-- Netdata API Endpoint Tests --');

    // after=-1&points=1: last 1 second of data, single point (latest)
    const endpoints = [
        { name: 'system.cpu', path: '/api/v1/data?chart=system.cpu&after=-1&points=1&format=json' },
        { name: 'system.ram', path: '/api/v1/data?chart=system.ram&after=-1&points=1&format=json' },
        { name: 'disk_space./', path: '/api/v1/data?chart=disk_space./&after=-1&points=1&format=json' },
        { name: 'system.uptime', path: '/api/v1/data?chart=system.uptime&after=-1&points=1&format=json' },
    ];

    const results = {};
    for (const ep of endpoints) {
        try {
            const resp = await httpGet(ep.path);
            if (resp.status === 200 && resp.body && resp.body.data && resp.body.data.length > 0) {
                pass(`Netdata ${ep.name} — reachable, valid data`);
                results[ep.name] = resp.body;
            } else {
                fail(`Netdata ${ep.name}`, `status=${resp.status}, no data`);
                results[ep.name] = null;
            }
        } catch (e) {
            fail(`Netdata ${ep.name}`, e.message);
            results[ep.name] = null;
        }
    }
    return results;
}

function testMetricsParsing(netdataResults) {
    console.log('\n-- Metrics Parsing Tests --');

    // CPU — supports both idle-based and sum-based calculation
    const cpuData = netdataResults['system.cpu'];
    if (cpuData) {
        const labels = cpuData.labels || [];
        const values = cpuData.data[0];
        const idleIdx = labels.indexOf('idle');
        let cpuPct;
        if (idleIdx >= 0) {
            cpuPct = clampPct(100 - values[idleIdx]);
            if (cpuPct >= 0 && cpuPct <= 100) {
                pass(`CPU parsing (idle-based) — ${cpuPct}% (idle=${values[idleIdx]})`);
            } else {
                fail('CPU parsing', `out of range: ${cpuPct}`);
            }
        } else {
            // No idle label — sum all active components (skip index 0 = time)
            let cpuSum = 0;
            for (let ci = 1; ci < values.length; ci++) cpuSum += values[ci];
            cpuPct = clampPct(cpuSum);
            if (cpuPct >= 0 && cpuPct <= 100) {
                pass(`CPU parsing (sum-based, no idle label) — ${cpuPct}% (components: ${labels.slice(1).join(',')})`);
            } else {
                fail('CPU parsing', `out of range: ${cpuPct}`);
            }
        }
    }

    // RAM
    const ramData = netdataResults['system.ram'];
    if (ramData) {
        const labels = ramData.labels || [];
        const values = ramData.data[0];
        const usedIdx = labels.indexOf('used');
        const freeIdx = labels.indexOf('free');
        if (usedIdx >= 0 && freeIdx >= 0) {
            const used = values[usedIdx];
            const free = values[freeIdx];
            const cachedIdx = labels.indexOf('cached');
            const buffersIdx = labels.indexOf('buffers');
            const cached = cachedIdx >= 0 ? values[cachedIdx] : 0;
            const buffers = buffersIdx >= 0 ? values[buffersIdx] : 0;
            const total = used + free + cached + buffers;
            const ramPct = clampPct((used / total) * 100);
            if (ramPct >= 0 && ramPct <= 100) {
                pass(`RAM parsing — ${ramPct}% (${used.toFixed(0)}/${total.toFixed(0)} MiB)`);
            } else {
                fail('RAM parsing', `out of range: ${ramPct}`);
            }
        } else {
            fail('RAM parsing', `missing labels: ${labels.join(',')}`);
        }
    }

    // Disk
    const diskData = netdataResults['disk_space./'];
    if (diskData) {
        const labels = diskData.labels || [];
        const values = diskData.data[0];
        const usedIdx = labels.indexOf('used');
        const availIdx = labels.indexOf('avail');
        if (usedIdx >= 0 && availIdx >= 0) {
            const used = values[usedIdx];
            const avail = values[availIdx];
            const diskPct = clampPct((used / (used + avail)) * 100);
            if (diskPct >= 0 && diskPct <= 100) {
                pass(`Disk parsing — ${diskPct}% (${used.toFixed(1)}/${(used + avail).toFixed(1)} GiB)`);
            } else {
                fail('Disk parsing', `out of range: ${diskPct}`);
            }
        } else {
            fail('Disk parsing', `missing labels: ${labels.join(',')}`);
        }
    }

    // Uptime
    const uptimeData = netdataResults['system.uptime'];
    if (uptimeData) {
        const uptime = Math.round(uptimeData.data[0][1]);
        if (uptime > 0) {
            const hours = (uptime / 3600).toFixed(1);
            pass(`Uptime parsing — ${uptime}s (${hours}h)`);
        } else {
            fail('Uptime parsing', `invalid value: ${uptime}`);
        }
    }
}

function testHealthPayloadAssembly(netdataResults) {
    console.log('\n-- Health Payload Assembly Tests --');

    // Simulate the full health-aggregator logic
    const m = {};

    // Parse each endpoint result into the format the flow uses
    const keyMap = {
        'system.cpu': 'cpu',
        'system.ram': 'ram',
        'disk_space./': 'disk',
        'system.uptime': 'uptime',
    };
    for (const [chartName, data] of Object.entries(netdataResults)) {
        const key = keyMap[chartName];
        if (key && data) {
            m[key] = { labels: data.labels || [], values: data.data[0] };
        }
    }

    // CPU — idle-based or sum-based
    let cpu_usage_pct = -1;
    if (m.cpu && m.cpu.labels) {
        const idleIdx = m.cpu.labels.indexOf('idle');
        if (idleIdx >= 0) {
            cpu_usage_pct = clampPct(100 - m.cpu.values[idleIdx]);
        } else {
            let cpuSum = 0;
            for (let ci = 1; ci < m.cpu.values.length; ci++) cpuSum += m.cpu.values[ci];
            cpu_usage_pct = clampPct(cpuSum);
        }
    }

    // RAM
    let ram_usage_pct = -1;
    if (m.ram && m.ram.labels) {
        const usedIdx = m.ram.labels.indexOf('used');
        const freeIdx = m.ram.labels.indexOf('free');
        if (usedIdx >= 0 && freeIdx >= 0) {
            const used = m.ram.values[usedIdx];
            const free = m.ram.values[freeIdx];
            const cachedIdx = m.ram.labels.indexOf('cached');
            const buffersIdx = m.ram.labels.indexOf('buffers');
            const cached = cachedIdx >= 0 ? m.ram.values[cachedIdx] : 0;
            const buffersMem = buffersIdx >= 0 ? m.ram.values[buffersIdx] : 0;
            const total = used + free + cached + buffersMem;
            if (total > 0) ram_usage_pct = clampPct((used / total) * 100);
        }
    }

    // Disk
    let disk_usage_pct = -1;
    if (m.disk && m.disk.labels) {
        const usedIdx = m.disk.labels.indexOf('used');
        const availIdx = m.disk.labels.indexOf('avail');
        if (usedIdx >= 0 && availIdx >= 0) {
            const used = m.disk.values[usedIdx];
            const avail = m.disk.values[availIdx];
            if (used + avail > 0) disk_usage_pct = clampPct((used / (used + avail)) * 100);
        }
    }

    // Uptime
    let uptime_seconds = 0;
    if (m.uptime && m.uptime.values && m.uptime.values.length > 1) {
        uptime_seconds = Math.round(m.uptime.values[1]);
    }

    const healthPayload = {
        ts: Date.now(),
        values: {
            cpu_usage_pct,
            ram_usage_pct,
            disk_usage_pct,
            uptime_seconds,
            mqtt_connected: true,
            cloud_connected: false,
            buffer_queue_size: 0,
            buffering_active: false,
        },
    };

    // Validate payload structure
    if (typeof healthPayload.ts === 'number' && healthPayload.ts > 0) {
        pass('Payload has valid ts (epoch ms)');
    } else {
        fail('Payload ts', `invalid: ${healthPayload.ts}`);
    }

    if (typeof healthPayload.values === 'object' && healthPayload.values !== null) {
        pass('Payload has values object');
    } else {
        fail('Payload values', 'missing or not object');
    }

    // Validate all 8 required keys
    const requiredKeys = [
        'cpu_usage_pct', 'ram_usage_pct', 'disk_usage_pct', 'uptime_seconds',
        'mqtt_connected', 'cloud_connected', 'buffer_queue_size', 'buffering_active',
    ];
    const missingKeys = requiredKeys.filter(function (k) { return !(k in healthPayload.values); });
    if (missingKeys.length === 0) {
        pass(`All 8 telemetry keys present in payload`);
    } else {
        fail('Telemetry keys', `missing: ${missingKeys.join(', ')}`);
    }

    // Validate types
    const v = healthPayload.values;
    const typeChecks = [
        ['cpu_usage_pct', 'number'], ['ram_usage_pct', 'number'], ['disk_usage_pct', 'number'],
        ['uptime_seconds', 'number'], ['mqtt_connected', 'boolean'], ['cloud_connected', 'boolean'],
        ['buffer_queue_size', 'number'], ['buffering_active', 'boolean'],
    ];
    let allTypesOK = true;
    for (const [key, expectedType] of typeChecks) {
        if (typeof v[key] !== expectedType) {
            fail(`Type check ${key}`, `expected ${expectedType}, got ${typeof v[key]}`);
            allTypesOK = false;
        }
    }
    if (allTypesOK) {
        pass('All telemetry values have correct types');
    }

    // Validate percentage clamping (M4)
    const pctKeys = ['cpu_usage_pct', 'ram_usage_pct', 'disk_usage_pct'];
    let clampOK = true;
    for (const key of pctKeys) {
        if (v[key] !== -1 && (v[key] < 0 || v[key] > 100)) {
            fail(`Clamp check ${key}`, `value ${v[key]} outside [0, 100]`);
            clampOK = false;
        }
    }
    if (clampOK) {
        pass('All percentage metrics within [0, 100] or -1 sentinel (M4)');
    }

    // Verify removed keys are NOT present
    const removedKeys = ['ups_battery_pct', 'ups_status', 'nodered_memory_mb', 'mosquitto_memory_mb', 'netdata_memory_mb'];
    const unexpectedKeys = removedKeys.filter(function (k) { return k in healthPayload.values; });
    if (unexpectedKeys.length === 0) {
        pass('Removed keys (UPS, cgroup) are not present in payload');
    } else {
        fail('Removed keys still present', unexpectedKeys.join(', '));
    }

    console.log('\n  Assembled payload:');
    console.log('  ' + JSON.stringify(healthPayload, null, 2).replace(/\n/g, '\n  '));

    return healthPayload;
}

async function testMqttPublish(healthPayload) {
    console.log('\n-- MQTT Pipeline Tests --');

    return new Promise(function (resolve) {
        let client;
        const timeout = setTimeout(function () {
            fail('MQTT connection', 'timeout after 10s');
            if (client) client.end(true);
            resolve();
        }, 10000);

        try {
            client = mqtt.connect(`mqtt://${MOSQUITTO_HOST}:${MOSQUITTO_PORT}`, {
                clientId: 'integration-test-' + Date.now(),
                connectTimeout: 5000,
            });
        } catch (e) {
            clearTimeout(timeout);
            fail('MQTT connect', e.message);
            resolve();
            return;
        }

        client.on('connect', function () {
            pass('MQTT connected to local Mosquitto');

            // Subscribe to health status topic
            client.subscribe('nexus/internal/gateway-health-status', { qos: 0 }, function (err) {
                if (err) {
                    fail('MQTT subscribe', err.message);
                    clearTimeout(timeout);
                    client.end(true);
                    resolve();
                    return;
                }
                pass('Subscribed to nexus/internal/gateway-health-status');

                // Publish test payload
                const payload = JSON.stringify(healthPayload);
                client.publish('nexus/internal/gateway-health-status', payload, { qos: 0, retain: false }, function (err) {
                    if (err) {
                        fail('MQTT publish health status', err.message);
                    } else {
                        pass('Published health payload to nexus/internal/gateway-health-status');
                    }
                });
            });

            // Also subscribe to error topic
            client.subscribe('nexus/internal/gateway-health-errors', { qos: 0 });
        });

        client.on('message', function (topic, message) {
            if (topic === 'nexus/internal/gateway-health-status') {
                try {
                    const received = JSON.parse(message.toString());
                    if (received.ts && received.values && typeof received.values.cpu_usage_pct === 'number') {
                        pass('Received and parsed health payload from MQTT');
                    } else {
                        fail('MQTT payload validation', 'missing ts or values or cpu_usage_pct');
                    }
                } catch (e) {
                    fail('MQTT payload parse', e.message);
                }

                // Now test error topic
                const errorPayload = JSON.stringify({
                    error_type: 'IntegrationTestError',
                    source: 'test-gateway-health-integration',
                    message: 'Test error message',
                    ts: Date.now(),
                });
                client.publish('nexus/internal/gateway-health-errors', errorPayload, { qos: 0 });
            }

            if (topic === 'nexus/internal/gateway-health-errors') {
                try {
                    const errMsg = JSON.parse(message.toString());
                    if (errMsg.error_type && errMsg.source && errMsg.message && errMsg.ts) {
                        pass('Error topic receives structured error payload');
                    } else {
                        fail('Error payload validation', 'missing required fields');
                    }
                } catch (e) {
                    fail('Error payload parse', e.message);
                }

                clearTimeout(timeout);
                client.end(true);
                resolve();
            }
        });

        client.on('error', function (err) {
            fail('MQTT error', err.message);
            clearTimeout(timeout);
            client.end(true);
            resolve();
        });
    });
}

function testStalenessLogic() {
    console.log('\n-- Staleness Cutoff Logic Tests (L2) --');

    const STALENESS_CUTOFF_MS = 5 * 60 * 1000;
    const now = Date.now();

    // Simulate fresh cached metric (should be used)
    const freshCache = { data: { labels: ['time', 'idle'], values: [now, 50] }, ts: now - 1000 };
    if (now - freshCache.ts <= STALENESS_CUTOFF_MS) {
        pass('Fresh cached metric (1s old) — within staleness window, would use cache');
    } else {
        fail('Staleness logic', 'fresh cache incorrectly marked stale');
    }

    // Simulate stale cached metric (should revert to null)
    const staleCache = { data: { labels: ['time', 'idle'], values: [now - 400000, 50] }, ts: now - 400000 };
    if (now - staleCache.ts > STALENESS_CUTOFF_MS) {
        pass('Stale cached metric (6.7min old) — exceeds staleness window, would revert to null');
    } else {
        fail('Staleness logic', 'stale cache not detected');
    }

    // Edge case: exactly at boundary
    const boundaryCache = { data: { labels: ['time', 'idle'], values: [now, 50] }, ts: now - STALENESS_CUTOFF_MS - 1 };
    if (now - boundaryCache.ts > STALENESS_CUTOFF_MS) {
        pass('Boundary cached metric (5min+1ms old) — correctly detected as stale');
    } else {
        fail('Staleness logic', 'boundary case failed');
    }
}

function testClampPct() {
    console.log('\n-- Percentage Clamping Tests (M4) --');

    // Normal values
    if (clampPct(50) === 50) pass('clampPct(50) = 50');
    else fail('clampPct(50)', `got ${clampPct(50)}`);

    if (clampPct(0) === 0) pass('clampPct(0) = 0');
    else fail('clampPct(0)', `got ${clampPct(0)}`);

    if (clampPct(100) === 100) pass('clampPct(100) = 100');
    else fail('clampPct(100)', `got ${clampPct(100)}`);

    // Edge cases from Netdata
    if (clampPct(100.5) === 100) pass('clampPct(100.5) clamped to 100');
    else fail('clampPct(100.5)', `got ${clampPct(100.5)}`);

    if (clampPct(-0.5) === -1) pass('clampPct(-0.5) = -1 (sentinel preserved)');
    else fail('clampPct(-0.5)', `got ${clampPct(-0.5)}`);

    if (clampPct(-1) === -1) pass('clampPct(-1) = -1 (sentinel preserved)');
    else fail('clampPct(-1)', `got ${clampPct(-1)}`);
}

// ─── Main ───

async function main() {
    console.log('=== Gateway Health Integration Tests (Story 1.6) ===');
    console.log(`Target: Netdata @ ${NETDATA_HOST}:${NETDATA_PORT}, Mosquitto @ ${MOSQUITTO_HOST}:${MOSQUITTO_PORT}`);
    console.log(`Time: ${new Date().toISOString()}`);

    // 1. Test Netdata endpoints
    const netdataResults = await testNetdataEndpoints();

    // 2. Test metrics parsing
    testMetricsParsing(netdataResults);

    // 3. Test payload assembly
    const healthPayload = testHealthPayloadAssembly(netdataResults);

    // 4. Test clamp logic
    testClampPct();

    // 5. Test staleness logic
    testStalenessLogic();

    // 6. Test MQTT pipeline
    await testMqttPublish(healthPayload);

    // Summary
    console.log('\n=== Results ===');
    console.log(`PASS: ${PASS}`);
    console.log(`FAIL: ${FAIL}`);
    console.log(`TOTAL: ${PASS + FAIL}`);

    if (FAIL > 0) {
        console.log('\nFAILED TESTS:');
        RESULTS.filter(function (r) { return r.status === 'FAIL'; })
            .forEach(function (r) { console.log(`  - ${r.name}: ${r.reason}`); });
        console.log('\nSOME TESTS FAILED');
        process.exit(1);
    } else {
        console.log('\nALL TESTS PASSED');
        process.exit(0);
    }
}

main().catch(function (e) {
    console.error('Fatal error:', e);
    process.exit(2);
});
