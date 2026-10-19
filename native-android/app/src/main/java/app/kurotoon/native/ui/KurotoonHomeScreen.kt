package app.kurotoon.android.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.LocalContext
import coil.compose.AsyncImage
import app.kurotoon.android.data.ExperienceSettings
import app.kurotoon.android.data.KurotoonPreferences
import app.kurotoon.android.data.MangaDexProvider
import app.kurotoon.android.data.MangaTile
import app.kurotoon.android.experience.HapticsController
import app.kurotoon.android.experience.HapticMoment
import kotlinx.coroutines.launch

private data class PreviewDestination(
    val label: String,
    val symbol: String,
    val available: Boolean,
)

@Composable
fun KurotoonHomeScreen() {
    val context = LocalContext.current
    val preferences = remember { KurotoonPreferences(context) }
    val settings by preferences.settings.collectAsState(initial = ExperienceSettings())
    val source = remember { MangaDexProvider() }
    val scope = rememberCoroutineScope()
    val haptics = remember { HapticsController(context, preferences, scope) }

    var titles by remember { mutableStateOf<List<MangaTile>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    val refresh: () -> Unit = {
        scope.launch {
            loading = true
            errorMessage = null
            runCatching { source.getTrending(limit = 20) }
                .onSuccess { loaded ->
                    titles = loaded
                    if (loaded.isEmpty()) errorMessage = "MangaDex returned no titles for this request."
                }
                .onFailure { error ->
                    errorMessage = error.message?.take(180) ?: "Could not reach MangaDex."
                }
            loading = false
        }
    }

    LaunchedEffect(source) { refresh() }

    val destinations = listOf(
        PreviewDestination("Home", "✦", true),
        PreviewDestination("Browser", "⌕", false),
        PreviewDestination("Shop", "◇", false),
        PreviewDestination("Library", "▤", false),
        PreviewDestination("Me", "☾", false),
    )

    Box(Modifier.fillMaxSize()) {
        GalaxyBackdrop(motionEnabled = settings.galaxyMotionEnabled)
        Scaffold(
            containerColor = Color.Transparent,
            bottomBar = {
                NavigationBar(
                    containerColor = Color(0xF2070A18),
                    tonalElevation = 0.dp,
                ) {
                    destinations.forEachIndexed { index, destination ->
                        NavigationBarItem(
                            selected = index == 0,
                            onClick = { if (destination.available) haptics.play(HapticMoment.TAP) },
                            enabled = destination.available,
                            icon = {
                                Box(contentAlignment = Alignment.Center) {
                                    Text(
                                        text = if (destination.available) destination.symbol else "🔒",
                                        fontSize = if (destination.available) 21.sp else 15.sp,
                                        color = if (destination.available) Color(0xFFBBD9FF) else Color(0xFF64708A),
                                    )
                                }
                            },
                            label = {
                                Text(
                                    destination.label,
                                    fontSize = 10.sp,
                                    maxLines = 1,
                                )
                            },
                        )
                    }
                }
            },
        ) { innerPadding ->
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding),
                contentPadding = PaddingValues(start = 18.dp, end = 18.dp, top = 16.dp, bottom = 28.dp),
                verticalArrangement = Arrangement.spacedBy(18.dp),
            ) {
                item {
                    HomeHeader(onRefresh = {
                        haptics.play(HapticMoment.TAP)
                        refresh()
                    })
                }
                item {
                    HeroPanel()
                }
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                "YOUR UNIVERSE",
                                color = Color(0xFF9FB9EF),
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold,
                                letterSpacing = 2.1.sp,
                            )
                            Spacer(Modifier.weight(1f))
                            Text(
                                "LIVE CATALOG",
                                color = Color(0xFF7DE4D2),
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Bold,
                                letterSpacing = 1.2.sp,
                            )
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            AssistChip(
                                onClick = { },
                                label = { Text("Trending") },
                                enabled = true,
                                colors = AssistChipDefaults.assistChipColors(
                                    containerColor = Color(0xB7253A60),
                                    labelColor = Color(0xFFE7F0FF),
                                ),
                                border = BorderStroke(1.dp, Color(0x667BA9F7)),
                            )
                            AssistChip(
                                onClick = { },
                                label = { Text("Categories 🔒") },
                                enabled = false,
                            )
                            AssistChip(
                                onClick = { },
                                label = { Text("Filters 🔒") },
                                enabled = false,
                            )
                        }
                    }
                }
                item {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.Bottom,
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text(
                                "Stories in orbit",
                                color = Color(0xFFF5F7FF),
                                fontSize = 22.sp,
                                fontWeight = FontWeight.SemiBold,
                            )
                            Spacer(Modifier.height(4.dp))
                            Text(
                                "Real cover art and titles, fetched live from MangaDex.",
                                color = Color(0xFFABB7D5),
                                fontSize = 12.sp,
                            )
                        }
                        Text(
                            if (titles.isEmpty()) "—" else titles.size.toString().padStart(2, '0'),
                            color = Color(0xFF9CCBFF),
                            fontSize = 18.sp,
                            fontWeight = FontWeight.Medium,
                        )
                    }
                }
                if (loading && titles.isEmpty()) {
                    item {
                        Box(
                            Modifier.fillMaxWidth().height(184.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(28.dp),
                                    color = Color(0xFF9CCBFF),
                                    strokeWidth = 2.dp,
                                )
                                Spacer(Modifier.height(12.dp))
                                Text("Finding worlds beyond the horizon…", color = Color(0xFFB7C5E3), fontSize = 12.sp)
                            }
                        }
                    }
                }
                if (!loading && titles.isNotEmpty()) {
                    item {
                        LazyRow(horizontalArrangement = Arrangement.spacedBy(13.dp)) {
                            items(titles, key = { it.id }) { tile -> MangaCoverCard(tile) }
                        }
                    }
                }
                if (errorMessage != null) {
                    item {
                        Card(
                            colors = CardDefaults.cardColors(containerColor = Color(0xC9171B30)),
                            border = BorderStroke(1.dp, Color(0x664C658D)),
                            shape = RoundedCornerShape(18.dp),
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text(
                                    if (titles.isEmpty()) "The signal is quiet" else "Some titles could not load",
                                    color = Color(0xFFF3F5FF),
                                    fontWeight = FontWeight.SemiBold,
                                )
                                Text(
                                    errorMessage.orEmpty(),
                                    color = Color(0xFFAEBBD8),
                                    fontSize = 12.sp,
                                )
                                TextButton(onClick = {
                                    haptics.play(HapticMoment.TAP)
                                    refresh()
                                }) { Text("Try again", color = Color(0xFF9CCBFF)) }
                            }
                        }
                    }
                }
                if (titles.isNotEmpty()) {
                    item {
                        SourceFootnote()
                    }
                }
                item {
                    LockedPreviewFooter()
                }
            }
        }
    }
}

@Composable
private fun HomeHeader(onRefresh: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(42.dp)
                .clip(RoundedCornerShape(15.dp))
                .background(
                    Brush.linearGradient(
                        listOf(Color(0xFF6F9FFF), Color(0xFF9C83FF), Color(0xFF52DCC9)),
                    ),
                ),
            contentAlignment = Alignment.Center,
        ) {
            Text("✦", color = Color(0xFF081024), fontSize = 25.sp, fontWeight = FontWeight.Black)
        }
        Column(Modifier.weight(1f)) {
            Text(
                "KUROTOON",
                fontSize = 16.sp,
                letterSpacing = 3.sp,
                color = Color(0xFFF4F7FF),
                fontWeight = FontWeight.ExtraBold,
            )
            Text(
                "GALAXY READER  ·  NATIVE PREVIEW",
                fontSize = 8.sp,
                letterSpacing = 1.15.sp,
                color = Color(0xFF9BAED1),
            )
        }
        TextButton(onClick = onRefresh) {
            Text("↻", color = Color(0xFFB9D6FF), fontSize = 25.sp)
        }
    }
}

@Composable
private fun HeroPanel() {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(26.dp),
        colors = CardDefaults.cardColors(containerColor = Color(0xA9141D38)),
        border = BorderStroke(1.dp, Color(0x5277A2E9)),
    ) {
        Box(Modifier.fillMaxWidth()) {
            Box(
                Modifier
                    .align(Alignment.TopEnd)
                    .size(185.dp)
                    .background(
                        Brush.radialGradient(
                            colors = listOf(Color(0x357D9CFF), Color(0x147D70FF), Color.Transparent),
                        ),
                        CircleShape,
                    ),
            )
            Column(
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 22.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Text(
                    "A GALAXY OF STORIES",
                    color = Color(0xFF91E3E2),
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 2.sp,
                )
                Text(
                    "Your next world\nis out there.",
                    color = Color(0xFFF5F7FF),
                    fontSize = 29.sp,
                    lineHeight = 34.sp,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    "One calm library. Countless universes.\nLive sources, your space.",
                    color = Color(0xFFB7C7E4),
                    fontSize = 12.sp,
                    lineHeight = 19.sp,
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        Modifier.size(7.dp).clip(CircleShape).background(Color(0xFF6BE2C7)),
                    )
                    Spacer(Modifier.width(7.dp))
                    Text(
                        "THE GALAXY IS MOVING",
                        color = Color(0xFFA8C8F8),
                        fontSize = 9.sp,
                        letterSpacing = 1.2.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }
        }
    }
}

@Composable
private fun MangaCoverCard(tile: MangaTile) {
    Column(
        modifier = Modifier.width(146.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Card(
            modifier = Modifier.fillMaxWidth().height(204.dp),
            shape = RoundedCornerShape(18.dp),
            colors = CardDefaults.cardColors(containerColor = Color(0xB41B2440)),
            border = BorderStroke(1.dp, Color(0x3C9AB8F9)),
        ) {
            Box(Modifier.fillMaxSize()) {
                if (tile.coverUrl != null) {
                    AsyncImage(
                        model = tile.coverUrl,
                        contentDescription = "Cover art for ${tile.title}, from MangaDex",
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize(),
                    )
                } else {
                    Box(
                        Modifier.fillMaxSize().background(
                            Brush.linearGradient(listOf(Color(0xFF253B68), Color(0xFF352B61), Color(0xFF143F50))),
                        ),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text("✦", color = Color(0xFFDBE8FF), fontSize = 44.sp)
                    }
                }
                Box(
                    Modifier.align(Alignment.BottomStart).padding(8.dp)
                        .clip(RoundedCornerShape(7.dp))
                        .background(Color(0xD8070A18))
                        .padding(horizontal = 7.dp, vertical = 4.dp),
                ) {
                    Text(
                        (tile.status ?: "Live").replaceFirstChar { it.uppercase() },
                        color = Color(0xFFDCE9FF),
                        fontSize = 9.sp,
                        maxLines = 1,
                    )
                }
            }
        }
        Text(
            tile.title,
            color = Color(0xFFF2F5FF),
            fontSize = 13.sp,
            lineHeight = 17.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            tile.creators.take(2).joinToString(", ").ifBlank { "Creator information unavailable" },
            color = Color(0xFF9BAAC8),
            fontSize = 10.sp,
            lineHeight = 14.sp,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun SourceFootnote() {
    Row(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp))
            .background(Color(0x7910182D)).padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text("↗", color = Color(0xFF9CCBFF), fontSize = 14.sp)
        Text(
            "Catalog and cover art are provided live by MangaDex. KuroToon does not host or bundle these comic assets.",
            color = Color(0xFF9CAAC6),
            fontSize = 10.sp,
            lineHeight = 15.sp,
        )
    }
}

@Composable
private fun LockedPreviewFooter() {
    Column(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp))
            .background(Color(0x6612192D)).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Text("PREVIEW ACCESS", color = Color(0xFF8CA8DD), fontSize = 9.sp, letterSpacing = 1.6.sp, fontWeight = FontWeight.Bold)
        Text("Home is open. The rest stays sealed.", color = Color(0xFFE5EBFA), fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        Text(
            "Browser, categories, Shop, Library, Me and settings are intentionally locked while the native foundation is being built.",
            color = Color(0xFF9DAAC4),
            fontSize = 11.sp,
            lineHeight = 16.sp,
        )
    }
}
