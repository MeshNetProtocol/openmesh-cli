package com.meshnetprotocol.android.market

import org.json.JSONArray
import org.json.JSONObject

data class TrafficProvider(
    val id: String,
    val name: String,
    val description: String,
    val config_url: String,
    val tags: List<String>,
    val author: String,
    val updated_at: String,
    val provider_hash: String?,
    val package_hash: String?,
    val price_per_gb_usd: Double?,
    val detail_url: String?
) {
    companion object {
        fun fromJson(obj: JSONObject): TrafficProvider {
            val tags = mutableListOf<String>()
            val tagsArray = obj.optJSONArray("tags")
            if (tagsArray != null) {
                for (i in 0 until tagsArray.length()) {
                    tags.add(tagsArray.optString(i))
                }
            }
            return TrafficProvider(
                id = obj.optString("id", ""),
                name = obj.optString("name", ""),
                description = obj.optString("description", ""),
                config_url = obj.optString("config_url", ""),
                tags = tags,
                author = obj.optString("author", ""),
                updated_at = obj.optString("updated_at", ""),
                provider_hash = obj.optString("provider_hash").takeIf { it.isNotEmpty() },
                package_hash = obj.optString("package_hash").takeIf { it.isNotEmpty() },
                price_per_gb_usd = if (obj.has("price_per_gb_usd")) obj.optDouble("price_per_gb_usd").takeIf { !it.isNaN() } else null,
                detail_url = obj.optString("detail_url").takeIf { it.isNotEmpty() }
            )
        }

        fun listFromJsonArray(array: JSONArray): List<TrafficProvider> {
            val list = mutableListOf<TrafficProvider>()
            for (i in 0 until array.length()) {
                val obj = array.optJSONObject(i) ?: continue
                list.add(fromJson(obj))
            }
            return list
        }
    }
}

data class MarketResponse(
    val ok: Boolean,
    val data: List<TrafficProvider>?,
    val error: String?
)

data class MarketManifestResponse(
    val ok: Boolean,
    val providers: List<TrafficProvider>?,
    val error: String?
)
