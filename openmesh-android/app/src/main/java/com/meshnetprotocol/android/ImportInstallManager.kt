package com.meshnetprotocol.android

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONObject
import java.util.UUID

/**
 * 管理 Offline Import 的安装逻辑
 */
class ImportInstallManager(private val context: Context) {

    private val prefs: SharedPreferences = context.getSharedPreferences("openmesh_prefs", Context.MODE_PRIVATE)

    /**
     * 解析导入的配置文件内容
     * @return (providerID, providerName, packageHash, configData, routingRulesData, ruleSetURLMap)
     */
    fun parseImportPayload(text: String): ImportPayload {
        val rawData = if (text.isBase64Encoded()) {
            val decoded = android.util.Base64.decode(text, android.util.Base64.DEFAULT)
            String(decoded, Charsets.UTF_8)
        } else {
            text
        }.trim()

        val json = JSONObject(rawData)
        
        // 检查是否是 wrapper 格式
        val configAny = json.optJSONObject("config") 
            ?: json.optJSONObject("config_json") 
            ?: json.optJSONObject("configJSON") 
            ?: json.optJSONObject("singbox_config")

        if (configAny != null) {
            val providerID = json.optString("provider_id").orEmpty()
            val providerName = json.optString("name").orEmpty()
            val packageHash = json.optString("package_hash").orEmpty()
            
            val routingRulesData = json.optJSONObject("routing_rules")
                ?.toString()
                ?.toByteArray(Charsets.UTF_8)
            
            val ruleSetURLMap = parseRuleSetURLMap(
                json.optJSONObject("rule_set_urls")
                    ?: json.optJSONObject("ruleSetURLs")
                    ?: json.optJSONObject("rule_sets")
            )

            return ImportPayload(
                providerID = providerID,
                providerName = providerName,
                packageHash = packageHash,
                configData = configAny.toString().toByteArray(Charsets.UTF_8),
                routingRulesData = routingRulesData,
                ruleSetURLMap = ruleSetURLMap
            )
        }

        // 纯 config 格式
        return ImportPayload(
            providerID = "",
            providerName = "",
            packageHash = "",
            configData = rawData.toByteArray(Charsets.UTF_8),
            routingRulesData = null,
            ruleSetURLMap = null
        )
    }

    private fun parseRuleSetURLMap(obj: JSONObject?): Map<String, String> {
        if (obj == null) return emptyMap()
        
        val result = mutableMapOf<String, String>()
        obj.keys().forEach { key ->
            obj.optString(key)?.let { url ->
                if (url.isNotEmpty()) result[key] = url
            }
        }
        return result
    }

    /**
     * 生成 provider ID（如果未提供）
     */
    fun generateProviderID(): String {
        return "imported-${UUID.randomUUID().toString().take(8)}"
    }

    /**
     * 保存 rule_set_urls 到 SharedPreferences
     */
    fun saveRuleSetURLs(providerID: String, ruleSetURLMap: Map<String, String>) {
        val existing = getRuleSetURLs()
        val updated = existing.toMutableMap()
        updated[providerID] = ruleSetURLMap
        prefs.edit().putString("installed_provider_rule_set_urls", JSONObject(updated).toString()).apply()
    }

    private fun getRuleSetURLs(): Map<String, Map<String, String>> {
        val jsonStr = prefs.getString("installed_provider_rule_set_urls", "{}") ?: "{}"
        return try {
            val json = JSONObject(jsonStr)
            val result = mutableMapOf<String, Map<String, String>>()
            json.keys().forEach { providerID ->
                val mapJson = json.getJSONObject(providerID)
                val map = mutableMapOf<String, String>()
                mapJson.keys().forEach { tag ->
                    map[tag] = mapJson.getString(tag)
                }
                result[providerID] = map
            }
            result
        } catch (e: Exception) {
            emptyMap()
        }
    }

    /**
     * 保存 package_hash
     */
    fun savePackageHash(providerID: String, packageHash: String) {
        val existing = getPackageHashes()
        val updated = existing.toMutableMap()
        updated[providerID] = packageHash
        prefs.edit().putString("installed_provider_package_hash", JSONObject(updated).toString()).apply()
    }

    private fun getPackageHashes(): Map<String, String> {
        val jsonStr = prefs.getString("installed_provider_package_hash", "{}") ?: "{}"
        return try {
            val json = JSONObject(jsonStr)
            val result = mutableMapOf<String, String>()
            json.keys().forEach { key ->
                result[key] = json.getString(key)
            }
            result
        } catch (e: Exception) {
            emptyMap()
        }
    }

    /**
     * 保存 provider_id 到 profile 的映射
     */
    fun saveProviderIDByProfile(profileID: Long, providerID: String) {
        val existing = getProviderIDByProfile()
        val updated = existing.toMutableMap()
        updated[profileID.toString()] = providerID
        prefs.edit().putString("installed_provider_id_by_profile", JSONObject(updated).toString()).apply()
    }

    private fun getProviderIDByProfile(): Map<String, String> {
        val jsonStr = prefs.getString("installed_provider_id_by_profile", "{}") ?: "{}"
        return try {
            val json = JSONObject(jsonStr)
            val result = mutableMapOf<String, String>()
            json.keys().forEach { key ->
                result[key] = json.getString(key)
            }
            result
        } catch (e: Exception) {
            emptyMap()
        }
    }
}

/**
 * 导入配置的数据类
 */
data class ImportPayload(
    val providerID: String,
    val providerName: String,
    val packageHash: String,
    val configData: ByteArray,
    val routingRulesData: ByteArray?,
    val ruleSetURLMap: Map<String, String>?
)

/**
 * 检查字符串是否是 Base64 编码
 */
private fun String.isBase64Encoded(): Boolean {
    if (length < 10) return false
    if (trim().startsWith("{")) return false
    
    return try {
        val decoded = android.util.Base64.decode(this, android.util.Base64.DEFAULT)
        val reencoded = android.util.Base64.encodeToString(decoded, android.util.Base64.NO_WRAP)
        // 检查解码后是否是有效的 JSON
        String(decoded, Charsets.UTF_8).trim().startsWith("{")
    } catch (e: Exception) {
        false
    }
}
