package com.meshnetprotocol.android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.net.Uri
import android.net.VpnService
import android.os.Bundle
import android.util.Base64
import android.view.View
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.view.isVisible
import com.google.android.material.bottomnavigation.BottomNavigationView
import com.google.android.material.button.MaterialButton
import com.google.android.material.textfield.TextInputEditText
import com.meshnetprotocol.android.data.profile.ProfileRepository
import com.meshnetprotocol.android.vpn.OpenMeshVpnService
import com.meshnetprotocol.android.vpn.VpnServiceState
import com.meshnetprotocol.android.vpn.VpnStateMachine
import org.json.JSONObject
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL

class MainActivity : AppCompatActivity() {
    private lateinit var bottomNavigation: BottomNavigationView
    private lateinit var tabDashboardRoot: View
    private lateinit var tabWalletRoot: View
    private lateinit var tabMarketRoot: View
    private lateinit var tabSettingsRoot: View

    private lateinit var appVersionText: TextView
    private lateinit var statusDot: View
    private lateinit var vpnStateText: TextView
    private lateinit var vpnToggleButton: MaterialButton
    private lateinit var vpnActionHintText: TextView
    private lateinit var providerNameText: TextView
    private lateinit var uplinkValueText: TextView
    private lateinit var downlinkValueText: TextView
    private lateinit var currentOutboundText: TextView
    private lateinit var outboundDelayText: TextView
    private lateinit var urltestButton: MaterialButton
    private lateinit var selectOutboundButton: MaterialButton

    private lateinit var installFromPasteButton: MaterialButton
    private lateinit var installFromUrlButton: MaterialButton
    private lateinit var profileContentInput: TextInputEditText
    private lateinit var profileUrlInput: TextInputEditText
    private lateinit var providerIdInput: TextInputEditText
    private lateinit var installResultText: TextView
    private lateinit var openMarketplaceButton: MaterialButton
    private lateinit var openInstalledButton: MaterialButton

    private lateinit var settingsAppVersionText: TextView
    private lateinit var settingsVpnStatusText: TextView
    private lateinit var settingsVpnToggleButton: MaterialButton
    private lateinit var openDocsButton: MaterialButton
    private lateinit var openSourceButton: MaterialButton

    private var receiverRegistered = false

    private val vpnPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) { result ->
        if (result.resultCode == RESULT_OK) {
            OpenMeshVpnService.start(this)
        } else {
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
        setupTabNavigation()
        setupActions()

        restoreSavedInputs()
        renderVersion()
        renderProviderName()
        renderState(VpnStateMachine.currentState())
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
            receiverRegistered = true
        }
        renderState(VpnStateMachine.currentState())
    }

    override fun onStop() {
        if (receiverRegistered) {
            unregisterReceiver(serviceReceiver)
            receiverRegistered = false
        }
        super.onStop()
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
        providerNameText = findViewById(R.id.providerNameText)
        uplinkValueText = findViewById(R.id.uplinkValueText)
        downlinkValueText = findViewById(R.id.downlinkValueText)
        currentOutboundText = findViewById(R.id.currentOutboundText)
        outboundDelayText = findViewById(R.id.outboundDelayText)
        urltestButton = findViewById(R.id.urltestButton)
        selectOutboundButton = findViewById(R.id.selectOutboundButton)

        installFromPasteButton = findViewById(R.id.installFromPasteButton)
        installFromUrlButton = findViewById(R.id.installFromUrlButton)
        profileContentInput = findViewById(R.id.profileContentInput)
        profileUrlInput = findViewById(R.id.profileUrlInput)
        providerIdInput = findViewById(R.id.providerIdInput)
        installResultText = findViewById(R.id.installResultText)
        openMarketplaceButton = findViewById(R.id.openMarketplaceButton)
        openInstalledButton = findViewById(R.id.openInstalledButton)

        settingsAppVersionText = findViewById(R.id.settingsAppVersionText)
        settingsVpnStatusText = findViewById(R.id.settingsVpnStatusText)
        settingsVpnToggleButton = findViewById(R.id.settingsVpnToggleButton)
        openDocsButton = findViewById(R.id.openDocsButton)
        openSourceButton = findViewById(R.id.openSourceButton)
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

        urltestButton.setOnClickListener {
            val group = getSharedPreferences(ProfileRepository.PREFS_NAME, Context.MODE_PRIVATE)
                .getString("last_group_tag", "proxy")
                .orEmpty()
            sendCommand(JSONObject().put("action", "urltest").put("group", group))
            Toast.makeText(this, R.string.urltest_triggered, Toast.LENGTH_SHORT).show()
        }

        selectOutboundButton.setOnClickListener {
            Toast.makeText(this, R.string.switch_outbound_phase2_hint, Toast.LENGTH_SHORT).show()
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

        openMarketplaceButton.setOnClickListener {
            Toast.makeText(this, R.string.marketplace_phase2_hint, Toast.LENGTH_SHORT).show()
        }

        openInstalledButton.setOnClickListener {
            Toast.makeText(this, R.string.installed_phase2_hint, Toast.LENGTH_SHORT).show()
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
        if (state == VpnServiceState.STOPPED) {
            requestVpnPermissionAndStart()
        } else {
            OpenMeshVpnService.stop(this)
        }
    }

    private fun handleStateEvent(intent: Intent) {
        val stateName = intent.getStringExtra(OpenMeshVpnService.EXTRA_STATE_NAME) ?: return
        val state = runCatching { VpnServiceState.valueOf(stateName) }.getOrNull() ?: return
        renderState(state)

        val errorMessage = intent.getStringExtra(OpenMeshVpnService.EXTRA_ERROR_MESSAGE)
        if (!errorMessage.isNullOrBlank()) {
            Toast.makeText(this, errorMessage, Toast.LENGTH_LONG).show()
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

    private fun installProfileFromContent(content: String, source: String) {
        val trimmed = content.trim()
        if (trimmed.isEmpty()) {
            Toast.makeText(this, R.string.missing_profile_content_toast, Toast.LENGTH_SHORT).show()
            return
        }

        val normalized = normalizeProfileContent(trimmed)
        val providerId = providerIdInput.text?.toString()?.trim().orEmpty()
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
            installResultText.text = message
            Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
            persistCurrentInputs()
            renderProviderName()
        }.onFailure {
            val message = it.message ?: "install failed"
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
        providerNameText.text = if (name.isNullOrBlank()) {
            getString(R.string.provider_name_placeholder)
        } else {
            name
        }
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

        vpnToggleButton.text = getString(if (connected) R.string.disconnect_vpn else R.string.connect_vpn)
        vpnToggleButton.icon = ContextCompat.getDrawable(this, if (connected) R.drawable.stop_vpn else R.drawable.start_vpn)
        vpnToggleButton.background = ContextCompat.getDrawable(
            this,
            if (connected) R.drawable.bg_vpn_button_on else R.drawable.bg_vpn_button_off,
        )
        vpnActionHintText.text = getString(if (connected) R.string.disconnect_hint else R.string.connect_hint)

        settingsVpnToggleButton.text = getString(if (connected) R.string.disconnect else R.string.connect)

        val enableToggle = !connecting
        vpnToggleButton.isEnabled = enableToggle
        settingsVpnToggleButton.isEnabled = enableToggle
    }
}
