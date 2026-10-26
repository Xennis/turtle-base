package org.xennis.apps.turtlebase

import android.os.Bundle
import android.view.View
import androidx.activity.enableEdgeToEdge
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat

class MainActivity : TauriActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    enableEdgeToEdge()
    super.onCreate(savedInstanceState)
    resizeForKeyboard()
  }

  /**
   * Edge to edge, Android no longer resizes the window for the keyboard - it would cover the page's lower part (e.g. a
   * dialog's buttons). The WebView ends above the keyboard instead, so the page's viewport shrinks as in a browser.
   * The navigation bar's part of the keyboard's inset stays, the page keeps it free via `env(safe-area-inset-bottom)`.
   */
  private fun resizeForKeyboard() {
    ViewCompat.setOnApplyWindowInsetsListener(findViewById<View>(android.R.id.content)) { view, insets ->
      val keyboard = insets.getInsets(WindowInsetsCompat.Type.ime()).bottom
      val navigationBar = insets.getInsets(WindowInsetsCompat.Type.navigationBars()).bottom
      view.setPadding(0, 0, 0, maxOf(0, keyboard - navigationBar))
      insets
    }
  }
}
