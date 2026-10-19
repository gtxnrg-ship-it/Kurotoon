import { createDataRepositories } from './repositories';
import { getDefaultDataStore } from './store';

export type KurotoonDataServices = ReturnType<typeof createDataRepositories>;

let servicesPromise: Promise<KurotoonDataServices> | undefined;

/**
 * Shared application-level access to local repositories. UI screens consume
 * services through this seam rather than opening IndexedDB or localStorage.
 */
export function getDataServices(): Promise<KurotoonDataServices> {
  servicesPromise ??= getDefaultDataStore().then(createDataRepositories);
  return servicesPromise;
}
