package com.meshnetprotocol.android.market

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

class MarketCache(private val context: Context) {
    private val TAG = "MarketCache"

    private val recommendedCacheFile = File(context.cacheDir, "market_cache/market_recommended.json")
    private val manifestCacheFile = File(context.cacheDir, "market_cache/market_manifest.json")

    fun getCachedRecommended(): List<TrafficProvider> {
        return try {
            if (!recommendedCacheFile.exists()) return emptyList()
            val content = recommendedCacheFile.readText()
            val array = JSONArray(content)
            TrafficProvider.listFromJsonArray(array)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to read recommended cache", e)
            emptyList()
        }
    }

    fun saveCachedRecommended(providers: List<TrafficProvider>) {
        try {
            val array = JSONArray()
            providers.forEach { provider ->
                val obj = JSONObject()
                obj.put("id", provider.id)
                obj.put("name", provider.name)
                obj.put("description", provider.description)
                obj.put("config_url", provider.config_url)
                obj.put("tags", JSONArray(provider.tags))
                obj.put("author", provider.author)
                obj.put("updated_at", provider.updated_at)
                obj.put("provider_hash", provider.provider_hash)
                obj.put("package_hash", provider.package_hash)
                obj.put("price_per_gb_usd", provider.price_per_gb_usd)
                obj.put("detail_url", provider.detail_url)
                array.put(obj)
            }
            
            recommendedCacheFile.parentFile?.mkdirs()
            recommendedCacheFile.writeText(array.toString())
            Log.d(TAG, "Saved ${providers.size} providers to recommended cache")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save recommended cache", e)
        }
    }

    fun getCachedManifest(): List<TrafficProvider> {
        return try {
            if (!manifestCacheFile.exists()) return emptyList()
            val content = manifestCacheFile.readText()
            val array = JSONArray(content)
            TrafficProvider.listFromJsonArray(array)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to read manifest cache", e)
            emptyList()
        }
    }

    fun saveCachedManifest(providers: List<TrafficProvider>) {
        try {
            val array = JSONArray()
            providers.forEach { provider ->
                val obj = JSONObject()
                obj.put("id", provider.id)
                obj.put("name", provider.name)
                obj.put("description", provider.description)
                obj.put("config_url", provider.config_url)
                obj.put("tags", JSONArray(provider.tags))
                obj.put("author", provider.author)
                obj.put("updated_at", provider.updated_at)
                obj.put("provider_hash", provider.provider_hash)
                obj.put("package_hash", provider.package_hash)
                obj.put("price_per_gb_usd", provider.price_per_gb_usd)
                obj.put("detail_url", provider.detail_url)
                array.put(obj)
            }
            
            manifestCacheFile.parentFile?.mkdirs()
            manifestCacheFile.writeText(array.toString())
            Log.d(TAG, "Saved ${providers.size} providers to manifest cache")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save manifest cache", e)
        }
    }
}
