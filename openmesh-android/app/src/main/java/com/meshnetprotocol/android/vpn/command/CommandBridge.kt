package com.meshnetprotocol.android.vpn.command

import com.meshnetprotocol.android.vpn.OpenMeshBoxService
import org.json.JSONObject

class CommandBridge(
    private val boxService: OpenMeshBoxService,
) {
    fun execute(commandJson: String): String {
        return runCatching {
            val request = JSONObject(commandJson)
            val action = request.optString("action", "").trim()
            when (action) {
                "reload" -> {
                    val result = boxService.reload()
                    if (result.isFailure) {
                        errorResponse(result.exceptionOrNull()?.message ?: "reload failed")
                    } else {
                        successResponse()
                    }
                }

                "urltest" -> {
                    val group = request.optString("group", "").trim().ifEmpty { null }
                    val result = boxService.urlTest(group)
                    if (result.isFailure) {
                        errorResponse(result.exceptionOrNull()?.message ?: "urltest failed")
                    } else {
                        val payload = JSONObject()
                        payload.put("ok", true)
                        payload.put("group", group ?: "")
                        payload.put("delays", JSONObject(result.getOrThrow()))
                        payload.toString()
                    }
                }

                "select_outbound" -> {
                    val group = request.optString("group", "").trim()
                    val outbound = request.optString("outbound", "").trim()
                    if (group.isEmpty() || outbound.isEmpty()) {
                        errorResponse("missing group/outbound")
                    } else {
                        val result = boxService.selectOutbound(group, outbound)
                        if (result.isFailure) {
                            errorResponse(result.exceptionOrNull()?.message ?: "select_outbound failed")
                        } else {
                            successResponse()
                        }
                    }
                }

                "update_rules" -> {
                    val format = request.optString("format", "json").trim()
                    val content = request.optString("content", "")
                    if (!format.equals("json", ignoreCase = true)) {
                        errorResponse("unsupported format")
                    } else if (content.isBlank()) {
                        errorResponse("missing content")
                    } else {
                        val result = boxService.updateRules(content)
                        if (result.isFailure) {
                            errorResponse(result.exceptionOrNull()?.message ?: "update_rules failed")
                        } else {
                            successResponse()
                        }
                    }
                }

                else -> errorResponse("unsupported action: $action")
            }
        }.getOrElse { errorResponse(it.message ?: "invalid command") }
    }

    private fun successResponse(): String {
        return JSONObject().put("ok", true).toString()
    }

    private fun errorResponse(message: String): String {
        return JSONObject().put("ok", false).put("error", message).toString()
    }
}
