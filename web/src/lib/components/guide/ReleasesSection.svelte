<script lang="ts">
	import { page } from '$app/state';
	import {
		Clock01Icon,
		Download02Icon,
		ExternalLinkIcon,
		FileZipIcon,
		GameController02Icon,
		ShieldCheckIcon,
		WindowsNewIcon
	} from '@hugeicons/core-free-icons';
	import { HugeiconsIcon } from '@hugeicons/svelte';
	import { Badge } from '#lib/components/ui/badge/index.js';
	import { Button } from '#lib/components/ui/button/index.js';
	import * as Card from '#lib/components/ui/card/index.js';
	import { Separator } from '#lib/components/ui/separator/index.js';
	import * as m from '#lib/paraglide/messages.js';
	import { getLocaleForUrl } from '#lib/paraglide/runtime.js';
	import type { Release } from './types.js';

	let { releases, releasesLive }: { releases: Release[]; releasesLive: boolean } = $props();

	const dateLocales: Record<string, string> = {
		en: 'en-US',
		vi: 'vi-VN',
		zh: 'zh-CN',
		jp: 'ja-JP',
		kr: 'ko-KR'
	};

	let activeLocale = $derived(getLocaleForUrl(page.url));

	function formatDate(value: string) {
		return new Intl.DateTimeFormat(dateLocales[activeLocale] ?? 'en-US', {
			year: 'numeric',
			month: 'short',
			day: 'numeric'
		}).format(new Date(value));
	}

	function formatSize(bytes: number | null) {
		if (!bytes) return '';
		return `${(bytes / 1_000_000).toFixed(1)} MB`;
	}
</script>

<section id="releases" class="section-shell scroll-mt-24" aria-labelledby="releases-title">
	<div class="flex flex-col justify-between gap-6 lg:flex-row lg:items-end">
		<div class="section-heading mb-0">
			<p class="section-kicker">{m.releases_kicker()}</p>
			<h2 id="releases-title">{m.releases_title()}</h2>
			<p>{m.releases_description()}</p>
		</div>
		<Badge
			variant="outline"
			class="w-fit rounded-md border-border bg-card px-3 py-1 text-muted-foreground"
		>
			<span
				class={`mr-1 size-1.5 rounded-full ${releasesLive ? 'bg-[#a8e646]' : 'bg-primary'}`}
				aria-hidden="true"
			></span>
			{releasesLive ? m.release_live() : m.release_fallback()}
		</Badge>
	</div>

	<div class="mt-10 grid gap-5">
		{#each releases as release, index (release.tag)}
			<Card.Root
				class={index === 0
					? 'release-card latest-release rounded-xl border border-primary/45 bg-card shadow-[0_22px_70px_rgba(244,182,63,0.08)]'
					: 'release-card rounded-xl border border-border bg-card/75'}
			>
				<Card.Header class="gap-4 md:grid-cols-[1fr_auto] md:items-start">
					<div>
						<div class="flex flex-wrap items-center gap-2">
							<Card.Title class="font-mono text-2xl font-black text-foreground"
								>{release.tag}</Card.Title
							>
							<Badge
								class={index === 0
									? 'rounded-md bg-primary text-primary-foreground'
									: 'rounded-md bg-secondary text-secondary-foreground'}
							>
								{index === 0 ? m.release_latest() : m.release_previous()}
							</Badge>
							{#if release.prerelease}
								<Badge variant="outline" class="rounded-md border-[#3dd6c5]/35 text-[#67dace]">
									{m.release_prerelease()}
								</Badge>
							{/if}
						</div>
						<div class="mt-3 flex flex-wrap gap-x-6 gap-y-2 text-sm text-muted-foreground">
							<span class="inline-flex items-center gap-2">
								<HugeiconsIcon icon={Clock01Icon} strokeWidth={2} class="size-4" />
								{m.release_published({ date: formatDate(release.publishedAt) })}
							</span>
							<span class="inline-flex items-center gap-2">
								<HugeiconsIcon icon={GameController02Icon} strokeWidth={2} class="size-4" />
								{m.release_compatibility()}: {release.compatibility ??
									m.release_compatibility_unknown()}
							</span>
						</div>
					</div>
					<Button
						href={release.pageUrl}
						target="_blank"
						rel="noreferrer"
						variant="ghost"
						size="sm"
						class="w-fit rounded-md"
					>
						{m.release_notes()}
						<HugeiconsIcon icon={ExternalLinkIcon} strokeWidth={2} data-icon="inline-end" />
					</Button>
				</Card.Header>
				<Separator class="bg-border/60" />
				<Card.Content class="flex flex-wrap gap-3 pt-1">
					{#if release.zipUrl}
						<Button
							href={release.zipUrl}
							variant={index === 0 ? 'default' : 'secondary'}
							class="rounded-md font-bold"
						>
							<HugeiconsIcon icon={FileZipIcon} strokeWidth={2} data-icon="inline-start" />
							{m.release_bundle()}
							{#if release.zipSize}<span class="opacity-65">· {formatSize(release.zipSize)}</span
								>{/if}
						</Button>
					{/if}
					{#if release.installerUrl}
						<Button
							href={release.installerUrl}
							variant="outline"
							class="rounded-md border-border bg-background/30 font-bold"
						>
							<HugeiconsIcon icon={WindowsNewIcon} strokeWidth={2} data-icon="inline-start" />
							{m.release_installer()}
							{#if release.installerSize}<span class="opacity-65"
									>· {formatSize(release.installerSize)}</span
								>{/if}
						</Button>
					{/if}
					{#if release.checksumUrl}
						<Button
							href={release.checksumUrl}
							variant="ghost"
							class="rounded-md text-muted-foreground"
						>
							<HugeiconsIcon icon={ShieldCheckIcon} strokeWidth={2} data-icon="inline-start" />
							{m.release_checksum()}
						</Button>
					{/if}

					{#if release.downloadCount !== null}
						<span
							class="ml-auto inline-flex h-9 items-center gap-1.5 px-3 text-sm font-medium text-muted-foreground"
						>
							<HugeiconsIcon icon={Download02Icon} strokeWidth={2} class="size-4" />
							{release.downloadCount}
							{m.release_downloads()}
						</span>
					{/if}
				</Card.Content>
			</Card.Root>
		{/each}
	</div>
</section>
