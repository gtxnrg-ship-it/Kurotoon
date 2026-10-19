package app.kurotoon.native

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import app.kurotoon.native.ui.KurotoonHomeScreen
import app.kurotoon.native.ui.KurotoonTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            KurotoonTheme {
                KurotoonHomeScreen()
            }
        }
    }
}
