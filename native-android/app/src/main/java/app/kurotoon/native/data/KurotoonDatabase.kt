package app.kurotoon.android.data

import android.content.Context
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.Upsert
import kotlinx.coroutines.flow.Flow

@Entity(tableName = "works", indices = [Index("normalizedTitle")])
data class WorkEntity(
    @PrimaryKey val workId: String,
    val canonicalTitle: String,
    val normalizedTitle: String,
    val createdAtEpochMillis: Long,
    val updatedAtEpochMillis: Long,
    val userTitleOverride: String? = null,
)

@Entity(tableName = "provider_listings", indices = [Index("workId"), Index("providerId")])
data class ProviderListingEntity(
    @PrimaryKey val listingKey: String,
    val workId: String?,
    val providerId: String,
    val providerWorkId: String,
    val sourceUrl: String,
    val title: String,
    val languageCode: String?,
    val coverUrl: String?,
    val lastVerifiedAtEpochMillis: Long?,
)

@Entity(tableName = "library_entries", indices = [Index("workId")])
data class LibraryEntryEntity(
    @PrimaryKey val entryId: String,
    val workId: String,
    val preferredListingKey: String?,
    val status: String,
    val categoriesJson: String,
    val addedAtEpochMillis: Long,
    val updatedAtEpochMillis: Long,
)

@Entity(tableName = "reading_progress", indices = [Index("workId"), Index("listingKey")])
data class ReadingProgressEntity(
    @PrimaryKey val progressKey: String,
    val workId: String,
    val listingKey: String,
    val providerChapterId: String,
    val chapterLabel: String?,
    val pageIndex: Int,
    val scrollRatio: Float?,
    val updatedAtEpochMillis: Long,
)

@Entity(tableName = "provider_configs")
data class ProviderConfigEntity(
    @PrimaryKey val providerId: String,
    val enabled: Boolean,
    val sourceKind: String,
    val repositoryUrl: String?,
    val version: String?,
    val lastHealthCheckEpochMillis: Long?,
    val lastHealthMessage: String?,
)

@Dao
interface KurotoonDao {
    @Upsert suspend fun upsertWork(work: WorkEntity)
    @Upsert suspend fun upsertListings(listings: List<ProviderListingEntity>)
    @Upsert suspend fun upsertLibraryEntry(entry: LibraryEntryEntity)
    @Upsert suspend fun upsertProgress(progress: ReadingProgressEntity)
    @Upsert suspend fun upsertProviderConfig(config: ProviderConfigEntity)

    @Query("SELECT * FROM works WHERE workId = :workId LIMIT 1")
    suspend fun getWork(workId: String): WorkEntity?

    @Query("SELECT * FROM library_entries ORDER BY updatedAtEpochMillis DESC")
    fun observeLibrary(): Flow<List<LibraryEntryEntity>>

    @Query("SELECT * FROM reading_progress WHERE workId = :workId ORDER BY updatedAtEpochMillis DESC LIMIT 1")
    suspend fun getLatestProgress(workId: String): ReadingProgressEntity?

    @Query("SELECT * FROM provider_configs ORDER BY providerId")
    fun observeProviderConfigs(): Flow<List<ProviderConfigEntity>>

    @Query("DELETE FROM provider_listings WHERE lastVerifiedAtEpochMillis IS NOT NULL AND lastVerifiedAtEpochMillis < :olderThanEpochMillis")
    suspend fun pruneOldProviderListings(olderThanEpochMillis: Long): Int
}

/**
 * User-owned library and progress live separately from disposable provider data.
 * No cascade rule allows a cache cleanup to erase user data accidentally.
 */
@Database(
    entities = [
        WorkEntity::class,
        ProviderListingEntity::class,
        LibraryEntryEntity::class,
        ReadingProgressEntity::class,
        ProviderConfigEntity::class,
    ],
    version = 1,
    exportSchema = false,
)
abstract class KurotoonDatabase : RoomDatabase() {
    abstract fun kurotoonDao(): KurotoonDao

    companion object {
        @Volatile private var instance: KurotoonDatabase? = null

        fun get(context: Context): KurotoonDatabase = instance ?: synchronized(this) {
            instance ?: Room.databaseBuilder(
                context.applicationContext,
                KurotoonDatabase::class.java,
                "kurotoon-native.db",
            ).build().also { instance = it }
        }
    }
}
