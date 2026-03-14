package com.meshnetprotocol.android.data.rules

import java.io.File

class RulesRepository(private val providersDirectory: File) {
    fun providerRulesFile(providerId: String): File {
        return File(providersDirectory, "$providerId/routing_rules.json")
    }

    fun writeRules(providerId: String, jsonContent: String): File {
        val target = providerRulesFile(providerId)
        target.parentFile?.mkdirs()
        val temp = File(target.parentFile, "${target.name}.tmp")
        temp.writeText(jsonContent)
        if (target.exists()) {
            target.delete()
        }
        temp.renameTo(target)
        return target
    }
}
