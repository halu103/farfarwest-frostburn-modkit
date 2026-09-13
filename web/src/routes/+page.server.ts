import { env } from '$env/dynamic/private';
import type { Release } from '#lib/components/guide/types.js';
import type { PageServerLoad } from './$types';

const REPOSITORY_API = 'https://api.github.com/repos/halu103/farfarwest-frostburn-modkit';
const RELEASES_API = `${env.PRIVATE_GITHUB_API_URL || `${REPOSITORY_API}/releases`}?per_page=20`;

type GithubAsset = {
	name: string;
	browser_download_url: string;
	size: number;
	download_count: number;
};

type GithubRelease = {
	tag_name: string;
	name: string | null;
	published_at: string | null;
	html_url: string;
	draft: boolean;
	prerelease: boolean;
	assets: GithubAsset[];
};

type GithubRepository = {
	stargazers_count: number;
};

function githubHeaders() {
	const headers: Record<string, string> = {
		Accept: 'application/vnd.github+json',
		'User-Agent': 'FFWFrostburn8-install-guide',
		'X-GitHub-Api-Version': '2022-11-28'
	};

	if (env.PRIVATE_GITHUB_TOKEN) {
		headers.Authorization = `Bearer ${env.PRIVATE_GITHUB_TOKEN}`;
	}

	return headers;
}

function findAsset(assets: GithubAsset[], name: string) {
	return assets.find((asset) => asset.name === name) ?? null;
}

function normalizeRelease(release: GithubRelease): Release {
	const zip = findAsset(release.assets, 'FFWFrostburn8-Windows-x64.zip');

	const installer = findAsset(release.assets, 'FFWFrostburn8-Setup.exe');

	const checksum = findAsset(release.assets, 'FFWFrostburn8-Windows-x64.zip.sha256.txt');

	const downloadCount = (zip?.download_count ?? 0) + (installer?.download_count ?? 0);

	return {
		tag: release.tag_name,
		name: release.name || release.tag_name,
		publishedAt: release.published_at || '1970-01-01T00:00:00Z',
		pageUrl: release.html_url,
		prerelease: release.prerelease,
		compatibility: release.tag_name ?? null,

		downloadCount,

		zipUrl: zip?.browser_download_url ?? null,
		zipSize: zip?.size ?? null,

		installerUrl: installer?.browser_download_url ?? null,
		installerSize: installer?.size ?? null,

		checksumUrl: checksum?.browser_download_url ?? null
	};
}

export const load: PageServerLoad = async ({ fetch, setHeaders }) => {
	setHeaders({
		'cache-control': 'public, max-age=300, s-maxage=3600, stale-while-revalidate=86400'
	});

	const starCountPromise = fetch(REPOSITORY_API, { headers: githubHeaders() })
		.then(async (response) => {
			if (!response.ok) return null;

			const repository = (await response.json()) as GithubRepository;
			return Number.isFinite(repository.stargazers_count) ? repository.stargazers_count : null;
		})
		.catch(() => null);

	try {
		const response = await fetch(RELEASES_API, {
			headers: githubHeaders()
		});

		if (!response.ok) {
			throw new Error(`GitHub Releases returned ${response.status} ${response.statusText}`);
		}

		const githubReleases = (await response.json()) as GithubRelease[];

		const releases = githubReleases
			.filter((release) => !release.draft)
			.map(normalizeRelease)
			.filter((release) => release.zipUrl !== null || release.installerUrl !== null)
			.sort((a, b) => new Date(b.publishedAt).getTime() - new Date(a.publishedAt).getTime());

		if (releases.length === 0) {
			throw new Error('No downloadable releases found');
		}

		return {
			releases,
			releasesLive: true,
			starCount: await starCountPromise
		};
	} catch (error) {
		console.error('Failed to fetch GitHub releases:', error);

		return {
			releases: [],
			releasesLive: false,
			starCount: await starCountPromise
		};
	}
};
