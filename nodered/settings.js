/**
 * Node-RED Settings - Nexus-E Edge Stack
 * Admin UI is published by Docker Compose. Keep the compose bind address on
 * localhost unless NODE_RED_ADMIN_PASSWORD or NODE_RED_ADMIN_PASS_HASH is set.
 */
function getAdminPasswordHash() {
    if (process.env.NODE_RED_ADMIN_PASS_HASH) {
        return process.env.NODE_RED_ADMIN_PASS_HASH;
    }

    if (process.env.NODE_RED_ADMIN_PASSWORD) {
        return require("bcryptjs").hashSync(process.env.NODE_RED_ADMIN_PASSWORD, 8);
    }

    return null;
}

const adminPasswordHash = getAdminPasswordHash();

const settings = {
    uiPort: 1880,
    uiHost: "0.0.0.0",

    credentialSecret: process.env.NODE_RED_CREDENTIAL_SECRET || false,

    flowFile: "flows.json",
    flowFilePretty: true,

    functionGlobalContext: {},

    contextStorage: {
        default: {
            module: "localfilesystem"
        }
    },

    logging: {
        console: {
            level: "info",
            metrics: false,
            audit: false
        }
    },

    exportGlobalContextKeys: false,

    editorTheme: {
        projects: {
            enabled: false
        }
    }
};

if (adminPasswordHash) {
    settings.adminAuth = {
        type: "credentials",
        users: [{
            username: process.env.NODE_RED_ADMIN_USER || "admin",
            password: adminPasswordHash,
            permissions: "*"
        }]
    };
}

module.exports = settings;
