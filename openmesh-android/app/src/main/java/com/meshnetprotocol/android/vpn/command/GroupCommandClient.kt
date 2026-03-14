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
import java.util.Date

data class OutboundGroupItemModel(
    val tag: String,
    val type: String,
    val urlTestDelay: Int
) {
    val delayString: String get() = if (urlTestDelay > 0) "${urlTestDelay}ms" else "--"
}

data class OutboundGroupModel(
    val tag: String,
    val type: String,
    var selected: String,
    val selectable: Boolean,
    var isExpand: Boolean,
    val items: List<OutboundGroupItemModel>
)

object GroupCommandClient {
    private const val TAG = "GroupCommandClient"
    private var commandClient: libbox.CommandClient? = null

    @Volatile
    var isConnected = false
        private set

    @Volatile
    var groups: List<OutboundGroupModel> = emptyList()
        private set

    var onGroupsUpdated: ((List<OutboundGroupModel>) -> Unit)? = null

    @Synchronized
    fun connect() {
        if (isConnected || commandClient != null) return
        Thread {
            try {
                val options = CommandClientOptions()
                options.addCommand(Libbox.CommandGroup)
                options.statusInterval = 5_000_000_000L // 5 seconds
                
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
        groups = emptyList()
        Handler(Looper.getMainLooper()).post { onGroupsUpdated?.invoke(groups) }
    }

    fun urlTest(groupTag: String) {
        Thread {
            try {
                commandClient?.urlTest(groupTag) ?: run {
                    val client = Libbox.newStandaloneCommandClient()
                    client.urlTest(groupTag)
                    client.disconnect()
                }
            } catch (e: Exception) {
                Log.e(TAG, "urlTest error: ${e.message}")
            }
        }.start()
    }

    fun selectOutbound(groupTag: String, outboundTag: String) {
        Thread {
            try {
                commandClient?.selectOutbound(groupTag, outboundTag) ?: run {
                    val client = Libbox.newStandaloneCommandClient()
                    client.selectOutbound(groupTag, outboundTag)
                    client.disconnect()
                }
            } catch (e: Exception) {
                Log.e(TAG, "selectOutbound error: ${e.message}")
            }
        }.start()
    }

    private class ClientHandler : CommandClientHandler {
        override fun connected() {
            isConnected = true
            Log.i(TAG, "GroupCommandClient connected")
        }

        override fun disconnected(msg: String?) {
            isConnected = false
            commandClient = null
            Log.i(TAG, "GroupCommandClient disconnected: $msg")
        }

        override fun writeGroups(iterator: OutboundGroupIterator?) {
            if (iterator == null) return
            val list = mutableListOf<OutboundGroupModel>()
            while (iterator.hasNext()) {
                val group = iterator.next()
                val items = mutableListOf<OutboundGroupItemModel>()
                val itemIter = group.items
                if (itemIter != null) {
                    while (itemIter.hasNext()) {
                        val item = itemIter.next()
                        items.add(OutboundGroupItemModel(
                            tag = item.tag,
                            type = item.type,
                            urlTestDelay = item.urlTestDelay
                        ))
                    }
                }
                list.add(OutboundGroupModel(
                    tag = group.tag,
                    type = group.type,
                    selected = group.selected,
                    selectable = group.selectable,
                    isExpand = group.isExpand,
                    items = items
                ))
            }
            groups = list
            Handler(Looper.getMainLooper()).post { onGroupsUpdated?.invoke(list) }
        }

        override fun clearLogs() {}
        override fun initializeClashMode(p0: StringIterator?, p1: String?) {}
        override fun setDefaultLogLevel(p0: Int) {}
        override fun updateClashMode(p0: String?) {}
        override fun writeConnectionEvents(p0: ConnectionEvents?) {}
        override fun writeLogs(p0: LogIterator?) {}
        override fun writeStatus(p0: StatusMessage?) {}
    }
}
