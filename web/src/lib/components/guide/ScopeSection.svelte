<script lang="ts">
	import {
		Alert02Icon,
		CheckmarkCircle02Icon,
		ComputerCheckIcon,
		ShieldCheckIcon,
		UserGroup02Icon
	} from '@hugeicons/core-free-icons';
	import { HugeiconsIcon } from '@hugeicons/svelte';
	import * as Alert from '#lib/components/ui/alert/index.js';
	import { Badge } from '#lib/components/ui/badge/index.js';
	import * as Card from '#lib/components/ui/card/index.js';
	import * as m from '#lib/paraglide/messages.js';

	let hostPoints = $derived([m.host_point_1(), m.host_point_2(), m.host_point_3()]);
	let guestPoints = $derived([m.guest_point_1(), m.guest_point_2(), m.guest_point_3()]);
	let preflightItems = $derived([
		m.preflight_item_1(),
		m.preflight_item_2(),
		m.preflight_item_3(),
		m.preflight_item_4()
	]);
</script>

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
					>
						{m.guest_badge()}
					</Badge>
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
