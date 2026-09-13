<script lang="ts">
	import {
		BookOpen02Icon,
		CheckmarkCircle02Icon,
		CowboyHatIcon,
		PackageCheckIcon
	} from '@hugeicons/core-free-icons';
	import { HugeiconsIcon } from '@hugeicons/svelte';
	import * as Alert from '#lib/components/ui/alert/index.js';
	import * as Card from '#lib/components/ui/card/index.js';
	import * as m from '#lib/paraglide/messages.js';

	const inviteSlots = [2, 3, 4, 5, 6, 7, 8];
	let successItems = $derived([m.verify_success_1(), m.verify_success_2(), m.verify_success_3()]);
</script>

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
