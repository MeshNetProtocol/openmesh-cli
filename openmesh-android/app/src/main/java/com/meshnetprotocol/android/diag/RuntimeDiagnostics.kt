package com.meshnetprotocol.android.diag

import org.json.JSONObject
import java.io.File

object RuntimeDiagnostics {
    fun writeRuntimeDiag(target: File, values: Map<String, Any?>) {
        target.parentFile?.mkdirs()
        target.writeText(JSONObject(values).toString(2), Charsets.UTF_8)
    }
}
