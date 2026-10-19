import type { ComicProvider } from '../domain/provider';
import { ProviderRequestError } from '../domain/provider';
import { mangaDexProvider } from './mangadex';

/**
 * Runtime lookup for source adapters. This deliberately registers executable
 * adapters, not entries parsed from a repository JSON index. Community
 * extensions may register here only through a future, validated runtime.
 */
export class ProviderRegistry {
  private readonly providers = new Map<string, ComicProvider>();
  private readonly listeners = new Set<() => void>();

  constructor(initialProviders: ComicProvider[] = []) {
    for (const provider of initialProviders) this.register(provider);
  }

  register(provider: ComicProvider): void {
    const id = typeof provider?.id === 'string' ? provider.id.trim() : '';
    if (!id) throw new Error('A source adapter must have a non-empty ID.');
    if (this.providers.has(id)) throw new Error('A source adapter with ID "' + id + '" is already registered.');
    this.providers.set(id, provider);
    this.notify();
  }

  /** Replace an adapter explicitly during an approved extension update. */
  replace(provider: ComicProvider): void {
    const id = typeof provider?.id === 'string' ? provider.id.trim() : '';
    if (!id) throw new Error('A source adapter must have a non-empty ID.');
    this.providers.set(id, provider);
    this.notify();
  }

  unregister(providerId: string): boolean {
    const removed = this.providers.delete(providerId);
    if (removed) this.notify();
    return removed;
  }

  get(providerId: string): ComicProvider | undefined {
    return this.providers.get(providerId);
  }

  require(providerId: string): ComicProvider {
    const provider = this.get(providerId);
    if (provider) return provider;
    throw new ProviderRequestError({
      providerId,
      code: 'unsupported',
      message: 'The source adapter "' + providerId + '" is not currently available. Re-enable or reinstall that source.',
      retryable: false,
    });
  }

  list(): ComicProvider[] {
    return [...this.providers.values()].sort((a, b) => a.id.localeCompare(b.id));
  }

  subscribe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  }

  private notify(): void {
    for (const listener of this.listeners) listener();
  }
}

export const providerRegistry = new ProviderRegistry([mangaDexProvider]);

export function formatProviderName(providerId: string): string {
  const displayName = providerRegistry.get(providerId)?.displayName;
  if (displayName) return displayName;
  return providerId
    .split(/[-_.\s]+/u)
    .filter(Boolean)
    .map(word => word.charAt(0).toLocaleUpperCase() + word.slice(1))
    .join(' ') || 'Unknown source';
}
