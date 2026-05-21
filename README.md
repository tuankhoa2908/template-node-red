# template-node-red-pi

Repo nay dung de chay Node-RED tren Raspberry Pi bang Docker Compose. Mac dinh
chi chay Node-RED va cai san cac npm package trong `nodered/package.json`.

## 1. Chuan bi Pi

Tren Pi can co Docker va Docker Compose plugin:

```bash
docker --version
docker compose version
```

Neu Pi nam trong mang Tailscale, kiem tra IP Tailscale:

```bash
tailscale ip -4
```

Ghi lai IP dang `100.x.x.x`. IP nay se dung de mo Node-RED cho cac may khac
trong cung tailnet.

## 2. Lay source ve Pi

Lan dau:

```bash
git clone <repo-url>
cd template-node-red-pi
```

Nhung lan sau:

```bash
cd template-node-red-pi
git pull
```

## 3. Tao file `.env`

Repo co san `.env.example`. Tao `.env` rieng tren tung Pi:

```bash
cp .env.example .env
nano .env
```

Neu chi muon truy cap Node-RED bang SSH tunnel, co the de mac dinh:

```env
TZ=Asia/Ho_Chi_Minh
```

Neu muon truy cap truc tiep qua Tailscale, dat `NODERED_BIND` bang IP Tailscale
cua Pi:

```env
TZ=Asia/Ho_Chi_Minh
NODERED_BIND=100.x.x.x
NODE_RED_ADMIN_USER=admin
NODE_RED_ADMIN_PASSWORD=doi-mat-khau-nay
```

Khong nen dung `NODERED_BIND=0.0.0.0` neu chi can Tailscale, vi nhu vay
Node-RED se nghe ca tren LAN/Wi-Fi/Ethernet cua Pi.

Neu Node-RED co credential node can giu on dinh sau deploy, dat them:

```env
NODE_RED_CREDENTIAL_SECRET=doi-secret-nay
```

Nen set `NODE_RED_CREDENTIAL_SECRET` truoc khi tao credential trong Node-RED.

## 4. Chay Node-RED

Build image va start container:

```bash
docker compose up -d --build
```

Kiem tra trang thai:

```bash
docker compose ps
docker compose logs -f nodered
```

Neu dung Tailscale, mo tu may khac trong tailnet:

```text
http://100.x.x.x:1880
```

Neu de bind mac dinh `127.0.0.1`, dung SSH tunnel:

```bash
ssh -L 1880:127.0.0.1:1880 pi@<pi-host>
```

Sau do mo:

```text
http://127.0.0.1:1880
```

## 5. Cap nhat code ve sau

Khi repo co thay doi:

```bash
cd template-node-red-pi
git pull
docker compose up -d --build
```

Neu chi sua `docker-compose.yml`, `.env`, hoac `nodered/settings.js`, lenh tren
la du.

Neu sua `nodered/package.json`, Docker image se build lai. Luu y: Node-RED dung
named volume `template-node-red-pi-nodered-data` cho `/data`. Neu volume da ton
tai tu truoc, package moi trong image co the khong tu copy vao volume cu. Khi do
co hai cach:

```bash
docker compose exec nodered npm install --unsafe-perm --no-update-notifier --no-fund --only=production
docker compose restart nodered
```

Hoac, neu khong can giu flow/data hien tai:

```bash
docker compose down -v
docker compose up -d --build
```

Lenh `down -v` se xoa volume Node-RED data, can can than khi Pi da co flow that.

## 6. Dich vu tuy chon

Mac dinh chi chay Node-RED.

Bat Mosquitto:

```bash
docker compose --profile mqtt up -d --build
```

Bat Netdata:

```bash
docker compose --profile monitoring up -d --build
```

Bat tat ca:

```bash
docker compose --profile mqtt --profile monitoring up -d --build
```

## 7. Lenh van hanh nhanh

Restart Node-RED:

```bash
docker compose restart nodered
```

Xem log:

```bash
docker compose logs -f nodered
```

Dung stack:

```bash
docker compose down
```

Dung va xoa data volume:

```bash
docker compose down -v
```
