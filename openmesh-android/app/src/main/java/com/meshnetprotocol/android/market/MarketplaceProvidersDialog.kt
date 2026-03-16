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
import androidx.appcompat.widget.PopupMenu
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import com.meshnetprotocol.android.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.*

/**
 * 供应商市场列表对话框 (Android Sync Module 2)
 */
class MarketplaceProvidersDialog(
    private val context: Context,
    private val onActionCompleted: (() -> Unit)? = null
) {
    private var dialog: Dialog? = null
    private var adapter: MarketAdapter? = null
    private var allProviders: List<TrafficProvider> = emptyList()
    
    private var currentRegion: String = "全部"
    private var currentSortMode: SortMode = SortMode.UPDATED_DESC
    
    enum class SortMode {
        UPDATED_DESC, PRICE_ASC, PRICE_DESC
    }

    fun show() {
        val view = LayoutInflater.from(context).inflate(R.layout.dialog_marketplace_list, null)
        dialog = Dialog(context, android.R.style.Theme_Black_NoTitleBar_Fullscreen).apply {
            setContentView(view)
            setCancelable(false)
            window?.setLayout(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }

        val recyclerView = view.findViewById<RecyclerView>(R.id.marketRecyclerView)
        val searchInput = view.findViewById<EditText>(R.id.searchInput)
        val clearSearch = view.findViewById<ImageButton>(R.id.clearSearchButton)
        val swipeRefresh = view.findViewById<SwipeRefreshLayout>(R.id.swipeRefreshLayout)
        val regionBtn = view.findViewById<View>(R.id.regionFilterButton)
        val sortBtn = view.findViewById<View>(R.id.sortButton)
        val emptyView = view.findViewById<View>(R.id.emptyView)

        recyclerView.layoutManager = LinearLayoutManager(context)
        adapter = MarketAdapter()
        recyclerView.adapter = adapter

        view.findViewById<View>(R.id.closeButton).setOnClickListener { dialog?.dismiss() }

        searchInput.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                clearSearch.visibility = if (s.isNullOrEmpty()) View.GONE else View.VISIBLE
                applyFilterAndSort(searchInput.text.toString(), emptyView)
            }
            override fun afterTextChanged(s: Editable?) {}
        })

        clearSearch.setOnClickListener { searchInput.setText("") }

        swipeRefresh.setOnRefreshListener {
            refreshData(swipeRefresh, searchInput.text.toString(), emptyView)
        }

        regionBtn.setOnClickListener { showRegionMenu(it, searchInput.text.toString(), emptyView) }
        sortBtn.setOnClickListener { showSortMenu(it, searchInput.text.toString(), emptyView) }

        loadInitialData(searchInput.text.toString(), emptyView)

        dialog?.show()
    }

    private fun loadInitialData(query: String, emptyView: View) {
        val cache = MarketCache(context)
        val manifest = cache.getCachedManifest()
        val recommended = cache.getCachedRecommended()
        allProviders = (manifest + recommended).distinctBy { it.id }
        
        updateStats()
        applyFilterAndSort(query, emptyView)
        
        // Background refresh
        MainScope().launch {
            try {
                val fresh = MarketRepository.fetchAllProviders()
                if (fresh.isNotEmpty()) {
                    allProviders = fresh
                    cache.saveCachedManifest(fresh)
                    updateStats()
                    applyFilterAndSort(query, emptyView)
                }
            } catch (e: Exception) {
                android.util.Log.e("MarketplaceDialog", "Silent refresh failed: ${e.message}")
            }
        }
    }

    private fun refreshData(swipeRefresh: SwipeRefreshLayout, query: String, emptyView: View) {
        MainScope().launch {
            try {
                val fresh = MarketRepository.fetchAllProviders()
                allProviders = fresh
                MarketCache(context).saveCachedManifest(fresh)
                updateStats()
                applyFilterAndSort(query, emptyView)
            } catch (e: Exception) {
                android.widget.Toast.makeText(context, "刷新失败: ${e.message}", android.widget.Toast.LENGTH_SHORT).show()
            } finally {
                swipeRefresh.isRefreshing = false
            }
        }
    }

    private fun updateStats() {
        val rootView = dialog?.window?.decorView ?: return
        val onlineCount = allProviders.size
        rootView.findViewById<TextView>(R.id.chipOnlineCount).text = "在线 $onlineCount"
    }

    private fun applyFilterAndSort(query: String, emptyView: View) {
        var filtered = allProviders.filter { provider ->
            val regionMatch = currentRegion == "全部" || provider.tags.any { tag ->
                tag.equals("region:$currentRegion", ignoreCase = true) || 
                tag.equals(currentRegion, ignoreCase = true)
            }
            val searchMatch = query.isEmpty() || 
                provider.name.contains(query, ignoreCase = true) ||
                provider.id.contains(query, ignoreCase = true) ||
                provider.author.contains(query, ignoreCase = true) ||
                provider.description.contains(query, ignoreCase = true) ||
                provider.tags.any { it.contains(query, ignoreCase = true) }
            regionMatch && searchMatch
        }

        filtered = when (currentSortMode) {
            SortMode.UPDATED_DESC -> filtered.sortedByDescending { it.updated_at }
            SortMode.PRICE_ASC -> filtered.sortedBy { it.price_per_gb_usd ?: Double.MAX_VALUE }
            SortMode.PRICE_DESC -> filtered.sortedByDescending { it.price_per_gb_usd ?: 0.0 }
        }

        adapter?.submitList(filtered)
        emptyView.visibility = if (filtered.isEmpty()) View.VISIBLE else View.GONE
        
        val rootView = dialog?.window?.decorView ?: return
        rootView.findViewById<TextView>(R.id.chipHitCount).text = "命中 ${filtered.size}"
    }

    private fun showRegionMenu(anchor: View, query: String, emptyView: View) {
        val regions = allProviders.flatMap { it.tags }
            .mapNotNull { tag ->
                val regionRegex = Regex("(?i)^region:([A-Z]{2})$")
                regionRegex.find(tag)?.groupValues?.get(1)?.uppercase()
                    ?: if (tag.length == 2 && tag.all { it.isUpperCase() }) tag else null
            }
            .distinct()
            .sorted()

        val popup = PopupMenu(context, anchor)
        popup.menu.add("全部")
        regions.forEach { popup.menu.add(it) }
        
        popup.setOnMenuItemClickListener { item ->
            currentRegion = item.title.toString()
            (anchor as? TextView)?.text = "地区: $currentRegion"
            applyFilterAndSort(query, emptyView)
            true
        }
        popup.show()
    }

    private fun showSortMenu(anchor: View, query: String, emptyView: View) {
        val popup = PopupMenu(context, anchor)
        popup.menu.add(0, SortMode.UPDATED_DESC.ordinal, 0, "按更新时间")
        popup.menu.add(0, SortMode.PRICE_ASC.ordinal, 1, "价格升序")
        popup.menu.add(0, SortMode.PRICE_DESC.ordinal, 2, "价格降序")
        
        popup.setOnMenuItemClickListener { item ->
            currentSortMode = SortMode.values()[item.itemId]
            (anchor as? TextView)?.text = when (currentSortMode) {
                SortMode.UPDATED_DESC -> "排序: 更新"
                SortMode.PRICE_ASC -> "排序: 价格↑"
                SortMode.PRICE_DESC -> "排序: 价格↓"
            }
            applyFilterAndSort(query, emptyView)
            true
        }
        popup.show()
    }

    inner class MarketAdapter : RecyclerView.Adapter<MarketAdapter.ViewHolder>() {
        private var list: List<TrafficProvider> = emptyList()

        fun submitList(newList: List<TrafficProvider>) {
            list = newList
            notifyDataSetChanged()
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
            val v = LayoutInflater.from(parent.context).inflate(R.layout.item_market_provider, parent, false)
            return ViewHolder(v)
        }

        override fun onBindViewHolder(holder: ViewHolder, position: Int) {
            val provider = list[position]
            holder.nameText.text = provider.name
            holder.authorText.text = "By ${provider.author}"
            holder.descText.text = provider.description
            
            val price = provider.price_per_gb_usd ?: 0.0
            holder.priceText.text = if (price > 0) String.format(Locale.US, "$%.2f/GB", price) else "Free"
            
            holder.dateText.text = provider.updated_at.take(10) // YYYY-MM-DD
            
            if (provider.tags.isNotEmpty()) {
                holder.tagsText.text = provider.tags.take(3).joinToString(" · ")
                holder.tagsText.visibility = View.VISIBLE
            } else {
                holder.tagsText.visibility = View.GONE
            }

            // Status Badge
            val installedHashes = ProviderPreferences.getInstalledPackageHashes(context)
            val updatesAvailable = ProviderPreferences.getUpdatesAvailable(context)
            val localHash = installedHashes[provider.id] ?: ""
            val isUpdatable = updatesAvailable[provider.id] == true

            when {
                isUpdatable -> {
                    holder.statusBadge.text = "Update"
                    holder.statusBadge.setBackgroundResource(R.drawable.bg_mesh_chip_amber)
                    holder.statusBadge.visibility = View.VISIBLE
                }
                localHash.isNotEmpty() -> {
                    holder.statusBadge.text = "Installed"
                    holder.statusBadge.setBackgroundResource(R.drawable.bg_mesh_chip_mint)
                    holder.statusBadge.visibility = View.VISIBLE
                }
                else -> {
                    holder.statusBadge.visibility = View.GONE
                }
            }

            holder.itemView.setOnClickListener {
                dialog?.dismiss()
                ProviderDetailDialog(context, provider) {
                    onActionCompleted?.invoke()
                }.show()
            }
        }

        override fun getItemCount() = list.size

        inner class ViewHolder(v: View) : RecyclerView.ViewHolder(v) {
            val nameText: TextView = v.findViewById(R.id.providerNameText)
            val statusBadge: TextView = v.findViewById(R.id.statusBadge)
            val authorText: TextView = v.findViewById(R.id.authorText)
            val priceText: TextView = v.findViewById(R.id.priceText)
            val descText: TextView = v.findViewById(R.id.descriptionText)
            val tagsText: TextView = v.findViewById(R.id.tagsSummaryText)
            val dateText: TextView = v.findViewById(R.id.updateDateText)
        }
    }
}
