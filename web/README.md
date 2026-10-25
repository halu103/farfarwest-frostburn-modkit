# FFWFrostburn8 download and installation website

Production: <https://farfarwest-frostburn-modkit.vercel.app/>.
This SvelteKit app is deployed with the Vercel adapter. Changing local files
does **not** change production until the new source is deployed.

## Local development and checks

Use Node.js 22+ and pnpm 10. Copy `.env.example` to `.env` and set the public
repository/support links. A GitHub token is optional; never commit it or put it
in a `PUBLIC_` variable. No commercial game files are needed to build this site.

```sh
pnpm install --frozen-lockfile
pnpm test
pnpm check
pnpm build
pnpm dev
```

## Release discovery

The server reads the repository's public GitHub Releases API. It shows up to
100 published releases, including legacy and prerelease entries, newest first.
Drafts are excluded. A release must contain an identifiable Windows player ZIP
or Setup EXE; source archives and Uninstall EXEs are not mistaken for installers.
Standalone, game-version-qualified Setup files are supported: no bundle ZIP is
required. Download URLs come from GitHub's actual asset metadata.

Successful pages require browser revalidation and allow the CDN to cache for
60 seconds, with a further 60-second stale refresh window. Failed requests are
not cached and show a direct GitHub Releases link. GitHub rate limits or API
outages can still prevent live fetching. An optional server-only
`PRIVATE_GITHUB_TOKEN` increases the authenticated API allowance.

`PRIVATE_GITHUB_API_URL` is optional and defaults to this repository's releases
endpoint. Existing query parameters are preserved; `per_page` is set to 100.
The token and API requests stay server-side.

## Publish and verify

1. Publish the mod release on GitHub and upload its standalone Setup/Uninstall
   EXEs and checksums. A source commit alone does not create a downloadable
   release. Preserve the historical `legacy-v1.2.3` tag and its assets.
2. Review and push the website changes to the branch connected to Vercel, or
   deploy them through your existing Vercel project. Use `web` as Root Directory,
   `pnpm build` as Build Command, and the Vercel/SvelteKit framework settings.
3. Set the `.env.example` variables in Vercel's environment configuration.
   Keep `PRIVATE_GITHUB_TOKEN`, if used, server-only. Redeploy after changing
   environment variables.
4. Check that the new deployment is assigned to the production domain. Reload
   the page and confirm `legacy-v1.2.3` appears with its actual long Setup URL.
   After the official release is uploaded, check that its actual tag appears
   newest and the Setup URL downloads the correct v1.2.3 EXE.

If the site still displays only v1.2.2, verify that Vercel deployed the commit
containing this release parser, not merely that GitHub contains a newer mod
release. The older parser silently excluded version-qualified asset names.
