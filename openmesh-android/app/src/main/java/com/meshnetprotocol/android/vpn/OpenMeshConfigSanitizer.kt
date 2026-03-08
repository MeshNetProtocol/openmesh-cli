package com.meshnetprotocol.android.vpn

import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * Android 运行期配置修正器。
 *
 * 设计原则：
 * 配置文件的路由/DNS 逻辑完全由 provider 负责，app 层不主动修改业务规则。
 *
 * 但有两处 Android 平台必须的修正（iOS 不需要，因为底层框架不同）：
 *
 * 1. auto_detect_interface = true
 *    Android 平台要求 protect socket，iOS 由 NetworkExtension 框架自动处理。
 *
 * 2. 修正 hijack-dns 必须在 sniff 之后的顺序 bug
 *    sing-box 中 `protocol: dns` 只有在 sniff 执行后才能被识别，
 *    hijack-dns 规则必须排在 sniff 之后才能生效。
 *    provider 配置生成的顺序是 [hijack-dns, sniff, ...]，在 iOS 上
 *    因 NetworkExtension DNS 拦截机制不受影响，但 Android 上会导致
 *    所有 DNS 请求落到 ip_is_private=true => direct，网络完全不可用。
 *
 * 3. injectFakeNodeForSingleNodeGroups（对齐 iOS）
 *    selector/urltest 组只有 1 个节点时 libbox 初始化异常，注入伪节点规避。
 */
object OpenMeshConfigSanitizer {
    private const val TAG = "OpenMeshConfigSanitizer"

    fun sanitize(configContent: String): String {
        return runCatching {
            val root = JSONObject(configContent)
            stripNonSingboxMetadata(root)
            ensureAutoDetectInterface(root)
            fixHijackDnsAfterSniff(root)
            injectFakeNodeForSingleNodeGroups(root)
            root.toString()
        }.onFailure {
            Log.e(TAG, "sanitize failed: ${it.message}")
        }.getOrDefault(configContent)
    }

    // ─── 去除非 sing-box 元数据 ─────────────────────────────────────────────

    private fun stripNonSingboxMetadata(root: JSONObject) {
        listOf(
            "author", "name", "title", "description", "version",
            "updated_at", "created_at", "package_hash",
            "provider_id", "provider_name", "tags", "x402", "wallet",
        ).forEach(root::remove)
    }

    // ─── Android 平台字段 ─────────────────────────────────────────────────────

    private fun ensureAutoDetectInterface(root: JSONObject) {
        val route = root.optJSONObject("route") ?: JSONObject().also { root.put("route", it) }
        route.put("auto_detect_interface", true)
        Log.i(TAG, "ensureAutoDetectInterface: set auto_detect_interface=true")

        // 强制 DNS 优先选用 IPv4，避免 Android 平台上常见的 IPv6 路由不可达问题
        val dns = root.optJSONObject("dns") ?: JSONObject().also { root.put("dns", it) }
        dns.put("strategy", "prefer_ipv4")

        // 找到 tun inbound 并强制设置 Android 必须的底层参数
        val inbounds = root.optJSONArray("inbounds") ?: return
        for (i in 0 until inbounds.length()) {
            val inbound = inbounds.optJSONObject(i) ?: continue
            if (inbound.optString("type") == "tun") {
                // 强制使用 gVisor 栈，这是 Android 平台最稳定的选择
                inbound.put("stack", "gvisor")
                inbound.put("mtu", 9000)
                inbound.put("auto_route", true)
                inbound.put("strict_route", true)
                // 彻底移除 IPv6 配置，防止引擎尝试在 TUN 上建立 IPv6 栈
                inbound.remove("inet6_address") 
                inbound.remove("inet6_route_address") 
                inbound.remove("inet6_route_range") 
                inbound.put("inet6_address", JSONArray()) 
                Log.i(TAG, "ensureAutoDetectInterface: applied Android TUN tweaks (stack=gvisor, mtu=9000, no-ipv6)")
            }
        }
    }

    // ─── 修正 sniff / hijack-dns 顺序 ─────────────────────────────────────────

    /**
     * sing-box 规则匹配顺序说明：
     *   - sniff 是一个"动作型"规则：执行后继续匹配后续规则
     *   - hijack-dns 依赖 `protocol: dns`，而 protocol 只有 sniff 执行之后才能被识别
     *   - 因此 sniff 必须在 hijack-dns 之前
     *
     * provider 配置文件当前生成顺序（错误）：
     *   [0] hijack-dns  ← protocol 尚未识别，永远不生效
     *   [1] sniff
     *
     * 修正后顺序：
     *   [0] sniff       ← 先识别 protocol
     *   [1] hijack-dns  ← 才能匹配 protocol=dns
     */
    private fun fixHijackDnsAfterSniff(root: JSONObject) {
        val route = root.optJSONObject("route") ?: return
        val rules = route.optJSONArray("rules") ?: return

        var hijackIdx = -1
        var sniffIdx = -1

        for (i in 0 until rules.length()) {
            val rule = rules.optJSONObject(i) ?: continue
            val action = rule.optString("action")
            val protocol = rule.optString("protocol")
            when {
                action == "hijack-dns" || (protocol == "dns" && action.isEmpty()) -> hijackIdx = i
                action == "sniff" -> sniffIdx = i
            }
        }

        when {
            hijackIdx < 0 && sniffIdx < 0 -> {
                Log.i(TAG, "fixHijackDnsAfterSniff: neither rule found, skip")
            }
            hijackIdx < 0 || sniffIdx < 0 -> {
                Log.i(TAG, "fixHijackDnsAfterSniff: only one of sniff/hijack-dns found (sniff=$sniffIdx hijack=$hijackIdx), skip")
            }
            sniffIdx < hijackIdx -> {
                // 顺序正确
                Log.i(TAG, "fixHijackDnsAfterSniff: order OK (sniff[$sniffIdx] < hijack[$hijackIdx])")
            }
            else -> {
                // 顺序错误：sniff 在 hijack-dns 之后，需要把 sniff 移到 hijack-dns 之前
                val rulesList = mutableListOf<JSONObject>()
                for (i in 0 until rules.length()) {
                    rules.optJSONObject(i)?.let { rulesList.add(it) }
                }
                val sniffRule = rulesList.removeAt(sniffIdx)
                // hijackIdx < sniffIdx，remove sniff 之后 hijackIdx 不变
                rulesList.add(hijackIdx, sniffRule)

                val newRules = JSONArray()
                rulesList.forEach { newRules.put(it) }
                route.put("rules", newRules)
                Log.i(TAG, "fixHijackDnsAfterSniff: fixed — moved sniff[$sniffIdx] to before hijack[$hijackIdx]")
            }
        }
    }

    // ─── injectFakeNode (对齐 iOS) ─────────────────────────────────────────────

    private fun injectFakeNodeForSingleNodeGroups(root: JSONObject) {
        val outbounds = root.optJSONArray("outbounds") ?: return
        var needsFakeNode = false

        for (i in 0 until outbounds.length()) {
            val outbound = outbounds.optJSONObject(i) ?: continue
            val type = outbound.optString("type").lowercase()
            if (type != "selector" && type != "urltest") continue
            val members = outbound.optJSONArray("outbounds") ?: continue
            if (members.length() == 1) {
                members.put("fake-node-for-testing")
                needsFakeNode = true
                Log.i(TAG, "injectFakeNode: group '${outbound.optString("tag")}' had 1 node, injected fake")
            }
        }

        if (needsFakeNode) {
            outbounds.put(JSONObject().apply {
                put("type", "shadowsocks")
                put("tag", "fake-node-for-testing")
                put("server", "127.0.0.1")
                put("server_port", 65535)
                put("password", "fake")
                put("method", "aes-128-gcm")
            })
            Log.i(TAG, "injectFakeNode: added fake-node-for-testing outbound")
        }
    }
}
