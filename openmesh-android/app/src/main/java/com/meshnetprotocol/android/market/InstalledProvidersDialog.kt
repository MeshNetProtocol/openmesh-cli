package com.meshnetprotocol.android.market

import android.app.Dialog
import android.content.Context
import android.text.Editable
import android.text.TextWatcher
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.ImageButton
import android.widget.TextView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.meshnetprotocol.android.R
import com.meshnetprotocol.android.data.provider.ProviderStorageManager
import com.meshnetprotocol.android.vpn.VpnStateMachine
import com.meshnetprotocol.android.vpn.VpnServiceState
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch

/**
 * 已安装供应商列表对话框 (Android Sync)
 */
class InstalledProvidersDialog(
    private val context: Context,
    private val onActionCompleted: (() -> Unit)? = null
) {
    private var dialog: Dialog? = null
    private var adapter: InstalledAdapter? = null
    private var allItems: List<InstalledItem> = emptyList()

    data class InstalledItem(
        val providerID: String,
        val provider: TrafficProvider?,
        val localHash: String,
        val isUpdatable: Boolean
    )

    fun show() {
        val view = LayoutInflater.from(context).inflate(R.layout.dialog_installed_providers, null)
        dialog = Dialog(context, android.R.style.Theme_Black_NoTitleBar_Fullscreen).apply {
            setContentView(view)
            setCancelable(false)
            window?.setLayout(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }

        val recyclerView = view.findViewById<RecyclerView>(R.id.installedRecyclerView)
        val searchInput = view.findViewById<EditText>(R.id.searchInput)
        val clearSearch = view.findViewById<ImageButton>(R.id.clearSearchButton)
        val refreshButton = view.findViewById<ImageButton>(R.id.refreshButton)
        val emptyView = view.findViewById<View>(R.id.emptyView)
        val chipInstalled = view.findViewById<TextView>(R.id.chipInstalled)
        val chipUpdatable = view.findViewById<TextView>(R.id.chipUpdatable)
        val chipOffline = view.findViewById<TextView>(R.id.chipOffline)

        recyclerView.layoutManager = LinearLayoutManager(context)
        adapter = InstalledAdapter()
        recyclerView.adapter = adapter

        view.findViewById<View>(R.id.closeButton).setOnClickListener { dialog?.dismiss() }

        loadData()

        searchInput.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                clearSearch.visibility = if (s.isNullOrEmpty()) View.GONE else View.VISIBLE
                filter(s?.toString() ?: "", emptyView)
            }
            override fun afterTextChanged(s: Editable?) {}
        })

        clearSearch.setOnClickListener { searchInput.setText("") }

        refreshButton.setOnClickListener {
            MainScope().launch {
                UpdateChecker.checkInstalledProvidersUpdate(context)
                loadData()
            }
        }

        dialog?.show()
    }

    private fun loadData() {
        val storageManager = ProviderStorageManager(context)
        val installedIDs = storageManager.listInstalledProviders()
        val installedHashes = ProviderPreferences.getInstalledPackageHashes(context)
        val updates = ProviderPreferences.getUpdatesAvailable(context)
        val marketCache = MarketCache(context)
        val manifest = marketCache.getCachedManifest()
        val recommended = marketCache.getCachedRecommended()
        val allMarket = (manifest + recommended).distinctBy { it.id }

        allItems = installedIDs.map { id ->
            val provider = allMarket.find { it.id == id }
            val localHash = installedHashes[id] ?: ""
            val isUpdatable = updates[id] == true
            InstalledItem(id, provider, localHash, isUpdatable)
        }

        updateStats()
        adapter?.submitList(allItems)
    }

    private fun updateStats() {
        val updatableCount = allItems.count { it.isUpdatable }
        val offlineCount = allItems.count { it.provider == null }
        
        val rootView = dialog?.window?.decorView ?: return
        rootView.findViewById<TextView>(R.id.chipInstalled).text = "已安装 ${allItems.size}"
        rootView.findViewById<TextView>(R.id.chipUpdatable).text = "可更新 $updatableCount"
        rootView.findViewById<TextView>(R.id.chipOffline).text = "离线 $offlineCount"
    }

    private fun filter(query: String, emptyView: View) {
        val filtered = if (query.isEmpty()) {
            allItems
        } else {
            allItems.filter { item ->
                val nameMatch = item.provider?.name?.contains(query, ignoreCase = true) ?: false
                val idMatch = item.providerID.contains(query, ignoreCase = true)
                val hashMatch = item.localHash.contains(query, ignoreCase = true)
                val tagsMatch = item.provider?.tags?.any { it.contains(query, ignoreCase = true) } ?: false
                nameMatch || idMatch || hashMatch || tagsMatch
            }
        }
        adapter?.submitList(filtered)
        emptyView.visibility = if (filtered.isEmpty()) View.VISIBLE else View.GONE
    }

    inner class InstalledAdapter : RecyclerView.Adapter<InstalledAdapter.ViewHolder>() {
        private var list: List<InstalledItem> = emptyList()

        fun submitList(newList: List<InstalledItem>) {
            list = newList
            notifyDataSetChanged()
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
            val v = LayoutInflater.from(parent.context).inflate(R.layout.item_installed_provider, parent, false)
            return ViewHolder(v)
        }

        override fun onBindViewHolder(holder: ViewHolder, position: Int) {
            val item = list[position]
            holder.nameText.text = item.provider?.name ?: item.providerID
            holder.idText.text = item.providerID
            holder.localHashText.text = "Local: ${formatHash(item.localHash)}"
            
            if (item.provider != null && (item.provider.package_hash ?: "").isNotEmpty()) {
                holder.remoteHashText.text = "Remote: ${formatHash(item.provider.package_hash ?: "")}"
                holder.remoteHashText.visibility = View.VISIBLE
            } else {
                holder.remoteHashText.visibility = View.GONE
            }

            // Status Chip
            when {
                item.isUpdatable -> {
                    holder.statusChip.text = "UPDATE"
                    holder.statusChip.setBackgroundResource(R.drawable.bg_mesh_chip_amber)
                    holder.statusChip.visibility = View.VISIBLE
                    holder.updateButton.visibility = View.VISIBLE
                }
                item.provider == null -> {
                    holder.statusChip.text = "OFFLINE"
                    holder.statusChip.setBackgroundResource(R.drawable.bg_mesh_chip_red)
                    holder.statusChip.visibility = View.VISIBLE
                    holder.updateButton.visibility = View.GONE
                }
                else -> {
                    holder.statusChip.text = "INIT"
                    holder.statusChip.setBackgroundResource(R.drawable.bg_mesh_chip_blue)
                    holder.statusChip.visibility = View.VISIBLE
                    holder.updateButton.visibility = View.GONE
                }
            }

            holder.updateButton.setOnClickListener {
                if (item.provider != null) {
                    dialog?.dismiss()
                    val wizard = ProviderInstallWizardDialog(context, item.provider)
                    wizard.setOnCompletedListener { onActionCompleted?.invoke() }
                    wizard.show()
                }
            }

            holder.itemView.setOnClickListener {
                dialog?.dismiss()
                val targetProvider = item.provider ?: TrafficProvider(
                    id = item.providerID,
                    name = item.providerID,
                    description = "本地配置文件 (离线)",
                    config_url = "",
                    tags = emptyList(),
                    author = "Unknown",
                    updated_at = "",
                    provider_hash = null,
                    package_hash = null,
                    price_per_gb_usd = null,
                    detail_url = null
                )
                ProviderDetailDialog(context, targetProvider) {
                    onActionCompleted?.invoke()
                }.show()
            }
        }

        override fun getItemCount() = list.size

        inner class ViewHolder(v: View) : RecyclerView.ViewHolder(v) {
            val nameText = v.findViewById<TextView>(R.id.providerNameText)
            val idText = v.findViewById<TextView>(R.id.providerIdText)
            val localHashText = v.findViewById<TextView>(R.id.localHashText)
            val remoteHashText = v.findViewById<TextView>(R.id.remoteHashText)
            val statusChip = v.findViewById<TextView>(R.id.statusChip)
            val updateButton = v.findViewById<View>(R.id.updateButton)
        }

        private fun formatHash(hash: String): String {
            val value = hash.trim()
            if (value.isEmpty()) return "—"
            return if (value.length > 20) {
                value.take(10) + "…" + value.takeLast(8)
            } else {
                value
            }
        }
    }
}
