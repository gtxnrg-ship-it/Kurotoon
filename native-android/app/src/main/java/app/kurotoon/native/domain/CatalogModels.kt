package app.kurotoon.native.domain

enum class ChapterKind { REGULAR, MINI, SPECIAL, EXTRA, SEASON_BREAK, UNKNOWN }
enum class ComicFormat { MANGA, MANHWA, MANHUA, WEBTOON, COMIC, DOUJIN, OTHER, UNKNOWN }
enum class PublicationStatus { ONGOING, COMPLETED, HIATUS, CANCELLED, UNKNOWN }
enum class LibraryStatus { READING, COMPLETED, PAUSED, PLANNED, DROPPED }
enum class ReviewDecision { PENDING, ACCEPTED, REJECTED }

data class ProviderListing(
    val id: String,
    val providerId: String,
    val providerWorkId: String,
    val url: String,
    val title: String,
    val aliases: List<String> = emptyList(),
    val externalIds: Map<String, String> = emptyMap(),
    val globalCreatorIds: Set<String> = emptySet(),
    val creatorNames: List<String> = emptyList(),
    val languageCode: String? = null,
    val originalLanguage: String? = null,
    val format: ComicFormat = ComicFormat.UNKNOWN,
    val publicationStatus: PublicationStatus = PublicationStatus.UNKNOWN,
    val coverUrl: String? = null,
    val description: String? = null,
    val lastVerifiedAtEpochMillis: Long? = null,
)

data class ChapterListing(
    val id: String,
    val providerId: String,
    val providerWorkId: String,
    val providerChapterId: String,
    val url: String,
    val numberLabel: String?,
    val title: String?,
    val volumeLabel: String?,
    val kind: ChapterKind = ChapterKind.UNKNOWN,
    val languageCode: String? = null,
    val pageCount: Int? = null,
    val publishedAt: String? = null,
    val lastVerifiedAtEpochMillis: Long? = null,
) {
    init {
        require(id.isNotBlank())
        require(providerId.isNotBlank())
        require(providerWorkId.isNotBlank())
        require(providerChapterId.isNotBlank())
        require(url.isNotBlank())
        require(pageCount == null || pageCount >= 0)
    }
}

data class WorkIdentityCandidate(
    val stableKey: String,
    val title: String,
    val aliases: List<String> = emptyList(),
    val externalIds: Map<String, String> = emptyMap(),
    /** Only globally comparable creator keys belong here; provider-local IDs are not global. */
    val globalCreatorIds: Set<String> = emptySet(),
) {
    init {
        require(stableKey.isNotBlank())
    }

    companion object {
        fun from(listing: ProviderListing) = WorkIdentityCandidate(
            stableKey = "${listing.providerId}:${listing.providerWorkId}",
            title = listing.title,
            aliases = listing.aliases,
            externalIds = listing.externalIds,
            globalCreatorIds = listing.globalCreatorIds,
        )
    }
}

data class WorkMatchAssessment(
    val confidence: Double,
    val autoMerge: Boolean,
    val reasons: List<String>,
)

data class WorkIdentityGroup(
    val stableGroupKey: String,
    val canonicalTitle: String,
    val listingIds: List<String>,
    val providerIds: List<String>,
    val matchConfidence: Double,
)

data class MergeReviewSuggestion(
    val leftListingId: String,
    val rightListingId: String,
    val confidence: Double,
    val reasons: List<String>,
)

data class CatalogGroupingResult(
    val groups: List<WorkIdentityGroup>,
    val reviewSuggestions: List<MergeReviewSuggestion>,
    val candidatePairCount: Int,
    val wasCandidateLimitReached: Boolean,
)

data class ProviderCapabilities(
    val search: Boolean = true,
    val workDetails: Boolean = false,
    val chapters: Boolean = false,
    val chapterPages: Boolean = false,
    val creatorSearch: Boolean = false,
)

data class ProviderHealth(
    val providerId: String,
    val healthy: Boolean,
    val checkedAtEpochMillis: Long,
    val message: String? = null,
)

enum class ProviderFailureCode {
    TIMEOUT, NETWORK, BLOCKED, RATE_LIMITED, INVALID_RESPONSE, UNSUPPORTED, CANCELLED, UNKNOWN
}

data class ProviderFailure(
    val providerId: String,
    val code: ProviderFailureCode,
    val message: String,
    val retryable: Boolean,
)

sealed interface SearchSourceOutcome {
    val providerId: String

    data class Success(override val providerId: String, val listingIds: List<String>) : SearchSourceOutcome
    data class Empty(override val providerId: String) : SearchSourceOutcome
    data class Failed(override val providerId: String, val failure: ProviderFailure) : SearchSourceOutcome
}

data class UniversalWorkGroup(
    val stableGroupKey: String,
    val canonicalTitle: String,
    val listings: List<ProviderListing>,
    val confidence: Double,
    val hasPotentialDuplicates: Boolean = false,
)

data class UnifiedSearchResult(
    val query: String,
    val listings: List<ProviderListing>,
    val groups: List<UniversalWorkGroup>,
    val reviewSuggestions: List<MergeReviewSuggestion>,
    val outcomes: List<SearchSourceOutcome>,
    val isPartial: Boolean,
    val completedAtEpochMillis: Long,
)
