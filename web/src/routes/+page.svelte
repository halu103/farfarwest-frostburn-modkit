<script lang="ts">
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import type { Pathname, PathnameWithSearchOrHash } from '$app/types';
	import { HugeiconsIcon } from '@hugeicons/svelte';
	import {
		Alert02Icon,
		ArrowRight01Icon,
		BookOpen02Icon,
		CheckmarkCircle02Icon,
		Clock01Icon,
		CodeIcon,
		ComputerCheckIcon,
		CowboyHatIcon,
		Download04Icon,
		ExternalLinkIcon,
		FileZipIcon,
		FolderOpenIcon,
		GameController02Icon,
		Github01Icon,
		InstallingUpdates01Icon,
		LanguageCircleIcon,
		PackageCheckIcon,
		PlayIcon,
		ShieldCheckIcon,
		UserGroup02Icon,
		WindowsNewIcon,
		Download02Icon
	} from '@hugeicons/core-free-icons';
	import * as Accordion from '#lib/components/ui/accordion/index.js';
	import * as Alert from '#lib/components/ui/alert/index.js';
	import { Badge } from '#lib/components/ui/badge/index.js';
	import { Button } from '#lib/components/ui/button/index.js';
	import * as Card from '#lib/components/ui/card/index.js';
	import * as Select from '#lib/components/ui/select/index.js';
	import { Separator } from '#lib/components/ui/separator/index.js';
	import * as m from '#lib/paraglide/messages.js';
	import { getLocaleForUrl, localizeHref } from '#lib/paraglide/runtime.js';
	import type { PageData } from './$types';
	import { REPOSITORY_URL } from '#lib';

	let { data }: { data: PageData } = $props();

	const allReleasesUrl = `${REPOSITORY_URL}/releases`;

	const languages = [
		{ code: 'en', short: 'EN', flag: '🇬🇧', name: 'English' },
		{ code: 'vi', short: 'VI', flag: '🇻🇳', name: 'Tiếng Việt' },
		{ code: 'zh', short: 'ZH', flag: '🇨🇳', name: '简体中文' },
		{ code: 'jp', short: 'JP', flag: '🇯🇵', name: '日本語' },
		{ code: 'kr', short: 'KR', flag: '🇰🇷', name: '한국어' }
	] as const;

	const dateLocales: Record<string, string> = {
		en: 'en-US',
		vi: 'vi-VN',
		zh: 'zh-CN',
		jp: 'jp-JP',
		kr: 'kr-KR'
	};

	const inviteSlots = [2, 3, 4, 5, 6, 7, 8];

	let activeLocale = $derived(getLocaleForUrl(page.url));

	let latest = $derived(data.releases[0]);
	let languagePath = $derived(page.url.pathname + page.url.search + page.url.hash);
	let activeLanguage = $derived(
		languages.find((language) => language.code === activeLocale) ?? languages[0]
	);

	function changeLanguage(value: string) {
		const locale = languages.find((language) => language.code === value)?.code;

		if (!locale || locale === activeLocale) return;

		window.location.assign(localizeHref(languagePath, { locale }));
	}

	let quickSteps = $derived([
		m.quick_step_1(),
		m.quick_step_2(),
		m.quick_step_3(),
		m.quick_step_4()
	]);

	let hostPoints = $derived([m.host_point_1(), m.host_point_2(), m.host_point_3()]);

	let guestPoints = $derived([m.guest_point_1(), m.guest_point_2(), m.guest_point_3()]);

	let preflightItems = $derived([
		m.preflight_item_1(),
		m.preflight_item_2(),
		m.preflight_item_3(),
		m.preflight_item_4()
	]);

	let installSteps = $derived([
		{
			number: '01',
			icon: Download04Icon,
			title: m.install_step_1_title(),
			body: m.install_step_1_body(),
			tip: m.install_step_1_tip()
		},
		{
			number: '02',
			icon: FolderOpenIcon,
			title: m.install_step_2_title(),
			body: m.install_step_2_body(),
			tip: m.install_step_2_tip()
		},
		{
			number: '03',
			icon: InstallingUpdates01Icon,
			title: m.install_step_3_title(),
			body: m.install_step_3_body(),
			tip: m.install_step_3_tip()
		},
		{
			number: '04',
			icon: GameController02Icon,
			title: m.install_step_4_title(),
			body: m.install_step_4_body(),
			tip: m.install_step_4_tip()
		}
	]);

	let successItems = $derived([m.verify_success_1(), m.verify_success_2(), m.verify_success_3()]);

	let faqs = $derived([
		{ value: 'smartscreen', question: m.faq_smartscreen_q(), answer: m.faq_smartscreen_a() },
		{ value: 'game-path', question: m.faq_game_path_q(), answer: m.faq_game_path_a() },
		{ value: 'access', question: m.faq_access_q(), answer: m.faq_access_a() },
		{ value: 'four-slots', question: m.faq_four_slots_q(), answer: m.faq_four_slots_a() },
		{ value: 'guests', question: m.faq_guests_q(), answer: m.faq_guests_a() },
		{ value: 'remove', question: m.faq_remove_q(), answer: m.faq_remove_a() }
	]);

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

<header class="sticky top-0 z-50 border-b border-border/70 bg-background/90 backdrop-blur-xl">
	<div class="mx-auto flex min-h-16 max-w-[1180px] items-center gap-4 px-4 sm:px-6 lg:px-8">
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
	</div>
</header>

<main id="main-content">
	<section class="hero-field relative isolate overflow-hidden border-b border-border/60">
		<div class="hero-glow" aria-hidden="true"></div>
		<div
			class="mx-auto grid max-w-[1180px] gap-10 px-4 py-16 sm:px-6 sm:py-20 lg:grid-cols-[1.25fr_0.75fr] lg:items-center lg:gap-14 lg:px-8 lg:py-24"
		>
			<div class="relative z-10 max-w-3xl">
				<Badge
					class="mb-6 rounded-md border border-[#a8e646]/30 bg-[#a8e646]/10 px-3 py-1 text-[#c7f47a]"
				>
					<span
						class="mr-1 size-1.5 rounded-full bg-[#a8e646] shadow-[0_0_10px_#a8e646]"
						aria-hidden="true"
					></span>
					{m.hero_badge()}
				</Badge>

				<p class="section-kicker mb-3">{m.hero_kicker()}</p>
				<h1
					class="frontier-title max-w-[13ch] text-[clamp(3.4rem,9vw,7.5rem)] leading-[0.84] text-foreground"
				>
					{m.hero_title()}
				</h1>
				<p class="mt-7 max-w-2xl text-lg leading-8 text-[#d8c6a4] sm:text-xl">
					{m.hero_description()}
				</p>

				{#if latest}
					<div
						class="mt-7 flex flex-wrap items-center gap-2 text-sm font-semibold text-muted-foreground"
					>
						<span
							class="inline-flex size-2 rounded-full bg-[#a8e646] shadow-[0_0_12px_rgba(168,230,70,0.75)]"
							aria-hidden="true"
						></span>
						{m.hero_latest({ version: latest.tag })}
					</div>
				{/if}

				<div class="mt-8 flex flex-col gap-3 sm:flex-row sm:flex-wrap">
					{#if latest?.zipUrl}
						<Button
							href={latest.zipUrl}
							size="lg"
							class="h-12 rounded-md bg-primary px-5 text-base font-black text-primary-foreground shadow-[0_8px_35px_rgba(244,182,63,0.22)] hover:bg-[#ffd75a]"
						>
							<HugeiconsIcon icon={WindowsNewIcon} strokeWidth={2.2} data-icon="inline-start" />
							{m.hero_download_zip({ version: latest.tag })}
						</Button>
					{/if}
					{#if latest?.installerUrl}
						<Button
							href={latest.installerUrl}
							variant="outline"
							size="lg"
							class="h-12 rounded-md border-border bg-card/65 px-5 text-base font-bold hover:border-primary/60 hover:bg-secondary"
						>
							<HugeiconsIcon icon={Download04Icon} strokeWidth={2.2} data-icon="inline-start" />
							{m.hero_direct_exe()}
						</Button>
					{/if}
					<Button
						href={REPOSITORY_URL}
						target="_blank"
						rel="noreferrer"
						variant="ghost"
						size="lg"
						class="h-12 rounded-md px-4 text-base text-muted-foreground hover:text-foreground"
					>
						<HugeiconsIcon icon={Github01Icon} strokeWidth={2} data-icon="inline-start" />
						{m.hero_source()}
					</Button>
				</div>
				<p class="mt-4 max-w-2xl text-sm leading-6 text-muted-foreground">{m.hero_note()}</p>
			</div>

			<Card.Root
				class="quick-card relative z-10 rounded-xl border border-[#805936] bg-[#1b1410]/92 py-0 shadow-2xl"
			>
				<Card.Header class="border-b border-border/70 px-6 py-5">
					<div class="flex items-center justify-between gap-4">
						<div>
							<p class="text-xs font-black tracking-[0.18em] text-primary uppercase">
								FFW8 / SETUP
							</p>
							<Card.Title class="mt-1 text-xl font-extrabold">{m.quick_title()}</Card.Title>
						</div>
						<Badge
							variant="outline"
							class="rounded-md border-border bg-background/50 text-muted-foreground"
						>
							<HugeiconsIcon icon={Clock01Icon} strokeWidth={2} />
							{m.quick_time()}
						</Badge>
					</div>
				</Card.Header>
				<Card.Content class="p-3">
					<ol class="space-y-1">
						{#each quickSteps as step, index (step)}
							<li
								class="group flex items-center gap-4 rounded-lg px-3 py-3 transition-colors hover:bg-secondary/70"
							>
								<span
									class="grid size-9 shrink-0 place-items-center rounded-md border border-primary/35 bg-primary/10 font-mono text-sm font-black text-primary"
								>
									{String(index + 1).padStart(2, '0')}
								</span>
								<span class="leading-6 font-semibold text-card-foreground">{step}</span>
								<HugeiconsIcon
									icon={ArrowRight01Icon}
									strokeWidth={2}
									class="ml-auto size-4 text-muted-foreground transition-transform group-hover:translate-x-1 group-hover:text-primary"
								/>
							</li>
						{/each}
					</ol>
				</Card.Content>
				<div
					class="border-t border-border/70 bg-[#0f0c09]/50 px-6 py-4 font-mono text-[0.7rem] tracking-[0.15em] text-[#a8e646] uppercase"
				>
					<span aria-hidden="true">●</span> PACKAGE VERIFIED / SOURCE-OWNED LUA
				</div>
			</Card.Root>
		</div>

		<div
			class="mx-auto grid max-w-[1180px] grid-cols-1 border-t border-border/50 px-4 sm:grid-cols-3 sm:px-6 lg:px-8"
		>
			<div class="stat-cell">
				<span>{m.stat_game_label()}</span>
				<strong>{m.stat_game_value()}</strong>
			</div>
			<div class="stat-cell sm:border-l sm:border-border/50">
				<span>{m.stat_platform_label()}</span>
				<strong>{m.stat_platform_value()}</strong>
			</div>
			<div class="stat-cell sm:border-l sm:border-border/50">
				<span>{m.stat_capacity_label()}</span>
				<strong>{m.stat_capacity_value()}</strong>
			</div>
		</div>
	</section>

	<div class="mx-auto max-w-[1180px] px-4 pt-8 sm:px-6 lg:px-8">
		<Alert.Root
			class="rounded-lg border-[#de5545]/45 bg-[#de5545]/8 px-5 py-4 text-[#ffe2d8] shadow-[inset_3px_0_0_#de5545]"
		>
			<HugeiconsIcon icon={Alert02Icon} strokeWidth={2.2} class="mt-0.5 text-[#ff795f]" />
			<Alert.Title class="text-base font-black">{m.critical_title()}</Alert.Title>
			<Alert.Description class="max-w-4xl leading-6 text-[#e5c5bb]">
				{m.critical_body()}
			</Alert.Description>
		</Alert.Root>
	</div>

	<section class="section-shell" aria-labelledby="scope-title">
		<div class="section-heading">
			<p class="section-kicker">{m.scope_kicker()}</p>
			<h2 id="scope-title">{m.scope_title()}</h2>
			<p>{m.scope_description()}</p>
		</div>

		<div class="grid gap-5 lg:grid-cols-[1fr_1fr_0.82fr]">
			<Card.Root class="role-card host-card rounded-xl border border-primary/35 bg-card/90">
				<Card.Header>
					<div class="mb-3 flex items-center justify-between">
						<span class="icon-tile bg-primary/15 text-primary">
							<HugeiconsIcon icon={ComputerCheckIcon} strokeWidth={2} class="size-6" />
						</span>
						<Badge class="rounded-md bg-primary text-primary-foreground">{m.host_badge()}</Badge>
					</div>
					<Card.Title class="text-2xl font-black">{m.host_title()}</Card.Title>
					<Card.Description class="text-base leading-7">{m.host_description()}</Card.Description>
				</Card.Header>
				<Card.Content>
					<ul class="space-y-3">
						{#each hostPoints as point (point)}
							<li class="flex gap-3 leading-6">
								<HugeiconsIcon
									icon={CheckmarkCircle02Icon}
									strokeWidth={2}
									class="mt-1 size-4 shrink-0 text-[#a8e646]"
								/>
								<span>{point}</span>
							</li>
						{/each}
					</ul>
				</Card.Content>
			</Card.Root>

			<Card.Root class="role-card rounded-xl border border-[#3dd6c5]/30 bg-card/90">
				<Card.Header>
					<div class="mb-3 flex items-center justify-between">
						<span class="icon-tile bg-[#3dd6c5]/10 text-[#6de2d5]">
							<HugeiconsIcon icon={UserGroup02Icon} strokeWidth={2} class="size-6" />
						</span>
						<Badge
							variant="outline"
							class="rounded-md border-[#3dd6c5]/35 bg-[#3dd6c5]/8 text-[#77e4d7]"
							>{m.guest_badge()}</Badge
						>
					</div>
					<Card.Title class="text-2xl font-black">{m.guest_title()}</Card.Title>
					<Card.Description class="text-base leading-7">{m.guest_description()}</Card.Description>
				</Card.Header>
				<Card.Content>
					<ul class="space-y-3">
						{#each guestPoints as point (point)}
							<li class="flex gap-3 leading-6">
								<HugeiconsIcon
									icon={CheckmarkCircle02Icon}
									strokeWidth={2}
									class="mt-1 size-4 shrink-0 text-[#3dd6c5]"
								/>
								<span>{point}</span>
							</li>
						{/each}
					</ul>
				</Card.Content>
			</Card.Root>

			<Card.Root class="rounded-xl border border-border bg-[#15100d]" size="sm">
				<Card.Header class="border-b border-border/60">
					<div class="flex items-center gap-3">
						<HugeiconsIcon icon={ShieldCheckIcon} strokeWidth={2} class="size-5 text-primary" />
						<Card.Title class="text-lg font-black">{m.preflight_title()}</Card.Title>
					</div>
				</Card.Header>
				<Card.Content>
					<ul class="divide-y divide-border/55">
						{#each preflightItems as item, index (item)}
							<li class="flex gap-3 py-3 first:pt-0 last:pb-0">
								<span class="font-mono text-xs font-bold text-primary">0{index + 1}</span>
								<span class="leading-5 text-muted-foreground">{item}</span>
							</li>
						{/each}
					</ul>
				</Card.Content>
			</Card.Root>
		</div>
	</section>

	<section id="install" class="section-shell scroll-mt-24" aria-labelledby="install-title">
		<div class="section-heading">
			<p class="section-kicker">{m.install_kicker()}</p>
			<h2 id="install-title">{m.install_title()}</h2>
			<p>{m.install_description()}</p>
		</div>

		<div class="relative grid gap-5 md:grid-cols-2">
			<div class="step-rail" aria-hidden="true"></div>
			{#each installSteps as step (step.number)}
				<Card.Root
					class="install-card relative rounded-xl border border-border bg-card/90 transition-all duration-300 hover:-translate-y-1 hover:border-primary/45 hover:shadow-[0_18px_55px_rgba(0,0,0,0.25)]"
				>
					<Card.Header>
						<div class="mb-2 flex items-center justify-between gap-4">
							<span class="icon-tile bg-primary/10 text-primary">
								<HugeiconsIcon icon={step.icon} strokeWidth={2} class="size-6" />
							</span>
							<span class="font-mono text-3xl font-black text-border">{step.number}</span>
						</div>
						<Card.Title class="text-2xl font-black">{step.title}</Card.Title>
					</Card.Header>
					<Card.Content class="flex flex-1 flex-col">
						<p class="text-base leading-7 text-muted-foreground">{step.body}</p>
						<div
							class="mt-5 flex items-start gap-2 border-t border-border/55 pt-4 font-mono text-xs leading-5 text-[#d7b578]"
						>
							<HugeiconsIcon
								icon={ArrowRight01Icon}
								strokeWidth={2}
								class="mt-0.5 size-4 shrink-0 text-primary"
							/>
							<span>{step.tip}</span>
						</div>
					</Card.Content>
				</Card.Root>
			{/each}
		</div>

		{#if latest?.zipUrl}
			<div class="mt-8 flex justify-center">
				<Button href={latest.zipUrl} size="lg" class="h-12 rounded-md px-6 text-base font-black">
					<HugeiconsIcon icon={FileZipIcon} strokeWidth={2.2} data-icon="inline-start" />
					{m.download_latest()}
				</Button>
			</div>
		{/if}
	</section>

	<section
		id="verify"
		class="verify-band scroll-mt-24 border-y border-border/70"
		aria-labelledby="verify-title"
	>
		<div
			class="mx-auto grid max-w-[1180px] gap-10 px-4 py-16 sm:px-6 lg:grid-cols-[0.92fr_1.08fr] lg:items-center lg:px-8 lg:py-20"
		>
			<div>
				<p class="section-kicker">{m.verify_kicker()}</p>
				<h2 id="verify-title" class="mt-3 text-4xl font-black tracking-tight sm:text-5xl">
					{m.verify_title()}
				</h2>
				<p class="mt-5 max-w-xl text-lg leading-8 text-muted-foreground">
					{m.verify_description()}
				</p>

				<div class="session-grid mt-8" aria-label="1 host and 7 invite slots">
					<div class="session-slot host-slot">
						<HugeiconsIcon icon={CowboyHatIcon} strokeWidth={2.2} class="size-5" />
						<span>{m.slot_host()}</span>
					</div>
					{#each inviteSlots as slot (slot)}
						<div class="session-slot invite-slot">
							<span class="text-lg leading-none">+</span>
							<span>{m.slot_invite()} {slot}</span>
						</div>
					{/each}
				</div>
			</div>

			<div class="space-y-5">
				<Card.Root class="rounded-xl border border-[#a8e646]/30 bg-[#a8e646]/6">
					<Card.Header>
						<div class="flex items-center gap-3">
							<span class="icon-tile bg-[#a8e646]/10 text-[#b9ed61]">
								<HugeiconsIcon icon={PackageCheckIcon} strokeWidth={2} class="size-6" />
							</span>
							<Card.Title class="text-xl font-black">{m.verify_success_title()}</Card.Title>
						</div>
					</Card.Header>
					<Card.Content>
						<ul class="space-y-3">
							{#each successItems as item (item)}
								<li class="flex gap-3 text-base leading-6">
									<HugeiconsIcon
										icon={CheckmarkCircle02Icon}
										strokeWidth={2}
										class="mt-1 size-4 shrink-0 text-[#a8e646]"
									/>
									<span>{item}</span>
								</li>
							{/each}
						</ul>
					</Card.Content>
				</Card.Root>

				<Alert.Root class="rounded-xl border-primary/30 bg-primary/6 px-5 py-4">
					<HugeiconsIcon icon={BookOpen02Icon} strokeWidth={2} class="mt-0.5 text-primary" />
					<Alert.Title class="text-base font-black">{m.verify_limit_title()}</Alert.Title>
					<Alert.Description class="leading-6 text-[#d6c1a0]"
						>{m.verify_limit_body()}</Alert.Description
					>
				</Alert.Root>
			</div>
		</div>
	</section>

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
					class={`mr-1 size-1.5 rounded-full ${data.releasesLive ? 'bg-[#a8e646]' : 'bg-primary'}`}
					aria-hidden="true"
				></span>
				{data.releasesLive ? m.release_live() : m.release_fallback()}
			</Badge>
		</div>

		<div class="mt-10 grid gap-5">
			{#each data.releases as release, index (release.tag)}
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
									<Badge variant="outline" class="rounded-md border-[#3dd6c5]/35 text-[#67dace]"
										>{m.release_prerelease()}</Badge
									>
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
							<Button
								variant="ghost"
								class="ml-auto cursor-pointer rounded-md text-muted-foreground"
							>
								<HugeiconsIcon icon={Download02Icon} strokeWidth={2} data-icon="inline-start" />
								{release.downloadCount}
								{m.release_downloads()}
							</Button>
						{/if}
					</Card.Content>
				</Card.Root>
			{/each}
		</div>
	</section>

	<section id="help" class="section-shell scroll-mt-24 pt-4" aria-labelledby="help-title">
		<div class="grid gap-10 lg:grid-cols-[0.6fr_1.4fr]">
			<div class="section-heading mb-0 lg:sticky lg:top-28 lg:self-start">
				<p class="section-kicker">{m.help_kicker()}</p>
				<h2 id="help-title">{m.help_title()}</h2>
				<p>{m.help_description()}</p>
				<div class="mt-7 flex gap-3">
					<Button
						href={REPOSITORY_URL}
						target="_blank"
						rel="noreferrer"
						variant="outline"
						class="rounded-md border-border"
					>
						<HugeiconsIcon icon={CodeIcon} strokeWidth={2} data-icon="inline-start" />
						{m.footer_github()}
					</Button>
				</div>
			</div>

			<Accordion.Root type="single" class="rounded-xl border-border bg-card/80">
				{#each faqs as faq (faq.value)}
					<Accordion.Item value={faq.value} class="border-border/65 data-open:bg-secondary/40">
						<Accordion.Trigger
							class="px-5 py-5 text-base font-bold hover:text-primary hover:no-underline"
						>
							{faq.question}
						</Accordion.Trigger>
						<Accordion.Content class="px-5 pb-5 text-base leading-7 text-muted-foreground">
							{faq.answer}
						</Accordion.Content>
					</Accordion.Item>
				{/each}
			</Accordion.Root>
		</div>
	</section>

	<section class="mx-auto max-w-[1180px] px-4 pb-16 sm:px-6 lg:px-8">
		<div
			class="final-cta relative overflow-hidden rounded-xl border border-primary/35 bg-primary px-6 py-9 text-primary-foreground sm:px-10"
		>
			<div class="relative z-10 flex flex-col justify-between gap-6 md:flex-row md:items-center">
				<div>
					<p class="font-mono text-xs font-black tracking-[0.2em] uppercase opacity-65">
						READY TO RIDE
					</p>
					<h2 class="mt-2 text-3xl font-black tracking-tight sm:text-4xl">{m.quick_title()}</h2>
				</div>
				{#if latest?.zipUrl}
					<Button
						href={latest.zipUrl}
						size="lg"
						class="h-12 rounded-md bg-[#100d0a] px-6 text-base font-black text-[#fff8e8] hover:bg-[#2a2018]"
					>
						<HugeiconsIcon icon={PlayIcon} strokeWidth={2.2} data-icon="inline-start" />
						{m.hero_download_zip({ version: latest.tag })}
					</Button>
				{/if}
			</div>
		</div>
	</section>
</main>

<footer class="border-t border-border/60 bg-[#0c0907]">
	<div
		class="mx-auto flex max-w-[1180px] flex-col gap-6 px-4 py-9 sm:px-6 lg:flex-row lg:items-center lg:justify-between lg:px-8"
	>
		<div class="max-w-2xl">
			<p class="font-bold text-foreground">{m.footer_notice()}</p>
			<p class="mt-2 text-sm leading-6 text-muted-foreground">{m.footer_disclaimer()}</p>
		</div>
		<div class="flex flex-wrap gap-2">
			<Button
				href={REPOSITORY_URL}
				target="_blank"
				rel="noreferrer"
				variant="ghost"
				size="sm"
				class="rounded-md"
			>
				<HugeiconsIcon icon={Github01Icon} strokeWidth={2} data-icon="inline-start" />
				{m.footer_github()}
			</Button>
			<Button
				href={allReleasesUrl}
				target="_blank"
				rel="noreferrer"
				variant="ghost"
				size="sm"
				class="rounded-md"
			>
				<HugeiconsIcon icon={Download04Icon} strokeWidth={2} data-icon="inline-start" />
				{m.footer_releases()}
			</Button>
		</div>
	</div>
</footer>
