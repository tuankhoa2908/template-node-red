# IEC 60870-5-104 Server Binary

Place the `json-iec104-server` binary in this directory.

## Source

Copy from old production Pi:
```bash
scp pi@<old-pi-ip>:/home/pi/projects/json-iec104-server ./json-iec104-server
chmod +x ./json-iec104-server
```

## Requirements

- Architecture: arm64/linux (Raspberry Pi 4)
- The binary manages IEC104 protocol via stdin/stdout JSON
- Managed by `node-red-contrib-daemon` at runtime

## Interface

- **stdin**: JSON commands (newline-delimited)
- **stdout**: JSON data (newline-delimited)
- **start**: Send empty `msg.start` via daemon node
- **stop**: Send `{"type":"0","value":0,"address":0,"qualifier":"0"}`
- **shutdown**: SIGINT
