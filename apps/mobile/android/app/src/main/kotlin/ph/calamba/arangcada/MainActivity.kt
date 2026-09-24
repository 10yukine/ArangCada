package ph.calamba.arangcada

import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.View
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    private fun applyEdgeToEdge() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
            window.isStatusBarContrastEnforced = false
        }

        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE
            or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
            or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
            or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
            or View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
        )

        val controller = WindowCompat.getInsetsController(window, window.decorView)
        controller.isAppearanceLightNavigationBars = true
        controller.isAppearanceLightStatusBars = true
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyEdgeToEdge()
        window.decorView.setOnApplyWindowInsetsListener { _, insets ->
            applyEdgeToEdge()
            insets
        }
    }

    override fun onPostResume() {
        super.onPostResume()
        applyEdgeToEdge()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            applyEdgeToEdge()
        }
    }
}
