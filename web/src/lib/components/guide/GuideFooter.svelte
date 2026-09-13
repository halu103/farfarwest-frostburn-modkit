<script lang="ts">
	import { Download04Icon, Github01Icon } from '@hugeicons/core-free-icons';
	import { HugeiconsIcon } from '@hugeicons/svelte';
	import { Button } from '#lib/components/ui/button/index.js';
	import * as m from '#lib/paraglide/messages.js';
	import { REPOSITORY_URL } from '#lib';

	const allReleasesUrl = `${REPOSITORY_URL}/releases`;
</script>

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
