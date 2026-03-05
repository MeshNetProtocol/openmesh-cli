package com.meshnetprotocol.android.vpn.command

class CommandBridge {
    fun reload(): Result<Unit> = Result.success(Unit)

    @Suppress("UNUSED_PARAMETER")
    fun urlTest(group: String?): Result<Map<String, Int>> {
        return Result.success(emptyMap())
    }

    @Suppress("UNUSED_PARAMETER")
    fun selectOutbound(group: String, outbound: String): Result<Unit> {
        return Result.success(Unit)
    }

    @Suppress("UNUSED_PARAMETER")
    fun updateRules(content: String): Result<Unit> {
        return Result.success(Unit)
    }
}
