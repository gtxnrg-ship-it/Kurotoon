package app.kurotoon.native.domain

import java.text.Normalizer
import java.util.Locale

/**
 * Conservative, deterministic identity scoring. An identity score is evidence, not proof.
 * Editions, languages and provider listings remain separate even when they belong to one Work.
 */
object WorkIdentityEngine {
    fun normalizeTitle(value: String): String = Normalizer.normalize(value, Normalizer.Form.NFKC)
        .lowercase(Locale.ROOT)
        .replace(Regex("[’']"), "")
        .replace(Regex("[^\\p{L}\\p{N}]+"), " ")
        .trim()
        .replace(Regex("\\s+"), " ")

    fun comparisonTitle(value: String): String =
        normalizeTitle(value).replace(Regex("^(?:the|a|an)\\s+"), "")

    fun assess(left: WorkIdentityCandidate, right: WorkIdentityCandidate): WorkMatchAssessment {
        if (left.stableKey == right.stableKey) {
            return WorkMatchAssessment(1.0, true, listOf("same stable provider listing identity"))
        }

        val leftIds = normalizedExternalIds(left.externalIds)
        val rightIds = normalizedExternalIds(right.externalIds)
        val sharedNamespaces = leftIds.keys.intersect(rightIds.keys)
        val contradictoryNamespaces = sharedNamespaces.filter { leftIds[it] != rightIds[it] }
        if (contradictoryNamespaces.isNotEmpty()) {
            return WorkMatchAssessment(
                confidence = 0.0,
                autoMerge = false,
                reasons = listOf("contradictory external identifiers: ${contradictoryNamespaces.sorted().joinToString()}"),
            )
        }

        val matchingIds = sharedNamespaces.filter { leftIds[it] == rightIds[it] && leftIds[it].orEmpty().isNotBlank() }
        if (matchingIds.isNotEmpty()) {
            return WorkMatchAssessment(0.99, true, listOf("matching external identifier namespace: ${matchingIds.sorted().joinToString()}"))
        }

        val leftPrimary = normalizeTitle(left.title)
        val rightPrimary = normalizeTitle(right.title)
        val exactPrimary = leftPrimary.isNotBlank() &&
            (leftPrimary == rightPrimary || comparisonTitle(left.title) == comparisonTitle(right.title))
        val leftTitles = titleSet(left)
        val rightTitles = titleSet(right)
        val titleOrAliasOverlap = leftTitles.intersect(rightTitles).isNotEmpty()
        val creatorOverlap = left.globalCreatorIds.map(::normalizeIdentity)
            .filter(String::isNotBlank)
            .toSet()
            .intersect(right.globalCreatorIds.map(::normalizeIdentity).filter(String::isNotBlank).toSet())
            .isNotEmpty()

        val reasons = mutableListOf<String>()
        var confidence = 0.05
        if (exactPrimary) {
            confidence += 0.65
            reasons += "normalized primary titles match"
        } else if (titleOrAliasOverlap) {
            confidence += 0.50
            reasons += "title or alias overlaps"
        }
        if (creatorOverlap) {
            confidence += 0.25
            reasons += "globally comparable creator identity matches"
        }
        if (reasons.isEmpty()) reasons += "no strong identity evidence"

        confidence = confidence.coerceAtMost(0.95).let { (it * 100).toInt() / 100.0 }
        val autoMerge = exactPrimary && creatorOverlap && confidence >= 0.90
        return WorkMatchAssessment(confidence, autoMerge, reasons)
    }

    private fun titleSet(candidate: WorkIdentityCandidate): Set<String> =
        (listOf(candidate.title) + candidate.aliases)
            .flatMap { listOf(normalizeTitle(it), comparisonTitle(it)) }
            .filter(String::isNotBlank)
            .toSet()

    private fun normalizedExternalIds(ids: Map<String, String>): Map<String, String> =
        ids.entries.associate { normalizeIdentity(it.key) to normalizeIdentity(it.value) }
            .filterKeys(String::isNotBlank)
            .filterValues(String::isNotBlank)

    private fun normalizeIdentity(value: String): String =
        Normalizer.normalize(value, Normalizer.Form.NFKC).trim().lowercase(Locale.ROOT)
}
