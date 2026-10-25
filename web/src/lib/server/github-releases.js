/** @typedef {import('../components/guide/types.js').Release} Release */

export const REPOSITORY_API = 'https://api.github.com/repos/halu103/farfarwest-frostburn-modkit';
const REPOSITORY_PATH = '/halu103/farfarwest-frostburn-modkit/releases/';

/** Preserve configured query parameters instead of appending a second question mark. */
export function releasesApiUrl(configuredUrl = '') {
	const url = new URL(configuredUrl || `${REPOSITORY_API}/releases`);
	if (url.protocol !== 'https:') throw new Error('GitHub API URL must use HTTPS');
	url.searchParams.set('per_page', '100');
	return url.href;
}

/**
 * Releases are public. An expired optional token must not hide otherwise accessible downloads.
 * Only retry authentication rejection, not rate limiting or unrelated server failures.
 * @param {typeof fetch} fetcher
 * @param {string} url
 * @param {{token?: string}} options
 */
export async function fetchGithubPublicResource(fetcher, url, { token } = {}) {
	const headers = {
		Accept: 'application/vnd.github+json',
		'User-Agent': 'FFWFrostburn8-install-guide',
		'X-GitHub-Api-Version': '2022-11-28',
		...(token ? { Authorization: `Bearer ${token}` } : {})
	};
	const request = () =>
		fetcher(url, {
			headers,
			cache: 'no-store',
			signal: AbortSignal.timeout(10_000)
		});
	let response = await request();
	if (response.status === 401 && token) {
		delete headers.Authorization;
		response = await request();
	}
	return response;
}

/** @param {unknown} value */
function record(value) {
	return value !== null && typeof value === 'object' && !Array.isArray(value)
		? /** @type {Record<string, unknown>} */ (value)
		: null;
}

/** @param {unknown} value @param {'download/' | 'tag/'} kind */
function githubUrl(value, kind) {
	if (typeof value !== 'string') return null;
	try {
		const url = new URL(value);
		return url.protocol === 'https:' &&
			url.hostname === 'github.com' &&
			!url.port &&
			!url.username &&
			!url.password &&
			url.pathname.startsWith(`${REPOSITORY_PATH}${kind}`)
			? url.href
			: null;
	} catch {
		return null;
	}
}

/** @param {unknown} value */
function nonnegativeNumber(value) {
	return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : 0;
}

/** @param {unknown} value */
function asset(value) {
	const entry = record(value);
	const url = githubUrl(entry?.browser_download_url, 'download/');
	return entry && typeof entry.name === 'string' && url
		? {
				name: entry.name,
				url,
				size: nonnegativeNumber(entry.size),
				downloadCount: nonnegativeNumber(entry.download_count)
			}
		: null;
}

/** @param {string} name @param {'zip' | 'installer' | 'uninstaller'} kind */
function matchesAsset(name, kind) {
	// Each download has a distinct role; an uninstaller must never become the setup link.
	if (/(?:^|[-_.])(source|symbols|debug)(?:[-_.]|$)/i.test(name)) return false;
	if (kind === 'uninstaller') {
		return /(?:^|[-_.])FFWFrostburn8(?:[-_.][a-z0-9._-]+)?-Uninstall\.exe$/i.test(name);
	}
	if (/(?:^|[-_.])uninstall(?:[-_.]|$)/i.test(name)) return false;
	return kind === 'zip'
		? /(?:^|[-_.])FFWFrostburn8(?:[-_.][a-z0-9._-]+)?-Windows-x64\.zip$/i.test(name)
		: /(?:^|[-_.])FFWFrostburn8(?:[-_.][a-z0-9._-]+)?-Setup\.exe$/i.test(name);
}

/** @param {unknown} value @returns {Release | null} */
function normalizeRelease(value) {
	const release = record(value);
	if (!release || release.draft === true || typeof release.tag_name !== 'string') return null;
	const pageUrl = githubUrl(release.html_url, 'tag/');
	if (!release.tag_name.trim() || !pageUrl || !Array.isArray(release.assets)) return null;

	const assets = release.assets.map(asset).filter((entry) => entry !== null);
	/** @param {'zip' | 'installer' | 'uninstaller'} kind */
	const findDownload = (kind) => {
		const friendlyName =
			kind === 'zip'
				? 'FFWFrostburn8-Windows-x64.zip'
				: kind === 'installer'
					? 'FFWFrostburn8-Setup.exe'
					: 'FFWFrostburn8-Uninstall.exe';
		return (
			assets.find((entry) => entry.name === friendlyName) ??
			assets
				.filter((entry) => matchesAsset(entry.name, kind))
				.sort((a, b) => a.name.localeCompare(b.name))[0] ??
			null
		);
	};
	const zip = findDownload('zip');
	const installer = findDownload('installer');
	const uninstaller = findDownload('uninstaller');
	if (!zip && !installer) return null;
	const checksum = [installer, zip].flatMap((download) =>
		download
			? assets.filter((entry) =>
					[`${download.name}.sha256.txt`, `${download.name}.sha256`].some(
						(name) => entry.name.toLowerCase() === name.toLowerCase()
					)
				)
			: []
	)[0];
	const publishedAt =
		typeof release.published_at === 'string' && Number.isFinite(Date.parse(release.published_at))
			? release.published_at
			: '1970-01-01T00:00:00Z';

	return {
		tag: release.tag_name,
		name: typeof release.name === 'string' && release.name ? release.name : release.tag_name,
		publishedAt,
		pageUrl,
		prerelease: release.prerelease === true,
		compatibility: release.tag_name,
		downloadCount: (zip?.downloadCount ?? 0) + (installer?.downloadCount ?? 0),
		zipUrl: zip?.url ?? null,
		zipSize: zip?.size ?? null,
		installerUrl: installer?.url ?? null,
		installerSize: installer?.size ?? null,
		uninstallerUrl: uninstaller?.url ?? null,
		uninstallerSize: uninstaller?.size ?? null,
		checksumUrl: checksum?.url ?? null
	};
}

/** @param {unknown} payload @returns {Release[]} */
export function normalizeGithubReleases(payload) {
	if (!Array.isArray(payload)) throw new Error('GitHub Releases response must be a list');
	const releases = payload.map(normalizeRelease).filter((release) => release !== null);
	releases.sort((a, b) => Date.parse(b.publishedAt) - Date.parse(a.publishedAt));
	return releases.filter(
		(release, index) => releases.findIndex((candidate) => candidate.tag === release.tag) === index
	);
}
