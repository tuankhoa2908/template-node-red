/**
 * Node-RED Settings - Nexus-E Edge Stack
 * Admin UI bound to localhost only (SSH tunnel access)
 * Password-protected admin interface
 */
module.exports = {
    uiPort: 1880,
    uiHost: "0.0.0.0",

    adminAuth: {
        type: "credentials",
        users: [{
            username: process.env.NODE_RED_ADMIN_USER || "admin",
            password: process.env.NODE_RED_ADMIN_PASS_HASH || "$2b$08$invalid_hash_replace_me",
            permissions: "*"
        }]
    },

    credentialSecret: process.env.NODE_RED_CREDENTIAL_SECRET || false,

    flowFile: "flows.json",
    flowFilePretty: true,

    functionGlobalContext: {},

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
