package com.meshnetprotocol.android.market

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

object MarketRepository {
    private const val TAG = "MarketRepository"
    private const val BASE_URL = "https://openmesh-api.ribencong.workers.dev/api/v1"

    suspend fun fetchRecommendedProviders(): List<TrafficProvider> = withContext(Dispatchers.IO) {
        val endpoint = "$BASE_URL/market/recommended"
        Log.d(TAG, "Fetching recommended providers from $endpoint")
        
        try {
            val url = URL(endpoint)
            val conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "GET"
            conn.connectTimeout = 20_000
            conn.readTimeout = 20_000
            conn.setRequestProperty("Cache-Control", "no-cache")
            
            val code = conn.responseCode
            if (code !in 200..299) {
                val errorBody = conn.errorStream?.bufferedReader()?.readText()
                throw Exception("HTTP $code: $errorBody")
            }
            
            val body = conn.inputStream.bufferedReader().readText()
            val json = JSONObject(body)
            val ok = json.optBoolean("ok", false)
            if (!ok) {
                val error = json.optString("error", "Unknown error")
                throw Exception(error)
            }
            
            val dataArray = json.optJSONArray("data")
            val providers = if (dataArray != null) {
                TrafficProvider.listFromJsonArray(dataArray)
            } else {
                emptyList()
            }
            
            Log.d(TAG, "Successfully fetched ${providers.size} recommended providers")
            providers
        } catch (e: Exception) {
            Log.e(TAG, "Failed to fetch recommended providers: ${e.message}")
            throw e
        }
    }

    suspend fun fetchAllProviders(): List<TrafficProvider> = withContext(Dispatchers.IO) {
        val endpoint = "$BASE_URL/market/manifest"
        Log.d(TAG, "Fetching all providers from $endpoint")
        
        try {
            val url = URL(endpoint)
            val conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "GET"
            conn.connectTimeout = 30_000
            conn.readTimeout = 30_000
            conn.setRequestProperty("Cache-Control", "no-cache")
            
            val code = conn.responseCode
            if (code !in 200..299) {
                val errorBody = conn.errorStream?.bufferedReader()?.readText()
                throw Exception("HTTP $code: $errorBody")
            }
            
            val body = conn.inputStream.bufferedReader().readText()
            val json = JSONObject(body)
            val ok = json.optBoolean("ok", false)
            if (!ok) {
                val error = json.optString("error", "Unknown error")
                throw Exception(error)
            }
            
            val providersArray = json.optJSONArray("providers")
            val providers = if (providersArray != null) {
                TrafficProvider.listFromJsonArray(providersArray)
            } else {
                emptyList()
            }
            
            Log.d(TAG, "Successfully fetched ${providers.size} providers from manifest")
            providers
        } catch (e: Exception) {
            Log.e(TAG, "Failed to fetch all providers: ${e.message}")
            throw e
        }
    }
}
