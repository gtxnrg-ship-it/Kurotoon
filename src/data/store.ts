export const DATA_BUCKETS = [
  'catalog',
  'library',
  'progress',
  'settings',
  'repositories',
  'providerHealth',
] as const;

export type DataBucket = typeof DATA_BUCKETS[number];
export type DataStoreMode = 'indexeddb' | 'memory';

interface StoredEnvelope<T> {
  key: string;
  value: T;
  savedAt: string;
}

export interface DataStore {
  readonly mode: DataStoreMode;
  get<T>(bucket: DataBucket, key: string): Promise<T | undefined>;
  put<T>(bucket: DataBucket, key: string, value: T): Promise<void>;
  delete(bucket: DataBucket, key: string): Promise<void>;
  list<T>(bucket: DataBucket): Promise<Array<{ key: string; value: T; savedAt: string }>>;
  clear(bucket: DataBucket): Promise<void>;
  close(): void;
}

/**
 * Deterministic adapter for tests and environments without IndexedDB.
 * Its mode is explicitly "memory": callers must not mistake it for durable storage.
 */
export class MemoryDataStore implements DataStore {
  readonly mode = 'memory' as const;
  private readonly buckets = new Map<DataBucket, Map<string, StoredEnvelope<unknown>>>();

  constructor() {
    for (const bucket of DATA_BUCKETS) this.buckets.set(bucket, new Map());
  }

  async get<T>(bucket: DataBucket, key: string): Promise<T | undefined> {
    return this.buckets.get(bucket)?.get(key)?.value as T | undefined;
  }

  async put<T>(bucket: DataBucket, key: string, value: T): Promise<void> {
    this.buckets.get(bucket)?.set(key, { key, value, savedAt: new Date().toISOString() });
  }

  async delete(bucket: DataBucket, key: string): Promise<void> {
    this.buckets.get(bucket)?.delete(key);
  }

  async list<T>(bucket: DataBucket): Promise<Array<{ key: string; value: T; savedAt: string }>> {
    return [...(this.buckets.get(bucket)?.values() ?? [])] as Array<{ key: string; value: T; savedAt: string }>;
  }

  async clear(bucket: DataBucket): Promise<void> {
    this.buckets.get(bucket)?.clear();
  }

  close(): void {
    // No external resource to release.
  }
}

const DATABASE_NAME = 'kurotoon-data';
const DATABASE_VERSION = 1;

function openDatabase(factory: IDBFactory, databaseName: string): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    let request: IDBOpenDBRequest;
    try {
      request = factory.open(databaseName, DATABASE_VERSION);
    } catch (error) {
      reject(error);
      return;
    }

    request.onupgradeneeded = () => {
      const database = request.result;
      // Add stores without deleting existing ones: upgrades must preserve user data.
      for (const bucket of DATA_BUCKETS) {
        if (!database.objectStoreNames.contains(bucket)) {
          database.createObjectStore(bucket, { keyPath: 'key' });
        }
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error ?? new Error('Could not open Kurotoon storage.'));
    request.onblocked = () => reject(new Error('Kurotoon storage upgrade is blocked by another open tab.'));
  });
}

export class IndexedDbDataStore implements DataStore {
  readonly mode = 'indexeddb' as const;
  private readonly database: Promise<IDBDatabase>;

  constructor(factory: IDBFactory, databaseName = DATABASE_NAME) {
    this.database = openDatabase(factory, databaseName);
    void this.database.then(database => {
      database.onversionchange = () => database.close();
    }).catch(() => {
      // Each operation surfaces the open failure; the factory may choose a fallback.
    });
  }

  private async request<T>(
    bucket: DataBucket,
    mode: IDBTransactionMode,
    makeRequest: (store: IDBObjectStore) => IDBRequest<T>,
  ): Promise<T> {
    const database = await this.database;
    return new Promise<T>((resolve, reject) => {
      let result: T;
      let hasResult = false;
      let transaction: IDBTransaction;
      try {
        transaction = database.transaction(bucket, mode);
        const request = makeRequest(transaction.objectStore(bucket));
        request.onsuccess = () => {
          result = request.result;
          hasResult = true;
        };
        request.onerror = () => {
          // The transaction event is the single place that settles the promise.
        };
        transaction.oncomplete = () => {
          if (hasResult) resolve(result);
          else resolve(undefined as T);
        };
        transaction.onerror = () => reject(transaction.error ?? new Error('Kurotoon storage transaction failed.'));
        transaction.onabort = () => reject(transaction.error ?? new Error('Kurotoon storage transaction was aborted.'));
      } catch (error) {
        reject(error);
      }
    });
  }

  async get<T>(bucket: DataBucket, key: string): Promise<T | undefined> {
    const record = await this.request<StoredEnvelope<T> | undefined>(bucket, 'readonly', store => store.get(key));
    return record?.value;
  }

  async put<T>(bucket: DataBucket, key: string, value: T): Promise<void> {
    await this.request(bucket, 'readwrite', store => store.put({
      key,
      value,
      savedAt: new Date().toISOString(),
    } satisfies StoredEnvelope<T>));
  }

  async delete(bucket: DataBucket, key: string): Promise<void> {
    await this.request(bucket, 'readwrite', store => store.delete(key));
  }

  async list<T>(bucket: DataBucket): Promise<Array<{ key: string; value: T; savedAt: string }>> {
    const records = await this.request<Array<StoredEnvelope<T>>>(bucket, 'readonly', store => store.getAll());
    return (records ?? []).map(record => ({ key: record.key, value: record.value, savedAt: record.savedAt }));
  }

  async clear(bucket: DataBucket): Promise<void> {
    await this.request(bucket, 'readwrite', store => store.clear());
  }

  close(): void {
    void this.database.then(database => database.close()).catch(() => undefined);
  }
}

/**
 * Opens durable IndexedDB where available. If a browser blocks it or it is
 * unavailable, the returned store explicitly reports memory-only mode instead
 * of breaking the app. The UI should surface this mode before promising persistence.
 */
export async function openDataStore(options: {
  factory?: IDBFactory | null;
  databaseName?: string;
} = {}): Promise<DataStore> {
  let factory = options.factory;
  if (factory === undefined) {
    try {
      factory = typeof indexedDB === 'undefined' ? null : indexedDB;
    } catch {
      factory = null;
    }
  }

  if (factory) {
    const store = new IndexedDbDataStore(factory, options.databaseName ?? DATABASE_NAME);
    try {
      await store.get('settings', '__storage_probe__');
      return store;
    } catch {
      store.close();
    }
  }
  return new MemoryDataStore();
}

let defaultStorePromise: Promise<DataStore> | undefined;

export function getDefaultDataStore(): Promise<DataStore> {
  defaultStorePromise ??= openDataStore();
  return defaultStorePromise;
}
