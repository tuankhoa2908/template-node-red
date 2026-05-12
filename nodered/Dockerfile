FROM nodered/node-red:4.1.9

# Install build tools for native npm packages (e.g. node-red-node-sqlite)
USER root
RUN apk add --no-cache python3 make g++ sqlite-dev

# Copy IEC104 server binary
COPY bin/json-iec104-server /usr/local/bin/json-iec104-server
RUN sed -i 's/\r$//' /usr/local/bin/json-iec104-server \
 && chmod +x /usr/local/bin/json-iec104-server

USER node-red

# Pre-install Node-RED extra packages into /data
# When the named volume is first created, Docker initializes it from this directory
COPY package.json /data/package.json
WORKDIR /data
RUN npm install --unsafe-perm --no-update-notifier --no-fund --only=production
WORKDIR /usr/src/node-red
