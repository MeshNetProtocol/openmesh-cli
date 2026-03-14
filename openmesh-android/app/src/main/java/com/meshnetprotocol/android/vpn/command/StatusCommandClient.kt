package com.meshnetprotocol.android.vpn.command

import android.os.Handler
import android.os.Looper
import android.util.Log
import libbox.CommandClientHandler
import libbox.CommandClientOptions
import libbox.ConnectionEvents
import libbox.Libbox
import libbox.LogIterator
import libbox.OutboundGroupIterator
import libbox.StatusMessage
import libbox.StringIterator

object StatusCommandClient {
    private const val TAG = "StatusCommandClient"
    private var commandClient: libbox.CommandClient? = null

    @Volatile
    var isConnected = false
        private set

    var uplinkTotal: Long = 0
        private set
    var downlinkTotal: Long = 0
        private set
    var uplink: Long = 0
        private set
    var downlink: Long = 0
        private set

    var onStatusUpdated: ((uplinkTotal: Long, downlinkTotal: Long, uplink: Long, downlink: Long) -> Unit)? = null

    @Synchronized
    fun connect() {
        if (isConnected || commandClient != null) return
        Thread {
            try {
                val options = CommandClientOptions()
                options.addCommand(Libbox.CommandStatus)
                options.statusInterval = 1_000_000_000L // 1 second

                val client = Libbox.newCommandClient(ClientHandler(), options)
                client.connect()
                commandClient = client
            } catch (e: Exception) {
                Log.e(TAG, "Connect failed: ${e.message}")
            }
        }.start()
    }

    @Synchronized
    fun disconnect() {
        try {
            commandClient?.disconnect()
        } catch (e: Exception) {}
        commandClient = null
        isConnected = false
        uplinkTotal = 0
        downlinkTotal = 0
        uplink = 0
        downlink = 0
        Handler(Looper.getMainLooper()).post {
            onStatusUpdated?.invoke(0, 0, 0, 0)
        }
    }

    private class ClientHandler : CommandClientHandler {
        override fun connected() {
            isConnected = true
            Log.i(TAG, "StatusCommandClient connected")
        }

        override fun disconnected(msg: String?) {
            isConnected = false
            commandClient = null
            Log.i(TAG, "StatusCommandClient disconnected: $msg")
        }

        override fun writeStatus(msg: StatusMessage?) {
            if (msg == null) return
            uplinkTotal = msg.uplinkTotal
            downlinkTotal = msg.downlinkTotal
            uplink = msg.uplink
            downlink = msg.downlink

            Handler(Looper.getMainLooper()).post {
                onStatusUpdated?.invoke(uplinkTotal, downlinkTotal, uplink, downlink)
            }
        }

        override fun clearLogs() {}
        override fun initializeClashMode(p0: StringIterator?, p1: String?) {}
        override fun setDefaultLogLevel(p0: Int) {}
        override fun updateClashMode(p0: String?) {}
        override fun writeConnectionEvents(p0: ConnectionEvents?) {}
        override fun writeGroups(p0: OutboundGroupIterator?) {}
        override fun writeLogs(p0: LogIterator?) {}
    }
}
