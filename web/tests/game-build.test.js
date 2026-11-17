import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import test from 'node:test';

function readJson(relativePath) {
	return JSON.parse(readFileSync(new URL(relativePath, import.meta.url), 'utf8'));
}

test('website game compatibility follows the pinned installer target', () => {
	const { target } = readJson('../../config/upstream.lock.json');
	assert.deepEqual(readJson('../src/lib/game-build.json'), {
		gameVersion: target.gameVersion,
		artifactVersion: target.artifactVersion
	});
});

test('all preflight translations interpolate the shared game build label', () => {
	const messages = readdirSync(new URL('../messages/', import.meta.url)).filter((file) =>
		file.endsWith('.json')
	);
	assert.ok(messages.length > 0);
	for (const file of messages) {
		const locale = readJson(`../messages/${file}`);
		assert.match(locale.preflight_item_3, /\{build\}/, file);
		assert.ok(!('stat_game_value' in locale), `${file} contains a duplicate game build label`);
	}
});
