package app.kurotoon.native.domain

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.assertEquals
import org.junit.Test

class WorkIdentityEngineTest {
    @Test
    fun unicodeAndPunctuationNormalizeDeterministically() {
        assertEquals("one piece", WorkIdentityEngine.normalizeTitle("ＯＮＥ　ＰＩＥＣＥ!"))
        assertEquals("dont stop", WorkIdentityEngine.normalizeTitle("Don’t Stop"))
    }

    @Test
    fun titleAloneNeverAutoMerges() {
        val left = WorkIdentityCandidate("a", "Blue Star")
        val right = WorkIdentityCandidate("b", "Blue Star")
        val assessment = WorkIdentityEngine.assess(left, right)
        assertFalse(assessment.autoMerge)
        assertTrue(assessment.confidence < 0.90)
    }

    @Test
    fun globalCreatorAndPrimaryTitleCanAutoMerge() {
        val left = WorkIdentityCandidate("a", "Blue Star", globalCreatorIds = setOf("global:author:42"))
        val right = WorkIdentityCandidate("b", "The Blue Star", globalCreatorIds = setOf("global:author:42"))
        assertTrue(WorkIdentityEngine.assess(left, right).autoMerge)
    }

    @Test
    fun matchingExternalIdWinsOnlyWithoutContradiction() {
        val left = WorkIdentityCandidate("a", "A", externalIds = mapOf("mal" to "123", "anilist" to "77"))
        val matching = WorkIdentityCandidate("b", "Other title", externalIds = mapOf("mal" to "123", "anilist" to "77"))
        val conflict = WorkIdentityCandidate("c", "A", externalIds = mapOf("mal" to "123", "anilist" to "999"))
        assertTrue(WorkIdentityEngine.assess(left, matching).autoMerge)
        assertFalse(WorkIdentityEngine.assess(left, conflict).autoMerge)
    }

    @Test
    fun providerLocalCreatorIdsAreNotPartOfIdentityEvidence() {
        val left = WorkIdentityCandidate("a", "Blue Star")
        val right = WorkIdentityCandidate("b", "Blue Star")
        assertFalse(WorkIdentityEngine.assess(left, right).autoMerge)
    }
}
