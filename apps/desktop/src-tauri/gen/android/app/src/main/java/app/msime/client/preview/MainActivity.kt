package app.msime.client.preview

import android.os.Bundle
import android.webkit.WebView
import androidx.activity.enableEdgeToEdge
import androidx.activity.OnBackPressedCallback

class MainActivity : TauriActivity() {
  private var settingsWebView: WebView? = null

  override fun onWebViewCreate(webView: WebView) {
    super.onWebViewCreate(webView)
    settingsWebView = webView
    app.msime.client.WindowLayout.fitSystemBars(webView)
    webView.post { webView.requestApplyInsets() }
  }

  override fun onCreate(savedInstanceState: Bundle?) {
    enableEdgeToEdge()
    super.onCreate(savedInstanceState)
    // Preparation used to sit behind a button on a development launcher screen. That screen is
    // gone, so each launcher triggers it; the call is idempotent and never overwrites an existing
    // configuration. Without this the bundle would ship a keyboard that cannot reach the Engine.
    app.msime.client.FirstRunPreparation.startIfNeeded(this)
    onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
      override fun handleOnBackPressed() {
        val webView = settingsWebView
        if (webView?.canGoBack() == true) {
          // The shared mobile settings UI owns the history entries. Going back
          // here dispatches popstate so nested pages and panels restore their
          // state instead of finishing the Activity.
          webView.goBack()
          return
        }
        // No app-owned history remains; let Android finish the Activity. The
        // callback must be disabled first to avoid recursively re-entering it.
        isEnabled = false
        onBackPressedDispatcher.onBackPressed()
        isEnabled = true
      }
    })
  }

  override fun onDestroy() {
    settingsWebView = null
    super.onDestroy()
  }
}
