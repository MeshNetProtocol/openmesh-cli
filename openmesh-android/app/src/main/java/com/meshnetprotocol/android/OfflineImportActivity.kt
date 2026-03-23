package com.meshnetprotocol.android

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.button.MaterialButton
import com.google.android.material.textfield.TextInputEditText
import java.net.URL
import java.net.HttpURLConnection
import javax.net.ssl.HttpsURLConnection
import java.io.BufferedReader
import java.io.InputStreamReader

class OfflineImportActivity : AppCompatActivity() {

    private lateinit var urlInput: TextInputEditText
    private lateinit var contentInput: TextInputEditText
    private lateinit var statsText: TextView
    private lateinit var errorText: TextView
    private lateinit var fetchUrlButton: MaterialButton
    private lateinit var pasteButton: MaterialButton
    private lateinit var clearButton: MaterialButton
    private lateinit var loadingOverlay: View
    private lateinit var loadingText: TextView
    private lateinit var installButton: MaterialButton
    private lateinit var footerStatusText: TextView
    private lateinit var footerStatsText: TextView

    private val mainHandler = Handler(Looper.getMainLooper())
    private var isFetching = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 隐藏ActionBar，使用自定义的顶部工具栏（与 iOS 一致）
        supportActionBar?.hide()
        
        try {
            setContentView(R.layout.activity_offline_import)

            urlInput = findViewById(R.id.urlInput)
            contentInput = findViewById(R.id.contentInput)
            statsText = findViewById(R.id.statsText)
            errorText = findViewById(R.id.errorText)
            fetchUrlButton = findViewById(R.id.fetchUrlButton)
            pasteButton = findViewById(R.id.pasteButton)
            clearButton = findViewById(R.id.clearButton)
            loadingOverlay = findViewById(R.id.loadingOverlay)
            loadingText = findViewById(R.id.loadingText)
            installButton = findViewById(R.id.installButton)
            footerStatusText = findViewById(R.id.footerStatusText)
            footerStatsText = findViewById(R.id.footerStatsText)
            val closeButton = findViewById<MaterialButton>(R.id.closeButton)

            // 绑定按钮事件
            closeButton.setOnClickListener { finish() }
            fetchUrlButton.setOnClickListener { fetchFromURL() }
            pasteButton.setOnClickListener { pasteFromClipboard() }
            clearButton.setOnClickListener { clearContent() }
            installButton.setOnClickListener { installImportedContent() }

            // 监听内容变化更新统计
            contentInput.addTextChangedListener(object : android.text.TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                    updateStats()
                    updateClearButtonState()
                    updateInstallButtonState()
                }
                override fun afterTextChanged(s: android.text.Editable?) {}
            })

            updateClearButtonState()
            updateInstallButtonState()
        } catch (e: Exception) {
            android.util.Log.e("OpenMeshAndroid", "OfflineImportActivity onCreate 失败：${e.message}", e)
            Toast.makeText(this, "初始化失败：${e.message}", Toast.LENGTH_LONG).show()
            e.printStackTrace()
            finish()
        }
    }

    private fun updateStats() {
        val text = contentInput.text?.toString() ?: ""
        val lines = if (text.isEmpty()) 0 else text.split("\n").size
        val chars = text.length
        statsText.text = "行 $lines  字符 $chars"
        footerStatsText.text = "行 $lines · 字符 $chars"
    }

    private fun updateClearButtonState() {
        val text = contentInput.text?.toString()?.trim().orEmpty()
        clearButton.isEnabled = !isFetching && text.isNotEmpty()
    }

    private fun updateInstallButtonState() {
        val text = contentInput.text?.toString()?.trim().orEmpty()
        val hasContent = text.isNotEmpty()
        installButton.isEnabled = !isFetching && hasContent
        
        if (hasContent) {
            footerStatusText.text = "准备安装导入内容"
        } else {
            footerStatusText.text = "等待输入内容"
        }
    }

    private fun pasteFromClipboard() {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = clipboard.primaryClip
        if (clip != null && clip.itemCount > 0) {
            val text = clip.getItemAt(0).text
            if (text != null) {
                contentInput.setText(text.toString())
            }
        } else {
            Toast.makeText(this, "剪贴板为空", Toast.LENGTH_SHORT).show()
        }
    }

    private fun clearContent() {
        contentInput.text?.clear()
        errorText.visibility = View.GONE
        errorText.text = ""
    }

    private fun fetchFromURL() {
        val urlStr = urlInput.text?.toString()?.trim().orEmpty()
        if (urlStr.isEmpty()) {
            Toast.makeText(this, "请输入 URL", Toast.LENGTH_SHORT).show()
            return
        }

        // 规范化 URL
        val normalizedUrl = normalizeURL(urlStr)
        if (!isValidURL(normalizedUrl)) {
            errorText.text = "URL 无效：仅支持 http/https"
            errorText.visibility = View.VISIBLE
            return
        }

        errorText.visibility = View.GONE
        isFetching = true
        updateUIForFetching()

        Thread {
            var lastError: Exception? = null
            var result: String? = null

            for (attempt in 1..3) {
                try {
                    mainHandler.post {
                        loadingText.text = "正在从 URL 拉取内容（第 $attempt/3 次尝试）…"
                    }

                    val url = URL(normalizedUrl)
                    // 支持 HTTP 和 HTTPS，使用 HttpURLConnection 类型
                    val connection = url.openConnection() as HttpURLConnection
                    connection.requestMethod = "GET"
                    connection.connectTimeout = 20000
                    connection.readTimeout = 20000
                    connection.setRequestProperty("Accept", "application/json, text/plain, */*")
                    connection.setRequestProperty("Cache-Control", "no-cache")

                    val responseCode = (connection as? HttpURLConnection)?.responseCode 
                        ?: throw Exception("无法连接")
                    
                    if (responseCode == HttpURLConnection.HTTP_OK) {
                        val reader = BufferedReader(InputStreamReader(connection.inputStream, "UTF-8"))
                        val builder = StringBuilder()
                        var line: String?
                        while (reader.readLine().also { line = it } != null) {
                            builder.append(line)
                            builder.append("\n")
                        }
                        reader.close()
                        result = builder.toString()
                        break
                    } else {
                        throw Exception("HTTP $responseCode")
                    }
                } catch (e: Exception) {
                    lastError = e
                    if (attempt < 3) {
                        try {
                            Thread.sleep(300L * attempt)
                        } catch (ie: InterruptedException) {
                            // ignore
                        }
                    }
                }
            }

            mainHandler.post {
                isFetching = false
                updateUIForFetching()

                if (result != null) {
                    contentInput.setText(result)
                    Toast.makeText(this@OfflineImportActivity, "拉取成功", Toast.LENGTH_SHORT).show()
                } else {
                    val errorMsg = lastError?.message ?: "未知错误"
                    errorText.text = "拉取失败：$errorMsg\nURL：$normalizedUrl"
                    errorText.visibility = View.VISIBLE
                }
            }
        }.start()
    }

    private fun updateUIForFetching() {
        fetchUrlButton.isEnabled = !isFetching
        pasteButton.isEnabled = !isFetching
        clearButton.isEnabled = !isFetching && contentInput.text?.toString()?.trim().orEmpty().isNotEmpty()
        urlInput.isEnabled = !isFetching
        contentInput.isEnabled = !isFetching
        loadingOverlay.visibility = if (isFetching) View.VISIBLE else View.GONE
        updateInstallButtonState()
    }

    private fun normalizeURL(input: String): String {
        var s = input.trim()
        // 移除可能的引号
        if ((s.startsWith("`") && s.endsWith("`")) || (s.startsWith("\"") && s.endsWith("\""))) {
            s = s.drop(1).dropLast(1)
        }
        s = s.trim()
        // 移除标点
        s = s.trimEnd(',', '，', '.', '。', ';', '；')
        return s
    }

    private fun isValidURL(url: String): Boolean {
        return try {
            val u = URL(url)
            (u.protocol == "http" || u.protocol == "https") && u.host != null
        } catch (e: Exception) {
            false
        }
    }

    /**
     * 安装导入的内容
     */
    fun installImportedContent() {
        val content = contentInput.text?.toString()?.trim().orEmpty()
        if (content.isEmpty()) {
            errorText.text = "请输入导入内容"
            errorText.visibility = View.VISIBLE
            return
        }

        try {
            val manager = ImportInstallManager(this)
            val payload = manager.parseImportPayload(content)
            
            val providerID = if (payload.providerID.isEmpty()) {
                manager.generateProviderID()
            } else {
                payload.providerID
            }
            
            val providerName = if (payload.providerName.isEmpty()) {
                "导入供应商"
            } else {
                payload.providerName
            }

            // 显示安装向导对话框
            showInstallWizard(providerID, providerName, payload)
        } catch (e: Exception) {
            errorText.text = "解析失败：${e.message}"
            errorText.visibility = View.VISIBLE
        }
    }

    private fun showInstallWizard(providerID: String, providerName: String, payload: ImportPayload) {
        val wizardDialog = InstallWizardDialog(this, providerID, providerName, payload)
        wizardDialog.setOnCompletedListener {
            // 安装完成后的回调
            Toast.makeText(this, "安装完成", Toast.LENGTH_SHORT).show()
            finish()
        }
        wizardDialog.show()
    }
}
