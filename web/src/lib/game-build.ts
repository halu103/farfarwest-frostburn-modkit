import target from './game-build.json';

const changelist = target.artifactVersion.replace(/^CL(?=\d)/, 'CL ');

export const GAME_BUILD_LABEL = `${target.gameVersion} / ${changelist}`;
