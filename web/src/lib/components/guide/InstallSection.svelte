<script lang="ts">
	import {
		ArrowRight01Icon,
		Download04Icon,
		FileZipIcon,
		FolderOpenIcon,
		GameController02Icon,
		InstallingUpdates01Icon
	} from '@hugeicons/core-free-icons';
	import { HugeiconsIcon } from '@hugeicons/svelte';
	import { Button } from '#lib/components/ui/button/index.js';
	import * as Card from '#lib/components/ui/card/index.js';
	import * as m from '#lib/paraglide/messages.js';
	import type { Release } from './types.js';

	let { latest }: { latest?: Release } = $props();
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
</script>

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
