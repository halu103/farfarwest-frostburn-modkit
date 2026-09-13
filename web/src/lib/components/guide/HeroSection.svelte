<script lang="ts">
	import { page } from '$app/state';
	import {
		ArrowRight01Icon,
		Clock01Icon,
		Download04Icon,
		Github01Icon,
		WindowsNewIcon
	} from '@hugeicons/core-free-icons';
	import { HugeiconsIcon } from '@hugeicons/svelte';
	import { Badge } from '#lib/components/ui/badge/index.js';
	import { Button } from '#lib/components/ui/button/index.js';
	import * as Card from '#lib/components/ui/card/index.js';
	import * as m from '#lib/paraglide/messages.js';
	import { getLocaleForUrl } from '#lib/paraglide/runtime.js';
	import { REPOSITORY_URL } from '#lib';
	import type { Release } from './types.js';

	let { latest }: { latest?: Release } = $props();

	let activeLocale = $derived(getLocaleForUrl(page.url));
	let isCjk = $derived(activeLocale === 'zh' || activeLocale === 'jp' || activeLocale === 'kr');
	let quickSteps = $derived([
		m.quick_step_1(),
		m.quick_step_2(),
		m.quick_step_3(),
		m.quick_step_4()
	]);
</script>

<section
	class="hero-field relative isolate overflow-hidden border-b border-border/60"
	data-locale={activeLocale}
>
	<div class="hero-glow" aria-hidden="true"></div>

	<div
		class="mx-auto grid max-w-[1180px] gap-10 px-4 py-16
			sm:px-6 sm:py-20
			lg:grid-cols-[minmax(0,1fr)_minmax(320px,390px)]
			lg:items-center lg:gap-12 lg:px-8 lg:py-24"
	>
		<div class="relative z-10 max-w-3xl min-w-0">
			<Badge
				class="mb-6 rounded-md border border-[#a8e646]/30 bg-[#a8e646]/10 px-3 py-1 text-[#c7f47a]"
			>
				<span
					class="mr-1 size-1.5 rounded-full bg-[#a8e646] shadow-[0_0_10px_#a8e646]"
					aria-hidden="true"
				></span>

				{m.hero_badge()}
			</Badge>

			<p class="section-kicker mb-3">
				{m.hero_kicker()}
			</p>

			<h1
				class="frontier-title hero-title text-foreground"
				class:hero-title-vi={activeLocale === 'vi'}
				class:hero-title-de={activeLocale === 'de'}
				class:hero-title-cjk={isCjk}
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
						class="inline-flex size-2 shrink-0 rounded-full bg-[#a8e646]
							shadow-[0_0_12px_rgba(168,230,70,0.75)]"
						aria-hidden="true"
					></span>

					<span class="min-w-0">
						{m.hero_latest({ version: latest.tag })}
					</span>
				</div>
			{/if}

			<div class="mt-8 flex flex-col gap-3 sm:flex-row sm:flex-wrap">
				{#if latest?.zipUrl}
					<Button
						href={latest.zipUrl}
						size="lg"
						class="h-auto min-h-12 rounded-md bg-primary px-5 py-3 text-center
							text-base font-black whitespace-normal text-primary-foreground
							shadow-[0_8px_35px_rgba(244,182,63,0.22)]
							hover:bg-[#ffd75a]"
					>
						<HugeiconsIcon
							icon={WindowsNewIcon}
							strokeWidth={2.2}
							data-icon="inline-start"
							class="shrink-0"
						/>

						<span>
							{m.hero_download_zip({ version: latest.tag })}
						</span>
					</Button>
				{/if}

				{#if latest?.installerUrl}
					<Button
						href={latest.installerUrl}
						variant="outline"
						size="lg"
						class="h-auto min-h-12 rounded-md border-border bg-card/65 px-5
							py-3 text-center text-base font-bold whitespace-normal
							hover:border-primary/60 hover:bg-secondary"
					>
						<HugeiconsIcon
							icon={Download04Icon}
							strokeWidth={2.2}
							data-icon="inline-start"
							class="shrink-0"
						/>

						<span>{m.hero_direct_exe()}</span>
					</Button>
				{/if}

				<Button
					href={REPOSITORY_URL}
					target="_blank"
					rel="noreferrer"
					variant="ghost"
					size="lg"
					class="h-auto min-h-12 rounded-md px-4 py-3 text-base
						whitespace-normal text-muted-foreground hover:text-foreground"
				>
					<HugeiconsIcon
						icon={Github01Icon}
						strokeWidth={2}
						data-icon="inline-start"
						class="shrink-0"
					/>

					<span>{m.hero_source()}</span>
				</Button>
			</div>

			<p class="mt-4 max-w-2xl text-sm leading-6 text-muted-foreground">
				{m.hero_note()}
			</p>
		</div>

		<Card.Root
			class="quick-card relative z-10 min-w-0 rounded-xl border border-[#805936]
				bg-[#1b1410]/92 py-0 shadow-2xl"
		>
			<Card.Header class="border-b border-border/70 px-5 py-5 sm:px-6">
				<div
					class="flex flex-col items-start gap-3 sm:flex-row
						sm:items-start sm:justify-between"
				>
					<div class="min-w-0 flex-1">
						<p class="text-xs font-black tracking-[0.18em] text-primary uppercase">FFW8 / SETUP</p>

						<Card.Title class="mt-1 text-xl leading-snug font-extrabold text-balance">
							{m.quick_title()}
						</Card.Title>
					</div>

					<Badge
						variant="outline"
						class="shrink-0 rounded-md border-border bg-background/50
							whitespace-nowrap text-muted-foreground"
					>
						<HugeiconsIcon icon={Clock01Icon} strokeWidth={2} class="shrink-0" />

						{m.quick_time()}
					</Badge>
				</div>
			</Card.Header>

			<Card.Content class="p-3">
				<ol class="space-y-1">
					{#each quickSteps as step, index (step)}
						<li
							class="group flex min-w-0 items-center gap-3 rounded-lg px-3 py-3
								transition-colors hover:bg-secondary/70 sm:gap-4"
						>
							<span
								class="grid size-9 shrink-0 place-items-center rounded-md border
									border-primary/35 bg-primary/10 font-mono text-sm
									font-black text-primary"
							>
								{String(index + 1).padStart(2, '0')}
							</span>

							<span
								class="quick-step min-w-0 flex-1 leading-6 font-semibold
									text-card-foreground"
							>
								{step}
							</span>

							<HugeiconsIcon
								icon={ArrowRight01Icon}
								strokeWidth={2}
								class="ml-auto size-4 shrink-0 text-muted-foreground
									transition-transform group-hover:translate-x-1
									group-hover:text-primary"
							/>
						</li>
					{/each}
				</ol>
			</Card.Content>

			<div
				class="border-t border-border/70 bg-[#0f0c09]/50 px-6 py-4
					font-mono text-[0.7rem] leading-5 tracking-[0.15em]
					text-[#a8e646] uppercase"
			>
				<span aria-hidden="true">●</span>
				PACKAGE VERIFIED / SOURCE-OWNED LUA
			</div>
		</Card.Root>
	</div>

	<div
		class="mx-auto grid max-w-[1180px] grid-cols-1 border-t border-border/50
			px-4 sm:grid-cols-3 sm:px-6 lg:px-8"
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

<style>
	.hero-title {
		max-width: 13ch;
		font-size: clamp(3.2rem, 7.3vw, 6.7rem);
		line-height: 0.87;
		text-wrap: balance;
	}

	/* Vietnamese cần nhiều khoảng trống theo chiều dọc cho dấu */
	.hero-title-vi {
		max-width: 12ch;
		font-size: clamp(3rem, 6.5vw, 6rem);
		line-height: 1.02;
		letter-spacing: -0.025em;
	}

	/* German */
	.hero-title-de {
		max-width: 14ch;
		font-size: clamp(2.9rem, 6.2vw, 5.8rem);
		line-height: 0.9;
		letter-spacing: -0.025em;
	}

	/* Chinese / Japanese / Korean */
	.hero-title-cjk {
		max-width: 10ch;
		font-size: clamp(3rem, 6.7vw, 6rem);
		line-height: 1;
		letter-spacing: 0;
	}

	.quick-step {
		overflow-wrap: break-word;
		hyphens: auto;
	}

	/* German có compound words rất dài */
	[data-locale='de'] .quick-step {
		overflow-wrap: anywhere;
		hyphens: auto;
	}

	/* Tránh Korean bị xuống dòng từng ký tự */
	[data-locale='ko'] .quick-step {
		word-break: keep-all;
	}

	@media (max-width: 639px) {
		.hero-title,
		.hero-title-de,
		.hero-title-cjk {
			max-width: 100%;
		}
	}
</style>
