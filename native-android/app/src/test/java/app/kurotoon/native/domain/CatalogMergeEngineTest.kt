package app.kurotoon.android.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CatalogMergeEngineTest {
    private fun listing(
        id: String,
        provider: String,
        title: String,
        creator: String? = null,
        aliases: List<String> = emptyList(),
        externalIds: Map<String, String> = emptyMap(),
    ) = ProviderListing(
        id = id,
        providerId = provider,
        providerWorkId = id,
        url = "https://example.test/$id",
        title = title,
        aliases = aliases,
        globalCreatorIds = creator?.let(::setOf) ?: emptySet(),
        externalIds = externalIds,
    )

    @Test
    fun duplicateListingsGroupAndPreserveBothSources() {
        val result = CatalogMergeEngine().group(listOf(
            listing("1", "alpha", "Blue Star", "global:artist:2"),
            listing("2", "beta", "Blue Star", "global:artist:2"),
        ))
        assertEquals(1, result.groups.size)
        assertEquals(setOf("alpha", "beta"), result.groups.single().providerIds.toSet())
        assertEquals(2, result.groups.single().listingIds.size)
    }

    @Test
    fun aliasOnlyOverlapBecomesReviewSuggestion() {
        val result = CatalogMergeEngine().group(listOf(
            listing("1", "alpha", "Blue Star", aliases = listOf("Star of Blue")),
            listing("2", "beta", "Night Road", aliases = listOf("Blue Star")),
        ))
        assertEquals(2, result.groups.size)
        assertTrue(result.reviewSuggestions.isNotEmpty())
    }

    @Test
    fun duplicateWithinOneProviderIsNotShownTwice() {
        val result = CatalogMergeEngine().group(listOf(
            listing("1", "alpha", "Blue Star"),
            listing("1", "alpha", "Blue Star alternate"),
        ))
        assertEquals(1, result.groups.size)
        assertFalse(result.groups.single().listingIds.isEmpty())
    }

    @Test
    fun pairCandidateLimitIsBounded() {
        val listings = (1..100).map { listing("$it", "p$it", "Common Title", "creator:shared") }
        val result = CatalogMergeEngine(maxCandidatePairs = 25).group(listings)
        assertTrue(result.wasCandidateLimitReached)
        assertTrue(result.candidatePairCount <= 25)
    }
}
