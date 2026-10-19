package app.kurotoon.android.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.nio.charset.StandardCharsets

data class MangaTile(
    val id: String,
    val title: String,
    val description: String?,
    val status: String?,
    val coverUrl: String?,
    val creators: List<String>,
    val sourceUrl: String = "https://mangadex.org",
    val contentRating: String = "unknown",
)

/**
 * Native, live-first MangaDex client. It retrieves only metadata and cover thumbnails:
 * chapters remain on the provider and are never copied or re-hosted by KuroToon.
 */
class MangaDexProvider(
    private val connectTimeoutMillis: Int = 8_000,
    private val readTimeoutMillis: Int = 12_000,
) {
    suspend fun getTrending(limit: Int = 18): List<MangaTile> = withContext(Dispatchers.IO) {
        require(limit in 1..100)
        val path = "/manga?limit=$limit&order%5BfollowedCount%5D=desc" +
            "&contentRating%5B%5D=safe&contentRating%5B%5D=suggestive" +
            "&includes%5B%5D=cover_art&includes%5B%5D=author&includes%5B%5D=artist"
        request(path)
    }

    suspend fun search(query: String, limit: Int = 20): List<MangaTile> = withContext(Dispatchers.IO) {
        val cleaned = query.trim()
        if (cleaned.isBlank()) return@withContext emptyList()
        require(cleaned.length <= 160) { "Search query is too long" }
        require(limit in 1..100)
        val encoded = URLEncoder.encode(cleaned, StandardCharsets.UTF_8.name())
        val path = "/manga?limit=$limit&title=$encoded&order%5Brelevance%5D=desc" +
            "&contentRating%5B%5D=safe&contentRating%5B%5D=suggestive" +
            "&includes%5B%5D=cover_art&includes%5B%5D=author&includes%5B%5D=artist"
        request(path)
    }

    private fun request(path: String): List<MangaTile> {
        val connection = (URL("https://api.mangadex.org$path").openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = connectTimeoutMillis
            readTimeout = readTimeoutMillis
            setRequestProperty("Accept", "application/json")
            setRequestProperty("User-Agent", "KuroToon-Native/0.1 (Android)")
            useCaches = false
        }

        try {
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
                ?: throw IllegalStateException("MangaDex returned HTTP $status")
            val body = stream.use { it.readBounded(MAX_RESPONSE_BYTES) }
            if (status !in 200..299) {
                throw IllegalStateException("MangaDex returned HTTP $status")
            }
            val root = JSONObject(body)
            val data = root.optJSONArray("data") ?: return emptyList()
            buildList {
                for (index in 0 until data.length()) {
                    val raw = data.optJSONObject(index) ?: continue
                    parseTile(raw)?.let(::add)
                }
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun parseTile(raw: JSONObject): MangaTile? {
        val id = raw.optString("id").takeIf(String::isNotBlank) ?: return null
        val attributes = raw.optJSONObject("attributes") ?: JSONObject()
        val titles = attributes.optJSONObject("title") ?: JSONObject()
        val title = sequenceOf("en", "ja-ro", "ja", "ko", "zh", "zh-hk")
            .mapNotNull { locale -> titles.optString(locale).takeIf(String::isNotBlank) }
            .firstOrNull()
            ?: titles.keys().asSequence().mapNotNull { titles.optString(it).takeIf(String::isNotBlank) }.firstOrNull()
            ?: "Untitled"

        val descriptionObject = attributes.optJSONObject("description") ?: JSONObject()
        val description = sequenceOf("en", "ja-ro", "ja", "ko", "zh")
            .mapNotNull { locale -> descriptionObject.optString(locale).takeIf(String::isNotBlank) }
            .firstOrNull()
            ?.take(500)

        val creators = mutableListOf<String>()
        var coverFile: String? = null
        val relationships = raw.optJSONArray("relationships")
        if (relationships != null) {
            for (index in 0 until relationships.length()) {
                val relation = relationships.optJSONObject(index) ?: continue
                val type = relation.optString("type")
                val relAttributes = relation.optJSONObject("attributes") ?: continue
                when (type) {
                    "cover_art" -> coverFile = relAttributes.optString("fileName").takeIf(String::isNotBlank)
                    "author", "artist" -> relAttributes.optString("name")
                        .takeIf(String::isNotBlank)
                        ?.let { name -> if (name !in creators) creators += name }
                }
            }
        }

        val coverUrl = coverFile?.let {
            "https://uploads.mangadex.org/covers/$id/$it.256.jpg"
        }
        return MangaTile(
            id = id,
            title = title,
            description = description,
            status = attributes.optString("status").takeIf(String::isNotBlank),
            coverUrl = coverUrl,
            creators = creators.take(3),
            sourceUrl = "https://mangadex.org/title/$id",
            contentRating = attributes.optString("contentRating").ifBlank { "unknown" },
        )
    }

    private fun java.io.InputStream.readBounded(maxBytes: Int): String {
        val output = ByteArrayOutputStream(minOf(maxBytes, 64 * 1024))
        val buffer = ByteArray(8 * 1024)
        var total = 0
        while (true) {
            val count = read(buffer)
            if (count < 0) break
            total += count
            require(total <= maxBytes) { "MangaDex response exceeded the safety limit" }
            output.write(buffer, 0, count)
        }
        return output.toString(StandardCharsets.UTF_8.name())
    }

    private companion object {
        const val MAX_RESPONSE_BYTES = 4 * 1024 * 1024
    }
}
