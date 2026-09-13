<script lang="ts">
	import { CodeIcon, PlayIcon } from '@hugeicons/core-free-icons';
	import { HugeiconsIcon } from '@hugeicons/svelte';
	import * as Accordion from '#lib/components/ui/accordion/index.js';
	import { Button } from '#lib/components/ui/button/index.js';
	import * as m from '#lib/paraglide/messages.js';
	import { REPOSITORY_URL } from '#lib';
	import type { Release } from './types.js';

	let { latest }: { latest?: Release } = $props();
	let faqs = $derived([
		{ value: 'smartscreen', question: m.faq_smartscreen_q(), answer: m.faq_smartscreen_a() },
		{ value: 'game-path', question: m.faq_game_path_q(), answer: m.faq_game_path_a() },
		{ value: 'access', question: m.faq_access_q(), answer: m.faq_access_a() },
		{ value: 'four-slots', question: m.faq_four_slots_q(), answer: m.faq_four_slots_a() },
		{ value: 'guests', question: m.faq_guests_q(), answer: m.faq_guests_a() },
		{ value: 'remove', question: m.faq_remove_q(), answer: m.faq_remove_a() }
	]);
</script>

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
