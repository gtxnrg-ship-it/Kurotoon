package app.kurotoon.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import app.kurotoon.android.ui.KurotoonHomeScreen
import app.kurotoon.android.ui.KurotoonTheme

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
