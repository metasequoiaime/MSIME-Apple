package app.msime.client.preview

import android.os.Bundle
import android.content.Intent
import android.webkit.WebView
import androidx.activity.enableEdgeToEdge

class MainActivity : TauriActivity() {
  override fun onWebViewCreate(webView: WebView) {
    super.onWebViewCreate(webView)
    app.msime.client.WindowLayout.fitSystemBars(webView)
    webView.post { webView.requestApplyInsets() }
  }
  override fun onCreate(savedInstanceState: Bundle?) {
    enableEdgeToEdge()
    super.onCreate(savedInstanceState)
    if (savedInstanceState == null && !java.io.File(filesDir, "runtime-options.json").exists()) {
      startActivity(Intent(this, app.msime.client.SetupActivity::class.java))
    }
  }
}
