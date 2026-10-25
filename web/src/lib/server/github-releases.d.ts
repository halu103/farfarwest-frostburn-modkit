import type { Release } from '../components/guide/types.js';

export const REPOSITORY_API: string;
export function releasesApiUrl(configuredUrl?: string): string;
export function fetchGithubPublicResource(
	fetcher: typeof fetch,
	url: string,
	options?: { token?: string }
): Promise<Response>;
export function normalizeGithubReleases(payload: unknown): Release[];
