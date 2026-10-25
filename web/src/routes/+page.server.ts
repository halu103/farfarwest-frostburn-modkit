import { env } from '$env/dynamic/private';
import {
	fetchGithubPublicResource,
	normalizeGithubReleases,
	REPOSITORY_API,
	releasesApiUrl
} from '#lib/server/github-releases.js';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ fetch, setHeaders }) => {
	const starCountPromise = fetchGithubPublicResource(fetch, REPOSITORY_API, {
		token: env.PRIVATE_GITHUB_TOKEN
	})
		.then(async (response) => {
			if (!response.ok) return null;

			const repository = await response.json();
			return typeof repository?.stargazers_count === 'number' &&
				Number.isFinite(repository.stargazers_count)
				? repository.stargazers_count
				: null;
		})
		.catch(() => null);

	try {
		const response = await fetchGithubPublicResource(
			fetch,
			releasesApiUrl(env.PRIVATE_GITHUB_API_URL),
			{ token: env.PRIVATE_GITHUB_TOKEN }
		);

		if (!response.ok) {
			throw new Error(`GitHub Releases returned ${response.status} ${response.statusText}`);
		}

		const releases = normalizeGithubReleases(await response.json());

		if (releases.length === 0) {
			throw new Error('No downloadable releases found');
		}
		// Browser reloads revalidate; published releases no longer sit behind a 24-hour stale window.
		setHeaders({
			'cache-control': 'public, max-age=0, s-maxage=60, stale-while-revalidate=60'
		});

		return {
			releases,
			releasesLive: true,
			starCount: await starCountPromise
		};
	} catch (error) {
		console.error('Failed to fetch GitHub releases:', error);
		// Do not cache an API/rate-limit failure as the current release list.
		setHeaders({ 'cache-control': 'no-store' });

		return {
			releases: [],
			releasesLive: false,
			starCount: await starCountPromise
		};
	}
};
