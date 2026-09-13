<script lang="ts">
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import type { Pathname } from '$app/types';
	import {
		CowboyHatIcon,
		Download04Icon,
		Github01Icon,
		LanguageCircleIcon,
		StarIcon
	} from '@hugeicons/core-free-icons';
	import { HugeiconsIcon } from '@hugeicons/svelte';
	import { Button } from '#lib/components/ui/button/index.js';
	import * as Select from '#lib/components/ui/select/index.js';
	import * as m from '#lib/paraglide/messages.js';
	import { getLocaleForUrl, localizeHref } from '#lib/paraglide/runtime.js';
	import { REPOSITORY_URL } from '#lib';
	import type { Release } from './types.js';

	let { latest, starCount }: { latest?: Release; starCount: number | null } = $props();

	const languages = [
		{ code: 'en', short: 'EN', flag: '🇬🇧', name: 'English' },
		{ code: 'vi', short: 'VI', flag: '🇻🇳', name: 'Tiếng Việt' },
		{ code: 'zh', short: 'ZH', flag: '🇨🇳', name: '简体中文' },
		{ code: 'jp', short: 'JP', flag: '🇯🇵', name: '日本語' },
		{ code: 'kr', short: 'KR', flag: '🇰🇷', name: '한국어' }
	] as const;

	let activeLocale = $derived(getLocaleForUrl(page.url));
	let languagePath = $derived(page.url.pathname + page.url.search + page.url.hash);
	let activeLanguage = $derived(
		languages.find((language) => language.code === activeLocale) ?? languages[0]
	);
	let formattedStarCount = $derived(
		starCount === null
			? null
			: new Intl.NumberFormat('en-US', { notation: 'compact', maximumFractionDigits: 1 }).format(
					starCount
				)
	);

	function changeLanguage(value: string) {
		const locale = languages.find((language) => language.code === value)?.code;

		if (!locale || locale === activeLocale) return;

		window.location.assign(localizeHref(languagePath, { locale }));
	}
</script>

<header class="sticky top-0 z-50 border-b border-border/70 bg-background/90 backdrop-blur-xl">
	<div
		class="mx-auto flex min-h-16 max-w-[1180px] items-center gap-2 px-4 sm:gap-4 sm:px-6 lg:px-8"
	>
		<a
			href={resolve(localizeHref('/') as Pathname)}
			class="group flex min-w-0 items-center gap-3"
			aria-label="FFW8"
		>
			<span class="brand-mark" aria-hidden="true">
				<HugeiconsIcon icon={CowboyHatIcon} strokeWidth={2.2} class="size-5" />
			</span>
			<span class="hidden min-w-0 sm:block">
				<strong
					class="block truncate text-sm font-black tracking-[0.09em] text-foreground uppercase"
				>
					{m.brand_name()}
				</strong>
				<span
					class="block truncate text-[0.68rem] font-semibold tracking-[0.14em] text-muted-foreground uppercase"
				>
					{m.brand_kicker()}
				</span>
			</span>
		</a>

		<nav class="ml-auto hidden items-center gap-1 lg:flex" aria-label="Primary">
			<Button href="#install" variant="ghost" size="sm">{m.nav_install()}</Button>
			<Button href="#verify" variant="ghost" size="sm">{m.nav_verify()}</Button>
			<Button href="#releases" variant="ghost" size="sm">{m.nav_releases()}</Button>
			<Button href="#help" variant="ghost" size="sm">{m.nav_help()}</Button>
		</nav>

		<div class="ml-auto flex items-center gap-2 lg:ml-3">
			<span class="mr-1 hidden text-muted-foreground md:inline-flex" aria-hidden="true">
				<HugeiconsIcon icon={LanguageCircleIcon} strokeWidth={2} class="size-4" />
			</span>
			<Select.Root type="single" value={activeLocale} onValueChange={changeLanguage}>
				<Select.Trigger
					size="sm"
					class="h-9 w-[6.3rem] rounded-md border-primary/30 bg-primary/10 font-extrabold text-foreground hover:bg-primary/15"
					aria-label={`${m.language_label()}: ${activeLanguage.name}`}
				>
					<Select.Value placeholder={`${activeLanguage.flag} ${activeLanguage.short}`} />
				</Select.Trigger>
				<Select.Content align="end" class="min-w-52 rounded-lg border border-border bg-popover p-1">
					{#each languages as language (language.code)}
						<Select.Item
							value={language.code}
							label={`${language.flag} ${language.short}`}
							class="rounded-md py-2.5"
						>
							<span class="text-base leading-none" aria-hidden="true">{language.flag}</span>
							<span class="min-w-0 flex-1 truncate font-semibold">{language.name}</span>
							<span class="text-xs font-black tracking-[0.12em] text-muted-foreground">
								{language.short}
							</span>
						</Select.Item>
					{/each}
				</Select.Content>
			</Select.Root>
		</div>

		{#if latest?.zipUrl}
			<Button
				href={latest.zipUrl}
				size="sm"
				class="hidden rounded-md bg-primary font-extrabold text-primary-foreground shadow-[0_0_24px_rgba(244,182,63,0.18)] hover:bg-[#ffd75a] md:inline-flex"
			>
				<HugeiconsIcon icon={Download04Icon} strokeWidth={2.2} data-icon="inline-start" />
				{m.nav_download()}
			</Button>
		{/if}

		<Button
			href={REPOSITORY_URL}
			target="_blank"
			rel="noreferrer"
			variant="outline"
			size="sm"
			class="h-9 rounded-md border-border bg-card/70 px-2.5 font-bold hover:border-primary/50 hover:bg-secondary sm:px-3"
			aria-label={starCount === null ? 'Star project on GitHub' : `${starCount} GitHub stars`}
			title={starCount === null ? 'Star project on GitHub' : `${starCount} GitHub stars`}
		>
			<HugeiconsIcon icon={Github01Icon} strokeWidth={2} data-icon="inline-start" />
			<span class="hidden xl:inline">Star</span>
			<HugeiconsIcon icon={StarIcon} strokeWidth={2} class="size-3.5 text-primary" />
			{#if formattedStarCount !== null}<span>{formattedStarCount}</span>{/if}
		</Button>
	</div>
</header>
