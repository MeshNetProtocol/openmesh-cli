package com.meshnetprotocol.android

import android.content.BroadcastReceiver
import android.content.res.ColorStateList
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.graphics.Typeface
import android.net.Uri
import android.net.VpnService
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.SpannableString
import android.text.style.RelativeSizeSpan
import android.text.style.StyleSpan
import android.util.Base64
import android.util.Log
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.view.isVisible
import com.google.android.material.bottomnavigation.BottomNavigationView
import com.google.android.material.bottomsheet.BottomSheetBehavior
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.android.material.button.MaterialButton
import com.google.android.material.textfield.TextInputEditText
import com.meshnetprotocol.android.data.profile.ProfileRepository
import com.meshnetprotocol.android.data.provider.ProviderStorageManager
import com.meshnetprotocol.android.vpn.OpenMeshVpnService
import com.meshnetprotocol.android.vpn.VpnServiceState
import com.meshnetprotocol.android.vpn.VpnStateMachine
import org.json.JSONObject
import com.meshnetprotocol.android.vpn.command.GroupCommandClient
import com.meshnetprotocol.android.vpn.command.OutboundGroupModel
import com.meshnetprotocol.android.vpn.command.OutboundGroupItemModel
import com.meshnetprotocol.android.vpn.command.StatusCommandClient
import android.widget.ImageView
import android.text.format.Formatter
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import android.widget.ProgressBar
import kotlinx.coroutines.*
import com.meshnetprotocol.android.market.MarketCache
import com.meshnetprotocol.android.market.MarketRepository
import com.meshnetprotocol.android.market.TrafficProvider
import java.net.HttpURLConnection
import java.net.URL

class MainActivity : AppCompatActivity() {
    private data class MockProvider(
        val id: String,
        val name: String,
        val description: String,
        val priceUsdPerGb: Double,
        val tags: List<String>,
        var packageHash: String,
        val recommended: Boolean,
    )

    private lateinit var bottomNavigation: BottomNavigationView
    private lateinit var tabDashboardRoot: View
    private lateinit var tabWalletRoot: View
    private lateinit var tabMarketRoot: View
    private lateinit var tabSettingsRoot: View
    private lateinit var loadingOverlay: View

    private lateinit var appVersionText: TextView
    private lateinit var statusDot: View
    private lateinit var vpnStateText: TextView
    private lateinit var vpnToggleButton: MaterialButton
    private lateinit var vpnActionHintText: TextView
    private lateinit var merchantCard: View
    private lateinit var trafficCard: View
    private lateinit var outboundCard: View
    private lateinit var providerSelectCard: View
    private lateinit var providerNameText: TextView
    private lateinit var uplinkValueText: TextView
    private lateinit var downlinkValueText: TextView
    private lateinit var currentOutboundText: TextView
    private lateinit var outboundDelayText: TextView

    private lateinit var selectOutboundButton: MaterialButton

    private lateinit var installFromPasteButton: MaterialButton
    private lateinit var installFromUrlButton: MaterialButton
    private lateinit var profileContentInput: TextInputEditText
    private lateinit var profileUrlInput: TextInputEditText
    private lateinit var providerIdInput: TextInputEditText
    private lateinit var installResultText: TextView
    private lateinit var openMarketplaceButton: View
    private lateinit var openInstalledButton: View
    private lateinit var openOfflineImportButton: View
    private lateinit var refreshMarketButton: MaterialButton
    private lateinit var recommendedCountChipText: TextView
    private lateinit var syncStateChipText: TextView
    private lateinit var marketCacheNoticeText: TextView
    private lateinit var marketLoadingText: TextView
    private lateinit var marketEmptyText: TextView
    private lateinit var marketLoadingProgress: ProgressBar
    private lateinit var marketErrorContainer: View
    private lateinit var marketErrorText: TextView
    private lateinit var marketRetryButton: MaterialButton
    private lateinit var recommendedListContainer: LinearLayout

    private lateinit var marketCache: MarketCache
    private var marketLoadJob: Job? = null

    private lateinit var settingsAppVersionText: TextView
    private lateinit var settingsVpnStatusText: TextView
    private lateinit var settingsVpnToggleButton: MaterialButton
    private lateinit var openDocsButton: MaterialButton
    private lateinit var openSourceButton: MaterialButton

    private val mockProviders = mutableListOf<MockProvider>()
    private val installedPackageHashByProvider = linkedMapOf<String, String>()
    private var marketLoading = false
    private var marketCacheNotice: String? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private var receiverRegistered = false

    private val updateStateReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: android.content.Context?, intent: android.content.Intent?) {
            // 收到更新状态变化时，刷新推荐列表 UI
            loadRecommendedProviders()
        }
    }

    private val vpnPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) { result ->
        if (result.resultCode == RESULT_OK) {
            OpenMeshVpnService.start(this)
        } else {
            loadingOverlay.isVisible = false
            Toast.makeText(this, R.string.vpn_permission_denied, Toast.LENGTH_SHORT).show()
        }
    }

    private val serviceReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                OpenMeshVpnService.ACTION_STATE_CHANGED -> handleStateEvent(intent)
                OpenMeshVpnService.ACTION_COMMAND_RESULT -> handleCommandResultEvent(intent)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        bindViews()
        marketCache = MarketCache(this)
        setupTabNavigation()
        setupActions()
        // initMockMarketData()

        restoreSavedInputs()
        renderVersion()
        renderProviderName()
        renderMarketHome()
        loadRecommendedProviders()
        renderState(VpnStateMachine.currentState())

        // Automated testing hook: auto-connect if requested via intent
        if (intent.getBooleanExtra("auto_connect", false)) {
            Log.i("MainActivity", "Auto-connect requested via intent")
            requestVpnPermissionAndStart()
        }
    }

    override fun onResume() {
        super.onResume()
        // Refresh provider name in case install happened in OfflineImportActivity
        renderProviderName()
    }

    override fun onStart() {
        super.onStart()
        if (!receiverRegistered) {
            ContextCompat.registerReceiver(
                this,
                serviceReceiver,
                IntentFilter().apply {
                    addAction(OpenMeshVpnService.ACTION_STATE_CHANGED)
                    addAction(OpenMeshVpnService.ACTION_COMMAND_RESULT)
                },
                ContextCompat.RECEIVER_NOT_EXPORTED,
            )
            // 监听供应商更新状态变化，刷新推荐列表
            ContextCompat.registerReceiver(
                this,
                updateStateReceiver,
                android.content.IntentFilter(
                    com.meshnetprotocol.android.market.UpdateChecker.ACTION_UPDATE_STATE_CHANGED
                ),
                ContextCompat.RECEIVER_NOT_EXPORTED
            )
            receiverRegistered = true
        }
        renderState(VpnStateMachine.currentState())
        GroupCommandClient.onGroupsUpdated = { groups ->
            renderOutboundGroupsHome(groups)
        }
        StatusCommandClient.onStatusUpdated = { uplinkTotal, downlinkTotal, uplink, downlink ->
            renderTrafficData(uplinkTotal, downlinkTotal)
        }
    }

    override fun onStop() {
        if (receiverRegistered) {
            try {
                unregisterReceiver(serviceReceiver)
                unregisterReceiver(updateStateReceiver)
            } catch (e: Exception) {
                // Ignore
            }
            receiverRegistered = false
        }
        GroupCommandClient.onGroupsUpdated = null
        StatusCommandClient.onStatusUpdated = null
        super.onStop()
    }

    private fun renderOutboundGroupsHome(groups: List<OutboundGroupModel>) {
        val proxyGroup = groups.firstOrNull { it.tag == "proxy" } ?: groups.firstOrNull()
        if (proxyGroup != null) {
            val selectedItem = proxyGroup.items.firstOrNull { it.tag == proxyGroup.selected }
            if (selectedItem != null) {
                currentOutboundText.text = selectedItem.tag
                outboundDelayText.text = selectedItem.delayString
                outboundDelayText.setTextColor(selectedItem.delayColorInt)
            } else {
                currentOutboundText.text = proxyGroup.selected.ifEmpty { "--" }
                outboundDelayText.text = "--"
                outboundDelayText.setTextColor(Color.parseColor("#94000000"))
            }
        } else {
            currentOutboundText.text = "--"
            outboundDelayText.text = "--"
            outboundDelayText.setTextColor(Color.parseColor("#94000000"))
        }
    }

    private fun bindViews() {
        bottomNavigation = findViewById(R.id.bottomNavigation)
        tabDashboardRoot = findViewById(R.id.tabDashboardRoot)
        tabWalletRoot = findViewById(R.id.tabWalletRoot)
        tabMarketRoot = findViewById(R.id.tabMarketRoot)
        tabSettingsRoot = findViewById(R.id.tabSettingsRoot)

        appVersionText = findViewById(R.id.appVersionText)
        statusDot = findViewById(R.id.statusDot)
        vpnStateText = findViewById(R.id.vpnStateText)
        vpnToggleButton = findViewById(R.id.vpnToggleButton)
        vpnActionHintText = findViewById(R.id.vpnActionHintText)
        merchantCard = findViewById(R.id.merchantCard)
        trafficCard = findViewById(R.id.trafficCard)
        outboundCard = findViewById(R.id.outboundCard)
        providerSelectCard = findViewById(R.id.providerSelectCard)
        providerNameText = findViewById(R.id.providerNameText)
        uplinkValueText = findViewById(R.id.uplinkValueText)
        downlinkValueText = findViewById(R.id.downlinkValueText)
        currentOutboundText = findViewById(R.id.currentOutboundText)
        outboundDelayText = findViewById(R.id.outboundDelayText)

        selectOutboundButton = findViewById(R.id.selectOutboundButton)

        installFromPasteButton = findViewById(R.id.installFromPasteButton)
        installFromUrlButton = findViewById(R.id.installFromUrlButton)
        profileContentInput = findViewById(R.id.profileContentInput)
        profileUrlInput = findViewById(R.id.profileUrlInput)
        providerIdInput = findViewById(R.id.providerIdInput)
        installResultText = findViewById(R.id.installResultText)
        openMarketplaceButton = findViewById(R.id.openMarketplaceButton)
        openInstalledButton = findViewById(R.id.openInstalledButton)
        openOfflineImportButton = findViewById(R.id.openOfflineImportButton)
        refreshMarketButton = findViewById(R.id.refreshMarketButton)
        recommendedCountChipText = findViewById(R.id.recommendedCountChipText)
        syncStateChipText = findViewById(R.id.syncStateChipText)
        marketCacheNoticeText = findViewById(R.id.marketCacheNoticeText)
        marketLoadingText = findViewById(R.id.marketLoadingText)
        marketEmptyText = findViewById(R.id.marketEmptyText)
        recommendedListContainer = findViewById(R.id.recommendedListContainer)
        marketLoadingProgress = findViewById(R.id.marketLoadingProgress)
        marketErrorContainer = findViewById(R.id.marketErrorContainer)
        marketErrorText = findViewById(R.id.marketErrorText)
        marketRetryButton = findViewById(R.id.marketRetryButton)

        settingsAppVersionText = findViewById(R.id.settingsAppVersionText)
        settingsVpnStatusText = findViewById(R.id.settingsVpnStatusText)
        settingsVpnToggleButton = findViewById(R.id.settingsVpnToggleButton)
        openDocsButton = findViewById(R.id.openDocsButton)
        openSourceButton = findViewById(R.id.openSourceButton)
        loadingOverlay = findViewById(R.id.loadingOverlay)
    }

    private fun setupTabNavigation() {
        bottomNavigation.setOnItemSelectedListener { item ->
            showTab(item.itemId)
            true
        }
        bottomNavigation.selectedItemId = R.id.nav_dashboard
    }

    private fun setupActions() {
        vpnToggleButton.setOnClickListener { toggleVpn() }
        settingsVpnToggleButton.setOnClickListener { toggleVpn() }



        selectOutboundButton.setOnClickListener {
            if (VpnStateMachine.currentState() != VpnServiceState.STARTED) {
                Toast.makeText(this, "Connect VPN First", Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            showOutboundGroupsDialog()
        }
        providerSelectCard.setOnClickListener {
            if (!hasInstalledProviderForSelection()) {
                showMarketplaceDialog()
            } else {
                showInstalledDialog()
            }
        }

        installFromPasteButton.setOnClickListener {
            val content = profileContentInput.text?.toString().orEmpty()
            installProfileFromContent(content, source = "paste")
        }

        installFromUrlButton.setOnClickListener {
            val url = profileUrlInput.text?.toString()?.trim().orEmpty()
            if (url.isEmpty()) {
                Toast.makeText(this, R.string.missing_profile_url_toast, Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            installFromUrl(url)
        }

        openMarketplaceButton.setOnClickListener { showMarketplaceDialog() }
        openInstalledButton.setOnClickListener { showInstalledDialog() }
        openOfflineImportButton.setOnClickListener { showOfflineImportDialog() }
        refreshMarketButton.setOnClickListener {
            loadRecommendedProviders(forceRefresh = true)
        }
        marketRetryButton.setOnClickListener {
            loadRecommendedProviders(forceRefresh = true)
        }

        openDocsButton.setOnClickListener {
            openUrl("https://meshnetprotocol.github.io/")
        }

        openSourceButton.setOnClickListener {
            openUrl("https://github.com/MeshNetProtocol/openmesh-cli")
        }
    }

    private fun showTab(itemId: Int) {
        tabDashboardRoot.isVisible = itemId == R.id.nav_dashboard
        tabWalletRoot.isVisible = itemId == R.id.nav_wallet
        tabMarketRoot.isVisible = itemId == R.id.nav_market
        tabSettingsRoot.isVisible = itemId == R.id.nav_settings
    }

    private fun toggleVpn() {
        val state = VpnStateMachine.currentState()
        Log.i("MainActivity", "toggleVpn: current state is $state")
        if (state == VpnServiceState.STOPPED) {
            showLoadingOverlay()
            requestVpnPermissionAndStart()
        } else if (state == VpnServiceState.STARTED) {
            showLoadingOverlay()
            OpenMeshVpnService.stop(this)
        } else {
            Toast.makeText(this, "Wait, VPN is $state", Toast.LENGTH_SHORT).show()
        }
    }

    private fun showLoadingOverlay() {
        loadingOverlay.isVisible = true
        // 10秒后强制取消遮罩，防止卡死
        mainHandler.postDelayed({ 
            if (loadingOverlay.isVisible) {
                loadingOverlay.isVisible = false
                Log.w("MainActivity", "Loading overlay timeout!")
            }
        }, 10000)
    }

    private fun handleStateEvent(intent: Intent) {
        val stateName = intent.getStringExtra(OpenMeshVpnService.EXTRA_STATE_NAME) ?: return
        val state = runCatching { VpnServiceState.valueOf(stateName) }.getOrNull() ?: return
        Log.d("MainActivity", "handleStateEvent state=$state")
        renderState(state)

        if (state == VpnServiceState.STARTED) {
            loadingOverlay.isVisible = false
            StatusCommandClient.connect()
        } else if (state == VpnServiceState.STOPPED) {
            loadingOverlay.isVisible = false
            StatusCommandClient.disconnect()
        }

        val errorMessage = intent.getStringExtra(OpenMeshVpnService.EXTRA_ERROR_MESSAGE)
        if (!errorMessage.isNullOrBlank()) {
            loadingOverlay.isVisible = false
            Toast.makeText(this, "VPN error: $errorMessage", Toast.LENGTH_LONG).show()
        } else if (state == VpnServiceState.STARTED) {
            Toast.makeText(this, R.string.vpn_connected_toast, Toast.LENGTH_SHORT).show()
        } else if (state == VpnServiceState.STOPPED) {
            // Toast.makeText(this, R.string.vpn_disconnected_toast, Toast.LENGTH_SHORT).show()
        }
    }

    private fun handleCommandResultEvent(intent: Intent) {
        val commandJson = intent.getStringExtra(OpenMeshVpnService.EXTRA_COMMAND_JSON).orEmpty()
        val resultJson = intent.getStringExtra(OpenMeshVpnService.EXTRA_COMMAND_RESULT_JSON).orEmpty()
        installResultText.text = getString(R.string.command_result_line, commandJson, resultJson)
    }

    private fun requestVpnPermissionAndStart() {
        val prepareIntent = VpnService.prepare(this)
        if (prepareIntent != null) {
            vpnPermissionLauncher.launch(prepareIntent)
            return
        }
        OpenMeshVpnService.start(this)
    }

    private fun sendCommand(json: JSONObject) {
        OpenMeshVpnService.sendCommand(this, json.toString())
    }

    private fun installFromUrl(urlValue: String) {
        installFromUrlButton.isEnabled = false
        Thread {
            val result = runCatching { downloadText(urlValue) }
            runOnUiThread {
                installFromUrlButton.isEnabled = true
                result.onSuccess { content ->
                    profileContentInput.setText(content)
                    installProfileFromContent(content, source = "url")
                }.onFailure {
                    val message = getString(
                        R.string.install_from_url_failed,
                        it.message ?: "unknown error",
                    )
                    installResultText.text = message
                    Toast.makeText(this, message, Toast.LENGTH_LONG).show()
                }
            }
        }.start()
    }

    private fun installProfileFromContent(
        content: String,
        source: String,
        providerIdOverride: String? = null,
        resultSink: (String) -> Unit = { installResultText.text = it },
    ) {
        val trimmed = content.trim()
        if (trimmed.isEmpty()) {
            Toast.makeText(this, R.string.missing_profile_content_toast, Toast.LENGTH_SHORT).show()
            return
        }

        val normalized = normalizeProfileContent(trimmed)
        val providerId = providerIdOverride ?: providerIdInput.text?.toString()?.trim().orEmpty()
        runCatching {
            JSONObject(normalized)

            val profilesDir = File(filesDir, "profiles")
            profilesDir.mkdirs()
            val profileFile = File(profilesDir, "selected_profile.json")
            profileFile.writeText(normalized, Charsets.UTF_8)

            val prefs = getSharedPreferences(ProfileRepository.PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit()
                .putLong(ProfileRepository.KEY_SELECTED_PROFILE_ID, 1L)
                .putString(ProfileRepository.KEY_SELECTED_PROFILE_NAME, "InstalledProfile")
                .putString(ProfileRepository.KEY_SELECTED_PROFILE_PATH, profileFile.absolutePath)
                .putString("selected_profile_source", source)
                .apply {
                    if (providerId.isEmpty()) {
                        remove(ProfileRepository.KEY_SELECTED_PROVIDER_ID)
                    } else {
                        putString(ProfileRepository.KEY_SELECTED_PROVIDER_ID, providerId)
                    }
                }
                .apply()

            profileFile.absolutePath
        }.onSuccess {
            val message = getString(R.string.saved_profile_toast)
            resultSink(message)
            installResultText.text = message
            Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
            persistCurrentInputs()
            renderProviderName()
        }.onFailure {
            val message = it.message ?: "install failed"
            resultSink(message)
            installResultText.text = message
            Toast.makeText(this, message, Toast.LENGTH_LONG).show()
        }
    }

    private fun normalizeProfileContent(raw: String): String {
        val trimmed = raw.trim()
        runCatching {
            JSONObject(trimmed)
            return trimmed
        }

        val decoded = runCatching { Base64.decode(trimmed, Base64.DEFAULT) }.getOrNull()
            ?: throw IllegalArgumentException("Invalid profile content: not JSON/base64")
        val decodedText = decoded.toString(Charsets.UTF_8).trim()
        JSONObject(decodedText)
        return decodedText
    }

    private fun renderTrafficData(uplinkTotal: Long, downlinkTotal: Long) {
        uplinkValueText.text = formatTrafficBytes(uplinkTotal)
        downlinkValueText.text = formatTrafficBytes(downlinkTotal)
    }

    private fun formatTrafficBytes(bytes: Long): String {
        return Formatter.formatFileSize(this, bytes)
    }

    private fun restoreSavedInputs() {
        val prefs = getSharedPreferences(ProfileRepository.PREFS_NAME, Context.MODE_PRIVATE)
        providerIdInput.setText(prefs.getString(ProfileRepository.KEY_SELECTED_PROVIDER_ID, ""))
        uplinkValueText.text = "--"
        downlinkValueText.text = "--"
        outboundDelayText.text = "--"
    }

    private fun persistCurrentInputs() {
        val prefs = getSharedPreferences(ProfileRepository.PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(ProfileRepository.KEY_SELECTED_PROVIDER_ID, providerIdInput.text?.toString()?.trim())
            .putString("last_group_tag", "proxy")
            .apply()
    }

    private fun renderProviderName() {
        val prefs = getSharedPreferences(ProfileRepository.PREFS_NAME, Context.MODE_PRIVATE)
        val name = prefs.getString(ProfileRepository.KEY_SELECTED_PROFILE_NAME, null)
        if (!name.isNullOrBlank()) {
            providerNameText.text = name
            return
        }
        // Fallback: if no selected name, try to auto-select from installed providers
        val storage = ProviderStorageManager(this)
        val installed = storage.listInstalledProviders()
        if (installed.size == 1) {
            val providerId = installed.first()
            val configFile = storage.getConfigFile(providerId)
            if (configFile.exists()) {
                // Auto-select the only installed provider
                prefs.edit()
                    .putLong(ProfileRepository.KEY_SELECTED_PROFILE_ID, System.currentTimeMillis())
                    .putString(ProfileRepository.KEY_SELECTED_PROFILE_NAME, providerId)
                    .putString(ProfileRepository.KEY_SELECTED_PROFILE_PATH, configFile.absolutePath)
                    .putString(ProfileRepository.KEY_SELECTED_PROVIDER_ID, providerId)
                    .apply()
                providerNameText.text = providerId
                return
            }
        }
        providerNameText.text = getString(R.string.provider_name_placeholder)
    }

    private fun hasInstalledProviderForSelection(): Boolean {
        val storage = ProviderStorageManager(this)
        if (storage.listInstalledProviders().isNotEmpty()) return true
        val prefs = getSharedPreferences(ProfileRepository.PREFS_NAME, Context.MODE_PRIVATE)
        val selectedPath = prefs.getString(ProfileRepository.KEY_SELECTED_PROFILE_PATH, null).orEmpty().trim()
        if (selectedPath.isEmpty()) return false
        return runCatching { File(selectedPath).exists() }.getOrDefault(false)
    }

    private fun renderVersion() {
        val versionName = runCatching {
            packageManager.getPackageInfo(packageName, 0).versionName ?: "1.0"
        }.getOrDefault("1.0")
        appVersionText.text = getString(R.string.app_version_line, versionName)
        settingsAppVersionText.text = versionName
    }

    private fun openUrl(value: String) {
        runCatching {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(value)))
        }.onFailure {
            Toast.makeText(this, it.message ?: "open url failed", Toast.LENGTH_SHORT).show()
        }
    }

    private fun downloadText(urlValue: String): String {
        val connection = URL(urlValue).openConnection() as HttpURLConnection
        connection.requestMethod = "GET"
        connection.connectTimeout = 12000
        connection.readTimeout = 20000
        connection.setRequestProperty("Accept", "application/json,text/plain,*/*")

        val code = connection.responseCode
        if (code !in 200..299) {
            throw IllegalStateException("HTTP $code")
        }

        connection.inputStream.use { input ->
            InputStreamReader(input, Charsets.UTF_8).use { reader ->
                BufferedReader(reader).use { buffered ->
                    return buffered.readText()
                }
            }
        }
    }

    private fun renderState(state: VpnServiceState) {
        val connected = state == VpnServiceState.STARTED
        val connecting = state == VpnServiceState.STARTING || state == VpnServiceState.STOPPING

        vpnStateText.text = when (state) {
            VpnServiceState.STOPPED -> getString(R.string.vpn_state_stopped)
            VpnServiceState.STARTING -> getString(R.string.vpn_state_starting)
            VpnServiceState.STARTED -> getString(R.string.vpn_state_started)
            VpnServiceState.STOPPING -> getString(R.string.vpn_state_stopping)
        }
        settingsVpnStatusText.text = vpnStateText.text

        vpnStateText.setTextColor(if (connected) Color.parseColor("#009E54") else Color.parseColor("#99000000"))
        settingsVpnStatusText.setTextColor(
            when {
                connected -> Color.parseColor("#009E54")
                state == VpnServiceState.STARTING -> Color.parseColor("#1C87F5")
                else -> Color.parseColor("#8A000000")
            }
        )

        statusDot.background = ContextCompat.getDrawable(
            this,
            if (connected) R.drawable.bg_status_dot_on else R.drawable.bg_status_dot_off,
        )

        // Update VPN button with two-line text, gradient background, and vector icon
        updateVpnButton(connected)
        vpnActionHintText.text = getString(if (connected) R.string.disconnect_hint else R.string.connect_hint)
        vpnActionHintText.isVisible = false

        settingsVpnToggleButton.text = getString(if (connected) R.string.disconnect else R.string.connect)

        val enableToggle = !connecting
        vpnToggleButton.isEnabled = enableToggle
        settingsVpnToggleButton.isEnabled = enableToggle

        // Keep parity with iOS Home tab: traffic and outbound cards are visible only when connected.
        trafficCard.isVisible = connected
        outboundCard.isVisible = connected
        merchantCard.alpha = if (connected) 1f else 0.98f
    }

    private fun updateVpnButton(connected: Boolean) {
        // Update background gradient
        vpnToggleButton.background = ContextCompat.getDrawable(
            this,
            if (connected) R.drawable.bg_vpn_button_on else R.drawable.bg_vpn_button_off,
        )
        
        // Update vector icon
        vpnToggleButton.icon = ContextCompat.getDrawable(
            this,
            if (connected) R.drawable.ic_vpn_stop else R.drawable.ic_vpn_play,
        )
        
        // Update two-line text with different font sizes using SpannableString
        val title = if (connected) 
            getString(R.string.disconnect_vpn_title) 
        else 
            getString(R.string.connect_vpn_title)
        
        val subtitle = if (connected)
            getString(R.string.disconnect_vpn_subtitle)
        else
            getString(R.string.connect_vpn_subtitle)
        
        // Create spannable string with different styles for title and subtitle
        val fullText = "$title\n$subtitle"
        val spannableString = SpannableString(fullText)
        
        // Title: 18sp, bold/heavy (already set in XML, but ensure it's bold)
        spannableString.setSpan(
            StyleSpan(Typeface.BOLD),
            0,
            title.length,
            android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        
        // Subtitle: 12sp (relative size 0.67 = 12/18), normal weight
        val subtitleStart = title.length + 1 // +1 for newline
        spannableString.setSpan(
            StyleSpan(Typeface.NORMAL),
            subtitleStart,
            fullText.length,
            android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        spannableString.setSpan(
            RelativeSizeSpan(0.67f), // 12sp / 18sp = 0.67
            subtitleStart,
            fullText.length,
            android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        
        vpnToggleButton.text = spannableString
    }

    private fun initMockMarketData() {
        if (mockProviders.isNotEmpty()) return
        mockProviders += MockProvider(
            id = "provider_alpha",
            name = "Provider Alpha",
            description = "Optimized provider for low-latency routing and stable global traffic.",
            priceUsdPerGb = 0.89,
            tags = listOf("Gaming", "Streaming", "LowLatency"),
            packageHash = "alpha_hash_v3",
            recommended = true,
        )
        mockProviders += MockProvider(
            id = "provider_beta",
            name = "Provider Beta",
            description = "Balanced provider with multi-region capacity and resilient routes.",
            priceUsdPerGb = 0.74,
            tags = listOf("Balanced", "Global"),
            packageHash = "beta_hash_v2",
            recommended = true,
        )
        mockProviders += MockProvider(
            id = "provider_gamma",
            name = "Provider Gamma",
            description = "Privacy-focused provider with strict egress policy presets.",
            priceUsdPerGb = 1.05,
            tags = listOf("Privacy", "Strict"),
            packageHash = "gamma_hash_v1",
            recommended = true,
        )
        mockProviders += MockProvider(
            id = "provider_delta",
            name = "Provider Delta",
            description = "Budget provider suitable for bulk traffic and batch jobs.",
            priceUsdPerGb = 0.49,
            tags = listOf("Budget", "Bulk"),
            packageHash = "delta_hash_v5",
            recommended = false,
        )
        installedPackageHashByProvider["provider_alpha"] = "alpha_hash_v2"
        installedPackageHashByProvider["provider_delta"] = "delta_hash_v5"
    }

    private fun renderMarketHome() {
        val recommended = mockProviders.filter { it.recommended }
        recommendedCountChipText.text = getString(R.string.recommended_count_chip, recommended.size)
        syncStateChipText.text = if (marketLoading) getString(R.string.market_syncing) else getString(R.string.market_ready)

        marketCacheNoticeText.isVisible = !marketCacheNotice.isNullOrBlank()
        marketCacheNoticeText.text = marketCacheNotice.orEmpty()
        marketLoadingText.isVisible = marketLoading
        marketLoadingText.text = if (marketLoading) getString(R.string.market_loading_recommended) else ""

        recommendedListContainer.removeAllViews()
        marketEmptyText.isVisible = recommended.isEmpty()
        if (recommended.isEmpty()) return

        val inflater = LayoutInflater.from(this)
        recommended.forEach { provider ->
            recommendedListContainer.addView(buildProviderRow(inflater, provider, isInInstalledDialog = false))
        }
    }

    private fun buildProviderRow(
        inflater: LayoutInflater,
        provider: MockProvider,
        isInInstalledDialog: Boolean,
    ): View {
        val row = inflater.inflate(R.layout.item_market_provider_row, recommendedListContainer, false)
        val rowRoot = row.findViewById<View>(R.id.providerRowRoot)
        val name = row.findViewById<TextView>(R.id.providerRowName)
        val price = row.findViewById<TextView>(R.id.providerRowPrice)
        val action = row.findViewById<MaterialButton>(R.id.providerRowAction)
        val desc = row.findViewById<TextView>(R.id.providerRowDesc)
        val hint = row.findViewById<TextView>(R.id.providerRowHint)
        val tagContainer = row.findViewById<LinearLayout>(R.id.providerRowTagContainer)

        val actionLabel = quickActionLabel(provider)
        name.text = provider.name
        price.text = String.format("%.2f USD/GB", provider.priceUsdPerGb)
        desc.text = provider.description
        hint.text = if (isInInstalledDialog) getString(R.string.provider_row_hint_installed) else getString(R.string.provider_row_hint)
        action.text = actionLabel
        action.isEnabled = actionLabel != getString(R.string.installed)
        styleProviderActionButton(action, actionLabel)

        action.setOnClickListener {
            when (actionLabel) {
                getString(R.string.uninstall) -> showUninstallWizard(provider)
                getString(R.string.installed) -> showProviderDetailDialog(provider)
                else -> showInstallWizard(provider, actionLabel)
            }
        }
        rowRoot.setOnClickListener { showProviderDetailDialog(provider) }

        tagContainer.removeAllViews()
        provider.tags.take(3).forEachIndexed { index, tag ->
            tagContainer.addView(createChipText(tag, index))
        }
        return row
    }

    private fun createChipText(tag: String, index: Int): TextView {
        val tv = TextView(this)
        tv.text = tag
        tv.textSize = 10f
        tv.setTextColor(
            when (index % 3) {
                0 -> Color.parseColor("#155FAF")
                1 -> Color.parseColor("#17687C")
                else -> Color.parseColor("#8B5A11")
            },
        )
        tv.background = ContextCompat.getDrawable(
            this,
            when (index % 3) {
                0 -> R.drawable.bg_chip_blue
                1 -> R.drawable.bg_chip_cyan
                else -> R.drawable.bg_chip_amber
            },
        )
        tv.setPadding(12, 4, 12, 4)
        val params = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        )
        if (index > 0) params.marginStart = 8
        tv.layoutParams = params
        return tv
    }

    private fun quickActionLabel(provider: MockProvider): String {
        val local = installedPackageHashByProvider[provider.id]
        if (local == null) return getString(R.string.install)
        if (local != provider.packageHash) return getString(R.string.update)
        return getString(R.string.installed)
    }

    private fun providerStatusText(provider: MockProvider): String {
        val local = installedPackageHashByProvider[provider.id]
        if (local == null) return getString(R.string.provider_status_not_installed)
        if (local != provider.packageHash) return getString(R.string.provider_status_update)
        return getString(R.string.provider_status_installed)
    }

    private fun styleProviderActionButton(button: MaterialButton, actionLabel: String) {
        when (actionLabel) {
            getString(R.string.install) -> {
                // 蓝色渐变实心按钮 (未安装状态)
                button.backgroundTintList = ColorStateList.valueOf(Color.parseColor("#2B78F5"))
                button.strokeWidth = 0
                button.setTextColor(Color.WHITE)
            }
            getString(R.string.update) -> {
                // 橙色渐变实心按钮 (更新状态)
                button.backgroundTintList = ColorStateList.valueOf(Color.parseColor("#F5A92F"))
                button.strokeWidth = 0
                button.setTextColor(Color.WHITE)
            }
            getString(R.string.reinstall) -> {
                // 青色渐变实心按钮 (重新安装状态)
                button.backgroundTintList = ColorStateList.valueOf(Color.parseColor("#27B8D7"))
                button.strokeWidth = 0
                button.setTextColor(Color.WHITE)
            }
            getString(R.string.installed) -> {
                // 浅绿色背景 + 绿色边框 + 绿色文字 (已安装状态)
                button.backgroundTintList = ColorStateList.valueOf(Color.parseColor("#E6F6EE"))
                button.strokeWidth = 1
                button.strokeColor = ColorStateList.valueOf(Color.parseColor("#4A2DAE73"))
                button.setTextColor(Color.parseColor("#2DAE73"))
            }
            else -> {
                // 默认白色背景 + 蓝色边框
                button.backgroundTintList = ColorStateList.valueOf(Color.WHITE)
                button.strokeWidth = 1
                button.strokeColor = ColorStateList.valueOf(Color.parseColor("#4D1C87F5"))
                button.setTextColor(Color.parseColor("#1C87F5"))
            }
        }
    }

    private fun styleDangerActionButton(button: MaterialButton) {
        button.backgroundTintList = ColorStateList.valueOf(Color.parseColor("#DE4A57"))
        button.strokeWidth = 0
        button.setTextColor(Color.WHITE)
    }

    private fun showMarketplaceDialog() {
        val view = LayoutInflater.from(this).inflate(R.layout.dialog_market_list, null, false)
        view.findViewById<TextView>(R.id.marketDialogTitle).text = getString(R.string.marketplace_dialog_title)
        view.findViewById<TextView>(R.id.marketDialogSubtitle).text = getString(R.string.marketplace_dialog_subtitle)
        view.findViewById<TextView>(R.id.marketDialogStats).apply {
            isVisible = true
            text = getString(R.string.market_dialog_stats, mockProviders.size)
        }
        val container = view.findViewById<LinearLayout>(R.id.marketDialogListContainer)
        val inflater = LayoutInflater.from(this)
        mockProviders.forEach { provider ->
            container.addView(buildProviderRow(inflater, provider, isInInstalledDialog = false))
        }
        val dialog = showMarketBottomSheet(view)
        view.findViewById<MaterialButton>(R.id.marketDialogCloseButton).setOnClickListener { dialog.dismiss() }
    }

    private fun showInstalledDialog() {
        val view = LayoutInflater.from(this).inflate(R.layout.dialog_market_list, null, false)
        view.findViewById<TextView>(R.id.marketDialogTitle).text = getString(R.string.installed_dialog_title)
        view.findViewById<TextView>(R.id.marketDialogSubtitle).text = getString(R.string.installed_dialog_subtitle)

        val storage = ProviderStorageManager(this)
        val realProviders = storage.listInstalledProviders()
        val prefs = getSharedPreferences(ProfileRepository.PREFS_NAME, Context.MODE_PRIVATE)
        val currentSelectedId = prefs.getString(ProfileRepository.KEY_SELECTED_PROVIDER_ID, null).orEmpty()

        view.findViewById<TextView>(R.id.marketDialogStats).apply {
            isVisible = true
            text = getString(R.string.market_dialog_stats, realProviders.size)
        }
        val container = view.findViewById<LinearLayout>(R.id.marketDialogListContainer)
        if (realProviders.isEmpty()) {
            val empty = TextView(this)
            empty.text = getString(R.string.installed_empty)
            empty.setTextColor(Color.parseColor("#7A000000"))
            empty.textSize = 12f
            container.addView(empty)
        } else {
            val dialog = showMarketBottomSheet(view)
            realProviders.forEach { providerId ->
                val configFile = storage.getConfigFile(providerId)
                val isSelected = (providerId == currentSelectedId)
                val row = buildRealProviderRow(providerId, configFile, isSelected) {
                    // On click: select this provider
                    prefs.edit()
                        .putLong(ProfileRepository.KEY_SELECTED_PROFILE_ID, System.currentTimeMillis())
                        .putString(ProfileRepository.KEY_SELECTED_PROFILE_NAME, providerId)
                        .putString(ProfileRepository.KEY_SELECTED_PROFILE_PATH, configFile.absolutePath)
                        .putString(ProfileRepository.KEY_SELECTED_PROVIDER_ID, providerId)
                        .apply()
                    renderProviderName()
                    dialog.dismiss()
                    Toast.makeText(this, "Selected: $providerId", Toast.LENGTH_SHORT).show()
                }
                container.addView(row)
            }
            view.findViewById<MaterialButton>(R.id.marketDialogCloseButton).setOnClickListener { dialog.dismiss() }
            return
        }
        val dialog = showMarketBottomSheet(view)
        view.findViewById<MaterialButton>(R.id.marketDialogCloseButton).setOnClickListener { dialog.dismiss() }
    }

    private fun buildRealProviderRow(
        providerId: String,
        configFile: File,
        isSelected: Boolean,
        onSelect: () -> Unit,
    ): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(24, 20, 24, 20)
            gravity = android.view.Gravity.CENTER_VERTICAL
            background = ContextCompat.getDrawable(this@MainActivity, R.drawable.bg_provider_select_card)
            val lp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            lp.bottomMargin = 12
            layoutParams = lp
        }

        val icon = FrameLayout(this).apply {
            val size = (36 * resources.displayMetrics.density).toInt()
            layoutParams = LinearLayout.LayoutParams(size, size)
            background = ContextCompat.getDrawable(this@MainActivity, R.drawable.bg_dashboard_provider_icon_circle)
        }
        val iconImg = android.widget.ImageView(this).apply {
            val imgSize = (18 * resources.displayMetrics.density).toInt()
            layoutParams = FrameLayout.LayoutParams(imgSize, imgSize, android.view.Gravity.CENTER)
            setImageResource(android.R.drawable.ic_menu_myplaces)
            setColorFilter(Color.parseColor("#1C87F5"))
        }
        icon.addView(iconImg)
        row.addView(icon)

        val textContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val lp = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            lp.marginStart = (12 * resources.displayMetrics.density).toInt()
            layoutParams = lp
        }
        val nameText = TextView(this).apply {
            text = providerId
            textSize = 15f
            setTextColor(Color.parseColor("#DE000000"))
            setTypeface(null, Typeface.BOLD)
        }
        val statusText = TextView(this).apply {
            text = if (isSelected) "✓ Selected" else if (configFile.exists()) "Installed" else "Missing config"
            textSize = 12f
            setTextColor(if (isSelected) Color.parseColor("#009E54") else Color.parseColor("#8A000000"))
        }
        textContainer.addView(nameText)
        textContainer.addView(statusText)
        row.addView(textContainer)

        val selectBtn = MaterialButton(this, null, com.google.android.material.R.attr.materialButtonOutlinedStyle).apply {
            text = if (isSelected) getString(R.string.installed) else "Select"
            isEnabled = !isSelected
            textSize = 12f
            isAllCaps = false
            if (isSelected) {
                backgroundTintList = ColorStateList.valueOf(Color.parseColor("#E6F6EE"))
                strokeWidth = 1
                strokeColor = ColorStateList.valueOf(Color.parseColor("#4A2DAE73"))
                setTextColor(Color.parseColor("#2DAE73"))
            } else {
                backgroundTintList = ColorStateList.valueOf(Color.parseColor("#2B78F5"))
                strokeWidth = 0
                setTextColor(Color.WHITE)
            }
        }
        selectBtn.setOnClickListener { onSelect() }
        row.addView(selectBtn)

        row.setOnClickListener { onSelect() }
        return row
    }

    private fun showProviderDetailDialog(provider: MockProvider) {
        val detailView = LayoutInflater.from(this).inflate(R.layout.dialog_market_provider_detail, null, false)
        detailView.findViewById<TextView>(R.id.detailProviderName).text = provider.name
        detailView.findViewById<TextView>(R.id.detailProviderPrice).text = String.format("%.2f USD/GB", provider.priceUsdPerGb)
        detailView.findViewById<TextView>(R.id.detailProviderDesc).text = provider.description
        detailView.findViewById<TextView>(R.id.detailStatusText).text = getString(
            R.string.provider_detail_status_line,
            providerStatusText(provider),
        )
        val tagContainer = detailView.findViewById<LinearLayout>(R.id.detailTagContainer)
        tagContainer.removeAllViews()
        provider.tags.forEachIndexed { idx, tag ->
            tagContainer.addView(createChipText(tag, idx))
        }
        val primaryButton = detailView.findViewById<MaterialButton>(R.id.detailPrimaryActionButton)
        val uninstallButton = detailView.findViewById<MaterialButton>(R.id.detailUninstallButton)
        val closeButton = detailView.findViewById<MaterialButton>(R.id.detailCloseButton)

        val actionLabel = when (quickActionLabel(provider)) {
            getString(R.string.installed) -> getString(R.string.reinstall)
            else -> quickActionLabel(provider)
        }
        primaryButton.text = actionLabel
        styleProviderActionButton(primaryButton, actionLabel)

        val installed = installedPackageHashByProvider.containsKey(provider.id)
        uninstallButton.isVisible = installed
        if (installed) {
            styleDangerActionButton(uninstallButton)
        }
        val dialog = showMarketBottomSheet(detailView)
        closeButton.setOnClickListener { dialog.dismiss() }
        primaryButton.setOnClickListener {
            dialog.dismiss()
            showInstallWizard(provider, actionLabel)
        }
        uninstallButton.setOnClickListener {
            dialog.dismiss()
            showUninstallWizard(provider)
        }
    }

    private fun showInstallWizard(provider: MockProvider, actionLabel: String) {
        val view = LayoutInflater.from(this).inflate(R.layout.dialog_market_confirm, null, false)
        view.findViewById<TextView>(R.id.confirmTitleText).text =
            getString(R.string.install_wizard_title, actionLabel, provider.name)
        view.findViewById<TextView>(R.id.confirmMessageText).text =
            getString(R.string.install_wizard_message, provider.name, provider.packageHash)
        val secondary = view.findViewById<MaterialButton>(R.id.confirmSecondaryButton)
        val primary = view.findViewById<MaterialButton>(R.id.confirmPrimaryButton)
        primary.text = actionLabel
        styleProviderActionButton(primary, actionLabel)
        val dialog = showMarketBottomSheet(view)
        secondary.setOnClickListener { dialog.dismiss() }
        primary.setOnClickListener {
            dialog.dismiss()
                installedPackageHashByProvider[provider.id] = provider.packageHash
                val message = getString(R.string.install_wizard_success, provider.name)
                installResultText.text = message
                Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
                renderMarketHome()
        }
    }

    private fun showUninstallWizard(provider: MockProvider) {
        val view = LayoutInflater.from(this).inflate(R.layout.dialog_market_confirm, null, false)
        view.findViewById<TextView>(R.id.confirmTitleText).text =
            getString(R.string.uninstall_wizard_title, provider.name)
        view.findViewById<TextView>(R.id.confirmMessageText).text =
            getString(R.string.uninstall_wizard_message)
        val secondary = view.findViewById<MaterialButton>(R.id.confirmSecondaryButton)
        val primary = view.findViewById<MaterialButton>(R.id.confirmPrimaryButton)
        primary.text = getString(R.string.uninstall)
        styleDangerActionButton(primary)
        val dialog = showMarketBottomSheet(view)
        secondary.setOnClickListener { dialog.dismiss() }
        primary.setOnClickListener {
            dialog.dismiss()
                installedPackageHashByProvider.remove(provider.id)
                val message = getString(R.string.uninstall_wizard_success, provider.name)
                installResultText.text = message
                Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
                renderMarketHome()
        }
    }

    private fun showOfflineImportDialog() {
        try {
            // 启动新的 OfflineImportActivity
            val intent = android.content.Intent(this, OfflineImportActivity::class.java)
            startActivity(intent)
        } catch (e: Exception) {
            android.util.Log.e("OpenMeshAndroid", "启动 OfflineImportActivity 失败：${e.message}", e)
            Toast.makeText(this, "打开失败：${e.message}", Toast.LENGTH_LONG).show()
            e.printStackTrace()
        }
    }

    private fun showMarketBottomSheet(contentView: View): BottomSheetDialog {
        val dialog = BottomSheetDialog(this)
        dialog.setContentView(contentView)
        dialog.setOnShowListener {
            val sheet = dialog.findViewById<FrameLayout>(com.google.android.material.R.id.design_bottom_sheet)
            if (sheet != null) {
                sheet.layoutParams = sheet.layoutParams.apply {
                    height = ViewGroup.LayoutParams.MATCH_PARENT
                }
            }
            dialog.behavior.skipCollapsed = true
            dialog.behavior.state = BottomSheetBehavior.STATE_EXPANDED
        }
        dialog.show()
        return dialog
    }

    private fun showOutboundGroupsDialog() {
        if (VpnStateMachine.currentState() != VpnServiceState.STARTED) return
        
        val view = LayoutInflater.from(this).inflate(R.layout.bottom_sheet_outbound_picker, null, false)

        val titleText = view.findViewById<TextView>(R.id.pickerTitleText)
        val speedTestButton = view.findViewById<com.google.android.material.button.MaterialButton>(R.id.pickerSpeedTestButton)
        val summaryText = view.findViewById<TextView>(R.id.pickerSummaryText)
        val sortDefaultBtn = view.findViewById<com.google.android.material.button.MaterialButton>(R.id.sortDefaultBtn)
        val sortLatencyBtn = view.findViewById<com.google.android.material.button.MaterialButton>(R.id.sortLatencyBtn)
        val sortNameBtn = view.findViewById<com.google.android.material.button.MaterialButton>(R.id.sortNameBtn)
        val nodeListContainer = view.findViewById<LinearLayout>(R.id.pickerNodeListContainer)
        val loadingOverlay = view.findViewById<FrameLayout>(R.id.pickerLoadingOverlay)
        val loadingText = view.findViewById<TextView>(R.id.pickerLoadingText)

        // 排序模式：0=默认，1=延迟，2=名称
        var currentSortMode = 0

        fun updateSortButtons() {
            listOf(sortDefaultBtn to 0, sortLatencyBtn to 1, sortNameBtn to 2).forEach { (btn, mode) ->
                val isSelected = (currentSortMode == mode)
                btn.backgroundTintList = android.content.res.ColorStateList.valueOf(
                    if (isSelected) android.graphics.Color.parseColor("#E8F0FE")
                    else android.graphics.Color.TRANSPARENT
                )
                btn.setTextColor(
                    if (isSelected) android.graphics.Color.parseColor("#1C87F5")
                    else android.graphics.Color.parseColor("#8F000000")
                )
            }
        }
        updateSortButtons()

        fun getCurrentGroup(): com.meshnetprotocol.android.vpn.command.OutboundGroupModel? {
            val groups = GroupCommandClient.groups
            return groups.firstOrNull { it.tag == "proxy" }
                ?: groups.firstOrNull { it.type.equals("selector", ignoreCase = true) }
                ?: groups.firstOrNull()
        }

        fun sortedItems(group: com.meshnetprotocol.android.vpn.command.OutboundGroupModel): 
                List<com.meshnetprotocol.android.vpn.command.OutboundGroupItemModel> {
            return when (currentSortMode) {
                1 -> group.items.sortedWith(compareBy { 
                    if (it.urlTestDelay <= 0) Int.MAX_VALUE else it.urlTestDelay 
                })
                2 -> group.items.sortedBy { it.tag }
                else -> group.items
            }
        }

        fun renderNodeList() {
            val group = getCurrentGroup()
            nodeListContainer.removeAllViews()

            if (group != null) {
                summaryText.text = "已连接：${group.selected}  |  共 ${group.items.size} 个节点 · ${group.type}"
            } else {
                summaryText.text = "暂无节点"
                return
            }

            val items = sortedItems(group)
            val inflater = LayoutInflater.from(this)
            items.forEach { item ->
                val itemView = inflater.inflate(R.layout.item_outbound_node, nodeListContainer, false)

                itemView.findViewById<TextView>(R.id.itemTagText).apply {
                    text = item.tag
                    setTextColor(android.graphics.Color.parseColor("#DE000000"))
                }

                itemView.findViewById<TextView>(R.id.itemTypeText).apply {
                    text = item.type.ifEmpty { "outbound" }
                }

                itemView.findViewById<View>(R.id.itemDelayDot).apply {
                    val dotColor = item.delayColorInt
                    background = android.graphics.drawable.GradientDrawable().apply {
                        shape = android.graphics.drawable.GradientDrawable.OVAL
                        setColor(dotColor)
                    }
                }

                itemView.findViewById<TextView>(R.id.itemDelayText).apply {
                    text = item.delayString
                    setTextColor(item.delayColorInt)
                }

                val isSelected = (group.selected == item.tag)
                itemView.findViewById<TextView>(R.id.itemConnectedBadge).apply {
                    visibility = if (isSelected) View.VISIBLE else View.GONE
                }

                itemView.findViewById<android.widget.ImageView>(R.id.itemCheckIcon).apply {
                    visibility = if (isSelected) View.VISIBLE else View.GONE
                }

                itemView.setOnClickListener {
                    if (!isSelected && group.selectable) {
                        GroupCommandClient.selectOutbound(group.tag, item.tag)
                    }
                }

                nodeListContainer.addView(itemView)
            }
        }
        renderNodeList()

        sortDefaultBtn.setOnClickListener { currentSortMode = 0; updateSortButtons(); renderNodeList() }
        sortLatencyBtn.setOnClickListener { currentSortMode = 1; updateSortButtons(); renderNodeList() }
        sortNameBtn.setOnClickListener  { currentSortMode = 2; updateSortButtons(); renderNodeList() }

        var isUrlTesting = false
        speedTestButton.setOnClickListener {
            if (isUrlTesting) return@setOnClickListener
            val group = getCurrentGroup() ?: return@setOnClickListener
            isUrlTesting = true
            loadingText.text = "测速中，请稍候…"
            loadingOverlay.visibility = View.VISIBLE
            speedTestButton.isEnabled = false
            GroupCommandClient.urlTest(group.tag)
            mainHandler.postDelayed({
                isUrlTesting = false
                loadingOverlay.visibility = View.GONE
                speedTestButton.isEnabled = true
                renderNodeList()
            }, 3000)
        }

        val dialog = showMarketBottomSheet(view)

        GroupCommandClient.onGroupsUpdated = { groups ->
            renderOutboundGroupsHome(groups)
            if (dialog.isShowing) {
                renderNodeList()
            }
        }

        dialog.setOnDismissListener {
            GroupCommandClient.onGroupsUpdated = { groups -> renderOutboundGroupsHome(groups) }
        }
    }


    private fun loadRecommendedProviders(forceRefresh: Boolean = false) {
        // 取消上一次未完成的加载（防止重复请求）
        marketLoadJob?.cancel()
        marketLoadJob = MainScope().launch {
            // 先读缓存（即使 forceRefresh=true，也先展示缓存，再刷新）
            if (!forceRefresh) {
                val cached = marketCache.getCachedRecommended()
                if (cached.isNotEmpty()) {
                    renderRecommendedProviders(cached)
                    marketCacheNoticeText.visibility = View.VISIBLE
                    marketCacheNoticeText.text = "显示本地缓存，正在刷新…"
                    syncStateChipText.text = getString(R.string.market_syncing)
                }
            }

            // 显示加载状态
            marketLoadingProgress.visibility = View.VISIBLE
            marketLoadingText.visibility = View.VISIBLE
            marketErrorContainer.visibility = View.GONE
            syncStateChipText.text = getString(R.string.market_syncing)

            try {
                val providers = withContext(Dispatchers.IO) {
                    MarketRepository.fetchRecommendedProviders()
                }
                // 保存缓存
                marketCache.saveCachedRecommended(providers)
                // 渲染数据
                renderRecommendedProviders(providers)

                // 异步触发更新检查（不阻塞 UI）
                MainScope().launch {
                    com.meshnetprotocol.android.market.UpdateChecker
                        .checkInstalledProvidersUpdate(this@MainActivity)
                }

                // 更新状态
                marketLoadingProgress.visibility = View.GONE
                marketLoadingText.visibility = View.GONE
                marketCacheNoticeText.visibility = View.GONE
                marketErrorContainer.visibility = View.GONE
                syncStateChipText.text = getString(R.string.market_ready)
                // 更新 chip 数量
                recommendedCountChipText.text = getString(R.string.recommended_count_chip, providers.size)
                // 保存 mock 数据（不再使用）
                marketLoading = false
            } catch (e: Exception) {
                if (e is CancellationException) return@launch
                marketLoadingProgress.visibility = View.GONE
                marketLoadingText.visibility = View.GONE
                val hasCached = recommendedListContainer.childCount > 0
                if (!hasCached) {
                    // 完全无数据时才显示错误
                    marketErrorContainer.visibility = View.VISIBLE
                    marketErrorText.text = "加载推荐供应商失败：${e.message}"
                } else {
                    // 已有缓存数据时，显示轻提示
                    marketCacheNoticeText.visibility = View.VISIBLE
                    marketCacheNoticeText.text = "网络请求失败，当前显示本地缓存数据。"
                }
                syncStateChipText.text = getString(R.string.market_ready)
                android.util.Log.e("MainActivity", "loadRecommendedProviders failed: ${e.message}")
            }
        }
    }

    private fun renderRecommendedProviders(providers: List<TrafficProvider>) {
        recommendedListContainer.removeAllViews()
        marketEmptyText.isVisible = providers.isEmpty()
        if (providers.isEmpty()) return

        val inflater = LayoutInflater.from(this)
        
        // 使用 hash-based 精确判断（对应 iOS ProviderRecommendedRow 的 localHash/updateAvailable）
        val installedHashes = com.meshnetprotocol.android.market.ProviderPreferences
            .getInstalledPackageHashes(this)
        val updatesAvailable = com.meshnetprotocol.android.market.ProviderPreferences
            .getUpdatesAvailable(this)

        // 兼容旧版：也检查 ProviderStorageManager（没有 hash 记录但目录存在的情况）
        val legacyInstalledProviders = ProviderStorageManager(this).listInstalledProviders()

        providers.forEach { provider ->
            val row = inflater.inflate(R.layout.item_provider_recommended_row, recommendedListContainer, false)

            // 供应商名字
            row.findViewById<TextView>(R.id.providerRowName).text = provider.name

            // 价格 chip（有价格才显示）
            val priceChip = row.findViewById<TextView>(R.id.providerRowPriceChip)
            if (provider.price_per_gb_usd != null) {
                priceChip.text = String.format("%.2f USD/GB", provider.price_per_gb_usd)
                priceChip.visibility = View.VISIBLE
            } else {
                priceChip.visibility = View.GONE
            }

            // 描述
            row.findViewById<TextView>(R.id.providerRowDesc).text = provider.description

            // 标签（最多 3 个，格式："标签: A · B · C"）
            val tagsView = row.findViewById<TextView>(R.id.providerRowTags)
            if (provider.tags.isNotEmpty()) {
                val tagSummary = "标签: " + provider.tags.take(3).joinToString(" · ")
                tagsView.text = tagSummary
                tagsView.visibility = View.VISIBLE
            } else {
                tagsView.visibility = View.GONE
            }

            // 操作按钮状态
            val actionBtn = row.findViewById<MaterialButton>(R.id.providerRowActionButton)
            
            val localHash = installedHashes[provider.id] ?: ""
            val isInstalled = localHash.isNotEmpty() || legacyInstalledProviders.contains(provider.id)
            val updateAvailable = updatesAvailable[provider.id] == true

            when {
                isInstalled && updateAvailable -> {
                    // "更新"按钮 - 橙色
                    actionBtn.text = "更新"
                    actionBtn.backgroundTintList = android.content.res.ColorStateList.valueOf(
                        android.graphics.Color.parseColor("#F5A92F")
                    )
                    actionBtn.setTextColor(android.graphics.Color.WHITE)
                    actionBtn.strokeWidth = 0
                    actionBtn.isEnabled = true
                    actionBtn.setOnClickListener {
                        // 点击"更新"→ 直接打开安装向导（复用 ProviderInstallWizardDialog）
                        val wizard = com.meshnetprotocol.android.market.ProviderInstallWizardDialog(
                            context = this,
                            provider = provider
                        )
                        wizard.setOnCompletedListener {
                            renderProviderName()
                            loadRecommendedProviders()
                        }
                        wizard.show()
                    }
                }
                isInstalled -> {
                    // "已安装"按钮 - 绿色禁用
                    actionBtn.text = getString(R.string.installed)
                    actionBtn.backgroundTintList = android.content.res.ColorStateList.valueOf(
                        android.graphics.Color.parseColor("#E6F6EE")
                    )
                    actionBtn.setTextColor(android.graphics.Color.parseColor("#009E54"))
                    actionBtn.strokeWidth = 1
                    actionBtn.strokeColor = android.content.res.ColorStateList.valueOf(
                        android.graphics.Color.parseColor("#4A009E54")
                    )
                    actionBtn.isEnabled = false
                }
                else -> {
                    // "安装"按钮 - 蓝色
                    actionBtn.text = getString(R.string.install)
                    actionBtn.backgroundTintList = android.content.res.ColorStateList.valueOf(
                        android.graphics.Color.parseColor("#1C87F5")
                    )
                    actionBtn.setTextColor(android.graphics.Color.WHITE)
                    actionBtn.strokeWidth = 0
                    actionBtn.isEnabled = true
                    actionBtn.setOnClickListener {
                        val wizard = com.meshnetprotocol.android.market.ProviderInstallWizardDialog(
                            context = this,
                            provider = provider
                        )
                        wizard.setOnCompletedListener {
                            renderProviderName()
                            loadRecommendedProviders()
                        }
                        wizard.show()
                    }
                }
            }

            // 整行点击：打开详情对话框
            row.setOnClickListener {
                com.meshnetprotocol.android.market.ProviderDetailDialog(
                    context = this,
                    provider = provider,
                    onActionCompleted = {
                        renderProviderName()
                        loadRecommendedProviders()
                    }
                ).show()
            }

            recommendedListContainer.addView(row)
        }
    }

    private fun triggerMarketRefresh() {
        if (marketLoading) return
        marketLoading = true
        renderMarketHome()
        mainHandler.postDelayed({
            marketLoading = false
            renderMarketHome()
        }, 850)
    }
}

