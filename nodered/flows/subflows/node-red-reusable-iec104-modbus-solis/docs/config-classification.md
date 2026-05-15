# Cách phân loại cấu hình

## .env

```env
MODBUS_HOST=192.168.1.254
MODBUS_PORT=502
MQTT_HOST=tichhop-vhouse-1414289788.udata.ai
MQTT_PORT=8883
MQTT_TOPIC=tichhop-vhouse/pms/tichhop-vhouse/det-chungtien
SITE_CONFIG_PATH=/data/config/site.solis.json
IEC104_DAEMON_PATH=/usr/local/bin/json-iec104-server
```

## site.solis.json

- Modbus register map
- IEC104 IOA map
- IEC104 command map
- MQTT payload fields
- Snapshot keys

## iec104_config.json

- ASDU
- IEC104 type config
- command mode
- deadband
