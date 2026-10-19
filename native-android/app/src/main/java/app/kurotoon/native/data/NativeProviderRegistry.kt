package app.kurotoon.native.data

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withTimeout

interface NativeComicProvider {
    val id: String
    val displayName: String
    suspend fun trending(limit: Int): List<MangaTile>
    suspend fun search(query: String, limit: Int): List<MangaTile>
}

class MangaDexNativeSource(private val api: MangaDexProvider = MangaDexProvider()) : NativeComicProvider {
    override val id = "mangadex"
    override val displayName = "MangaDex"
    override suspend fun trending(limit: Int) = api.getTrending(limit)
    override suspend fun search(query: String, limit: Int) = api.search(query, limit)
}

/** Explicit enable/disable registry; adding a metadata index never implies executable source support. */
class NativeProviderRegistry(providers: List<NativeComicProvider>) {
    private val providersById = providers.associateBy { it.id }
    private val enabledIds = providersById.keys.toMutableSet()

    init {
        require(providersById.size == providers.size) { "Provider IDs must be unique" }
        require(providersById.keys.none(String::isBlank)) { "Provider IDs must not be blank" }
    }

    @Synchronized
    fun enabledProviders(): List<NativeComicProvider> =
        enabledIds.mapNotNull(providersById::get)

    @Synchronized
    fun setEnabled(providerId: String, enabled: Boolean) {
        require(providerId in providersById) { "Unknown provider: $providerId" }
        if (enabled) enabledIds.add(providerId) else enabledIds.remove(providerId)
    }

    @Synchronized
    fun isEnabled(providerId: String): Boolean = providerId in enabledIds
}

sealed interface NativeProviderOutcome {
    val providerId: String
    data class Success(override val providerId: String, val items: List<MangaTile>) : NativeProviderOutcome
    data class Failure(override val providerId: String, val message: String, val timedOut: Boolean) : NativeProviderOutcome
}

data class NativeSearchBatch(
    val items: List<MangaTile>,
    val outcomes: List<NativeProviderOutcome>,
    val isPartial: Boolean,
)

/** Keeps source work bounded and returns partial results if any provider fails. */
class NativeSearchCoordinator(
    private val registry: NativeProviderRegistry,
    private val maxConcurrentProviders: Int = 3,
    private val perProviderTimeoutMillis: Long = 12_000,
) {
    init {
        require(maxConcurrentProviders in 1..8)
        require(perProviderTimeoutMillis in 1_000..60_000)
    }

    suspend fun search(query: String, limitPerProvider: Int = 20): NativeSearchBatch {
        val cleaned = query.trim()
        require(cleaned.length <= 160) { "Search query is too long" }
        if (cleaned.isBlank()) return NativeSearchBatch(emptyList(), emptyList(), false)

        val semaphore = Semaphore(maxConcurrentProviders)
        val providers = registry.enabledProviders()
        val outcomes = coroutineScope {
            providers.map { provider ->
                async {
                    try {
                        semaphore.withPermit {
                            withTimeout(perProviderTimeoutMillis) {
                                NativeProviderOutcome.Success(provider.id, provider.search(cleaned, limitPerProvider))
                            }
                        }
                    } catch (cancelled: CancellationException) {
                        throw cancelled
                    } catch (error: Exception) {
                        NativeProviderOutcome.Failure(
                            providerId = provider.id,
                            message = error.message?.take(240) ?: "Provider failed",
                            timedOut = error is kotlinx.coroutines.TimeoutCancellationException,
                        )
                    }
                }
            }.awaitAll()
        }

        val allItems = outcomes.filterIsInstance<NativeProviderOutcome.Success>()
            .flatMap { it.items }
            .distinctBy { "${it.id}:${it.sourceUrl}" }
        return NativeSearchBatch(
            items = allItems,
            outcomes = outcomes,
            isPartial = outcomes.any { it is NativeProviderOutcome.Failure } && outcomes.any { it is NativeProviderOutcome.Success },
        )
    }
}
