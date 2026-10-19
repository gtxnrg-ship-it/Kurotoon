package app.kurotoon.native.domain

import java.util.TreeSet

/**
 * Bounded batch grouping. Candidate generation is index-based rather than a full all-pairs scan.
 * Ambiguous matches become review suggestions; clusters are joined only when every cross-pair
 * passes the conservative auto-merge rule (no ambiguous bridge-record merges).
 */
class CatalogMergeEngine(
    private val maxCandidatePairs: Int = 100_000,
    private val maxBucketSize: Int = 64,
    private val maxReviewSuggestions: Int = 500,
) {
    init {
        require(maxCandidatePairs > 0)
        require(maxBucketSize >= 2)
        require(maxReviewSuggestions >= 0)
    }

    fun group(listings: List<ProviderListing>): CatalogGroupingResult {
        val items = listings
            .distinctBy { "${it.providerId}:${it.providerWorkId}" }
            .sortedBy { "${it.providerId}:${it.providerWorkId}" }
        if (items.isEmpty()) return CatalogGroupingResult(emptyList(), emptyList(), 0, false)

        val candidates = items.map(WorkIdentityCandidate::from)
        val bucketIndex = linkedMapOf<String, MutableList<Int>>()
        candidates.forEachIndexed { index, candidate ->
            val keys = buildSet {
                val primary = WorkIdentityEngine.comparisonTitle(candidate.title)
                if (primary.isNotBlank()) {
                    add("title-creator:$primary")
                    candidate.globalCreatorIds.forEach { add("title-creator:$primary|creator:${it.trim().lowercase()}") }
                }
                candidate.aliases.forEach { alias ->
                    val normalized = WorkIdentityEngine.comparisonTitle(alias)
                    if (normalized.isNotBlank()) add("alias:$normalized")
                }
                candidate.externalIds.forEach { (namespace, value) ->
                    if (namespace.isNotBlank() && value.isNotBlank()) {
                        add("external:${namespace.trim().lowercase()}:${value.trim().lowercase()}")
                    }
                }
                candidate.globalCreatorIds.forEach { creator ->
                    val normalizedCreator = creator.trim().lowercase()
                    if (normalizedCreator.isNotBlank()) add("creator:$normalizedCreator")
                }
            }
            keys.forEach { key -> bucketIndex.getOrPut(key) { mutableListOf() }.add(index) }
        }

        val pairs = TreeSet<Long>()
        var limitReached = false
        fun addPair(left: Int, right: Int) {
            if (left == right) return
            val a = minOf(left, right)
            val b = maxOf(left, right)
            val encoded = (a.toLong() shl 32) or (b.toLong() and 0xffffffffL)
            if (pairs.contains(encoded)) return
            if (pairs.size >= maxCandidatePairs) {
                limitReached = true
                return
            }
            pairs.add(encoded)
        }
        bucketIndex.values.forEach { bucket ->
            val bounded = bucket.take(maxBucketSize)
            for (i in bounded.indices) {
                for (j in i + 1 until bounded.size) addPair(bounded[i], bounded[j])
            }
        }

        val assessmentByPair = HashMap<Long, WorkMatchAssessment>(pairs.size)
        val neighbors = Array(items.size) { mutableListOf<Int>() }
        val suggestions = mutableListOf<MergeReviewSuggestion>()
        pairs.forEach { key ->
            val left = (key shr 32).toInt()
            val right = (key and 0xffffffffL).toInt()
            val assessment = WorkIdentityEngine.assess(candidates[left], candidates[right])
            assessmentByPair[key] = assessment
            if (assessment.autoMerge) {
                neighbors[left] += right
                neighbors[right] += left
            } else if (assessment.confidence >= 0.50 && suggestions.size < maxReviewSuggestions) {
                suggestions += MergeReviewSuggestion(
                    leftListingId = items[left].id,
                    rightListingId = items[right].id,
                    confidence = assessment.confidence,
                    reasons = assessment.reasons,
                )
            }
        }

        val clusterMembers = mutableListOf<MutableList<Int>>()
        val clusterOf = IntArray(items.size) { -1 }
        for (index in items.indices) {
            val neighboringClusters = neighbors[index]
                .map { clusterOf[it] }
                .filter { it >= 0 }
                .distinct()
                .sorted()
            val targetCluster = neighboringClusters.firstOrNull { clusterId ->
                clusterMembers[clusterId].all { existing ->
                    val low = minOf(index, existing)
                    val high = maxOf(index, existing)
                    val key = (low.toLong() shl 32) or (high.toLong() and 0xffffffffL)
                    assessmentByPair[key]?.autoMerge == true
                }
            }
            if (targetCluster == null) {
                clusterOf[index] = clusterMembers.size
                clusterMembers += mutableListOf(index)
            } else {
                clusterOf[index] = targetCluster
                clusterMembers[targetCluster] += index
            }
        }

        val groups = clusterMembers.map { memberIndexes ->
            val memberListings = memberIndexes.map(items::get)
            val title = selectCanonicalTitle(memberListings)
            val confidence = if (memberIndexes.size <= 1) 1.0 else memberIndexes
                .flatMapIndexed { position, left ->
                    memberIndexes.drop(position + 1).map { right ->
                        val low = minOf(left, right)
                        val high = maxOf(left, right)
                        val key = (low.toLong() shl 32) or (high.toLong() and 0xffffffffL)
                        assessmentByPair[key]?.confidence ?: 0.0
                    }
                }.minOrNull() ?: 1.0
            WorkIdentityGroup(
                stableGroupKey = memberListings.minOf { "${it.providerId}:${it.providerWorkId}" },
                canonicalTitle = title,
                listingIds = memberListings.map { it.id },
                providerIds = memberListings.map { it.providerId }.distinct().sorted(),
                matchConfidence = confidence,
            )
        }.sortedBy { WorkIdentityEngine.comparisonTitle(it.canonicalTitle) }

        val review = suggestions.distinctBy { listOf(it.leftListingId, it.rightListingId).sorted().joinToString("|") }
            .sortedWith(compareByDescending<MergeReviewSuggestion> { it.confidence }.thenBy { it.leftListingId }.thenBy { it.rightListingId })
            .take(maxReviewSuggestions)
        return CatalogGroupingResult(groups, review, pairs.size, limitReached)
    }

    private fun selectCanonicalTitle(listings: List<ProviderListing>): String {
        val titles = listings.map { it.title.trim() }.filter(String::isNotBlank)
        if (titles.isEmpty()) return "Untitled"
        val english = listings.filter { it.languageCode?.startsWith("en", ignoreCase = true) == true }
            .map { it.title.trim() }
            .filter(String::isNotBlank)
        val pool = if (english.isNotEmpty()) english else titles
        return pool.groupingBy { it }.eachCount().entries
            .sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key.lowercase() }.thenBy { it.key })
            .first().key
    }
}
