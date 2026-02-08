/**
 * OpenMesh API - Traffic Market & AASA
 */

interface Env {
    IOS_TEAM_ID?: string;
    IOS_BUNDLE_ID?: string;
    UL_PATHS?: string;
}

interface TrafficProvider {
    id: string;
    name: string;
    description: string;
    config_url: string;
    tags: string[];
    icon_url?: string;
    author: string;
    updated_at: string;
}

// Mock Data
const MOCK_PROVIDERS: TrafficProvider[] = [
    {
        id: "official-cn",
        name: "OpenMesh Official (CN)",
        description: "Optimized for users in China accessing global internet. Includes automatic routing rules.",
        config_url: "https://market.openmesh.network/api/v1/config/official-cn", // In real deployment, this would be the worker's own URL
        tags: ["Official", "CN-Optimized", "Stable"],
        author: "OpenMesh Team",
        updated_at: "2024-02-08"
    },
    {
        id: "us-access-cn",
        name: "US to China",
        description: "For users in US accessing Chinese apps and websites (Bilibili, NetEase Music, etc).",
        config_url: "https://market.openmesh.network/api/v1/config/us-access-cn",
        tags: ["Community", "US-to-CN"],
        author: "Community Contributor",
        updated_at: "2024-02-01"
    }
];

// Mock Config Content (Simplified sing-box config structure)
// In reality, this would be fetched from R2 or KV
const MOCK_CONFIGS: Record<string, any> = {
    "official-cn": {
        "log": { "level": "info", "timestamp": true },
        "dns": {
            "servers": [
                { "tag": "google", "address": "tls://8.8.8.8", "detour": "proxy" },
                { "tag": "local", "address": "223.5.5.5", "detour": "direct" }
            ],
            "rules": [
                { "outbound": "any", "server": "local" },
                { "clash_mode": "Global", "server": "google" },
                { "clash_mode": "Direct", "server": "local" },
                { "rule_set": "geosite-cn", "server": "local" }
            ]
        },
        "inbounds": [
            {
                "type": "tun",
                "tag": "tun-in",
                "interface_name": "utun",
                "inet4_address": "172.19.0.1/30",
                "auto_route": true,
                "strict_route": true,
                "stack": "system"
            }
        ],
        "outbounds": [
            { "type": "selector", "tag": "proxy", "outbounds": ["auto", "direct"], "default": "auto" },
            { "type": "urltest", "tag": "auto", "outbounds": ["hk-01", "sg-01"], "url": "http://cp.cloudflare.com", "interval": "10m" },
            { "type": "direct", "tag": "direct" },
            { "type": "block", "tag": "block" },
            { "type": "dns", "tag": "dns-out" },
            // Mock Nodes
            { "type": "vless", "tag": "hk-01", "server": "hk.example.com", "server_port": 443, "uuid": "00000000-0000-0000-0000-000000000000", "flow": "xtls-rprx-vision", "tls": { "enabled": true, "server_name": "hk.example.com", "utls": { "enabled": true, "fingerprint": "chrome" }, "reality": { "enabled": true, "public_key": "x25519_public_key", "short_id": "12345678" } }, "packet_encoding": "xudp" },
            { "type": "vmess", "tag": "sg-01", "server": "sg.example.com", "server_port": 443, "uuid": "00000000-0000-0000-0000-000000000000", "security": "auto", "tls": { "enabled": true, "server_name": "sg.example.com" } }
        ],
        "route": {
            "rules": [
                { "protocol": "dns", "outbound": "dns-out" },
                { "clash_mode": "Direct", "outbound": "direct" },
                { "clash_mode": "Global", "outbound": "proxy" },
                { "rule_set": "geoip-cn", "outbound": "direct" },
                { "rule_set": "geosite-cn", "outbound": "direct" }
            ],
            "rule_set": [
                { "tag": "geoip-cn", "type": "local", "format": "binary", "path": "rule-set/geoip-cn.srs" },
                { "tag": "geosite-cn", "type": "local", "format": "binary", "path": "rule-set/geosite-geolocation-cn.srs" }
            ],
             "final": "proxy"
        }
    },
    "us-access-cn": {
        "log": { "level": "info", "timestamp": true },
        "inbounds": [
            { "type": "tun", "tag": "tun-in", "interface_name": "utun", "inet4_address": "172.19.0.1/30", "auto_route": true, "strict_route": true, "stack": "system" }
        ],
        "outbounds": [
             { "type": "direct", "tag": "direct" },
             { "type": "selector", "tag": "proxy", "outbounds": ["cn-sh-01"], "default": "cn-sh-01" },
             { "type": "shadowsocks", "tag": "cn-sh-01", "server": "sh.example.com", "server_port": 8388, "method": "aes-256-gcm", "password": "password" }
        ],
        "route": {
            "rules": [
                 { "rule_set": "geosite-cn", "outbound": "proxy" },
                 { "rule_set": "geoip-cn", "outbound": "proxy" }
            ],
            "rule_set": [
                { "tag": "geoip-cn", "type": "local", "format": "binary", "path": "rule-set/geoip-cn.srs" },
                { "tag": "geosite-cn", "type": "local", "format": "binary", "path": "rule-set/geosite-geolocation-cn.srs" }
            ],
            "final": "direct"
        }
    }
};


function normalizePaths(paths: string[]): string[] {
    const out: string[] = [];
    for (const p of paths) {
        if (!p) continue;
        let s = p.trim();
        if (!s.startsWith("/")) s = "/" + s;
        out.push(s);
    }
    return Array.from(new Set(out));
}

function buildAASA(env: Env) {
    const teamId = (env.IOS_TEAM_ID || "TEAMID").trim();
    const bundleId = (env.IOS_BUNDLE_ID || "com.MeshNetProtocol.OpenMesh.OpenMesh").trim();
    const appID = `${teamId}.${bundleId}`;
    const rawPaths = (env.UL_PATHS || "/callback").split(",").map(s => s.trim()).filter(Boolean);
    const basePaths = normalizePaths(rawPaths);

    const paths: string[] = [];
    for (const bp of basePaths) {
        paths.push(bp);
        if (bp !== "/") {
            paths.push(`${bp}*`);
            paths.push(bp.endsWith("/") ? `${bp}*` : `${bp}/*`);
        } else {
            paths.push("/*");
        }
    }

    return {
        applinks: {
            apps: [],
            details: [{ appID, paths }],
        },
        webcredentials: { apps: [appID] },
    };
}

function json(resObj: unknown, status = 200, extraHeaders: Record<string, string> = {}) {
    return new Response(JSON.stringify(resObj), {
        status,
        headers: {
            "Content-Type": "application/json",
            "Cache-Control": "public, max-age=300",
            "Access-Control-Allow-Origin": "*", // Allow CORS for all API responses
            ...extraHeaders,
        },
    });
}

export default {
    async fetch(request: Request, env: Env): Promise<Response> {
        const url = new URL(request.url);
        const path = url.pathname;

        if (request.method === "OPTIONS") {
            return new Response(null, {
                status: 204,
                headers: {
                    "Access-Control-Allow-Origin": "*",
                    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
                    "Access-Control-Allow-Headers": "Content-Type, Authorization",
                    "Access-Control-Max-Age": "86400",
                },
            });
        }

        // AASA
        if (request.method === "GET" && (path === "/.well-known/apple-app-site-association" || path === "/apple-app-site-association")) {
            return json(buildAASA(env));
        }

        // Market API: List Providers
        if (request.method === "GET" && path === "/api/v1/providers") {
            // Update URLs to match current request host if needed, or keep hardcoded for now
            // For local dev, we might want to replace the host
            const host = url.host;
            const protocol = url.protocol;
            const baseUrl = `${protocol}//${host}`;
            
            const providers = MOCK_PROVIDERS.map(p => ({
                ...p,
                config_url: p.config_url.replace("https://market.openmesh.network", baseUrl)
            }));
            
            return json({
                ok: true,
                data: providers
            });
        }

        // Market API: Get Config
        // Route: /api/v1/config/:id
        const configMatch = path.match(/^\/api\/v1\/config\/([^\/]+)$/);
        if (request.method === "GET" && configMatch) {
            const id = configMatch[1];
            const config = MOCK_CONFIGS[id];
            if (config) {
                return json(config);
            } else {
                return json({ ok: false, error: "Config not found" }, 404);
            }
        }

        // Health
        if (path === "/api/health") {
            return json({ status: "healthy", timestamp: new Date().toISOString() });
        }

        return json({
            service: "OpenMesh Market API",
            endpoints: {
                "/api/v1/providers": "List traffic providers",
                "/api/v1/config/:id": "Get provider config",
                "/api/health": "Health check"
            }
        });
    },
} satisfies ExportedHandler<Env>;
