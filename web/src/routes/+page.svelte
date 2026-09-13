<script lang="ts">
	import { resolve } from '$app/paths';
	import type { PathnameWithSearchOrHash } from '$app/types';
	import GuideFooter from '#lib/components/guide/GuideFooter.svelte';
	import GuideHeader from '#lib/components/guide/GuideHeader.svelte';
	import HelpSection from '#lib/components/guide/HelpSection.svelte';
	import HeroSection from '#lib/components/guide/HeroSection.svelte';
	import InstallSection from '#lib/components/guide/InstallSection.svelte';
	import ReleasesSection from '#lib/components/guide/ReleasesSection.svelte';
	import ScopeSection from '#lib/components/guide/ScopeSection.svelte';
	import VerifySection from '#lib/components/guide/VerifySection.svelte';
	import * as m from '#lib/paraglide/messages.js';
	import { localizeHref } from '#lib/paraglide/runtime.js';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();
	let latest = $derived(data.releases[0]);
</script>

<svelte:head>
	<title>{m.meta_title()}</title>
	<meta name="description" content={m.meta_description()} />
	<meta name="theme-color" content="#100d0a" />
</svelte:head>

<a
	href={resolve(localizeHref('/#main-content') as PathnameWithSearchOrHash)}
	class="sr-only z-[100] rounded-md bg-primary px-4 py-3 font-bold text-primary-foreground focus:not-sr-only focus:fixed focus:top-4 focus:left-4"
>
	{m.skip_to_content()}
</a>

<GuideHeader {latest} starCount={data.starCount} />

<main id="main-content">
	<HeroSection {latest} />
	<ScopeSection />
	<InstallSection {latest} />
	<VerifySection />
	<ReleasesSection releases={data.releases} releasesLive={data.releasesLive} />
	<HelpSection {latest} />
</main>

<GuideFooter />
