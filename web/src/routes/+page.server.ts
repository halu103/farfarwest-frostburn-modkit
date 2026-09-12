import { PRIVATE_GITHUB_API_URL, PRIVATE_GITHUB_TOKEN } from '$env/static/private';
import type { PageServerLoad } from './$types';

const RELEASES_API = `${PRIVATE_GITHUB_API_URL}?per_page=20`;

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

type Release = {
	tag: string;
	name: string;
	publishedAt: string;
	pageUrl: string;
	prerelease: boolean;
	compatibility: string | null;
	zipUrl: string | null;
	zipSize: number | null;
	installerUrl: string | null;
	installerSize: number | null;
	checksumUrl: string | null;
	downloadCount: number | null;
};

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

	try {
		const response = await fetch(RELEASES_API, {
			headers: {
				Accept: 'application/vnd.github+json',
				'User-Agent': 'FFWFrostburn8-install-guide',
				'X-GitHub-Api-Version': '2022-11-28',
				Authorization: `Bearer ${PRIVATE_GITHUB_TOKEN}`
			}
		});

		if (!response.ok) {
			throw new Error(`GitHub Releases returned ${response.status} ${response.statusText}`);
		}

		const githubReleases = (await response.json()) as GithubRelease[];

		console.log('GitHub API response:', JSON.stringify(githubReleases, null, 2));

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
			releasesLive: true
		};
	} catch (error) {
		console.error('Failed to fetch GitHub releases:', error);

		return {
			releases: [],
			releasesLive: false
		};
	}
};
