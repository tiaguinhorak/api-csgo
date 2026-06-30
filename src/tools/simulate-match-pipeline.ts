/**
 * Simula partida ranked completa sem cliente CS:GO.
 *
 * Uso:
 *   npm run simulate:match -- --room-id <RankedMatchSession.id>
 *   npm run simulate:match -- --room-id cmxxx --steam 76561198367970104
 *
 * O room-id deve existir no site (Postgres) com status starting|live.
 * Se csgoMatchId estiver null, o site associa pelo roomId no webhook.
 */
import 'dotenv/config';
import Database from 'better-sqlite3';
import { matchManager } from '../services/match-manager';
import { stateStore } from '../services/state-store';
import { ensureMatchLiveTableWritable } from '../services/match-live-db';
import { getMatchLiveDbPath } from '../services/weapons-db-path';
import { processMatchLiveDbChanges } from '../services/match-live-watcher';

/** Same steam ids as site/lib/ranked/simulate-match.ts bot users. */
const ADMIN_STEAM_DEFAULT = '76561198000000001';

type CliOptions = {
  roomId: string;
  ichSteam: string;
  scoreA: number;
  scoreB: number;
  winnerTeam: 'A' | 'B';
  fullRoster: boolean;
  dryRun: boolean;
};

function botSteam(index: number): string {
  return `765611979602879${(30 + index).toString().padStart(2, '0')}`;
}

function parseArgs(): CliOptions {
  const args = process.argv.slice(2);
  let roomId = '';
  let ichSteam = '76561198367970104';
  let scoreA = 8;
  let scoreB = 13;
  let winnerTeam: 'A' | 'B' = 'B';
  let fullRoster = false;
  let dryRun = false;

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '--room-id' && args[i + 1]) {
      roomId = args[++i];
      continue;
    }
    if (arg === '--steam' && args[i + 1]) {
      ichSteam = args[++i];
      continue;
    }
    if (arg === '--score-a' && args[i + 1]) {
      scoreA = Number(args[++i]);
      continue;
    }
    if (arg === '--score-b' && args[i + 1]) {
      scoreB = Number(args[++i]);
      continue;
    }
    if (arg === '--winner' && args[i + 1]) {
      const w = args[++i]?.toUpperCase();
      if (w === 'A' || w === 'B') winnerTeam = w;
      continue;
    }
    if (arg === '--full-roster') {
      fullRoster = true;
      continue;
    }
    if (arg === '--dry-run') {
      dryRun = true;
    }
  }

  if (!roomId) {
    roomId = `sim-room-${Date.now()}`;
    console.warn(
      `WARN: --room-id não informado — usando ${roomId} (site provavelmente retorna session_not_found)`,
    );
  } else if (/^STEAM_/i.test(roomId) || /^\d{17}$/.test(roomId)) {
    console.warn(
      'WARN: --room-id parece Steam ID, não RankedMatchSession.id (ex.: cmqqznpl80002msus6zrub26r)',
    );
  }

  if (scoreA === scoreB) {
    console.warn('WARN: empate no placar — ajustando +1 para o vencedor.');
    if (winnerTeam === 'A') scoreA += 1;
    else scoreB += 1;
  }

  return { roomId, ichSteam, scoreA, scoreB, winnerTeam, fullRoster, dryRun };
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function probeSiteReachable(baseUrl: string): Promise<boolean> {
  if (!baseUrl) return false;
  try {
    const headers: Record<string, string> = {};
    if (baseUrl.includes('ngrok')) {
      headers['ngrok-skip-browser-warning'] = 'true';
    }
    const res = await fetch(baseUrl.replace(/\/+$/, '') + '/', {
      headers,
      signal: AbortSignal.timeout(8_000),
    });
    return res.ok || res.status < 500;
  } catch {
    return false;
  }
}

type SimPlayer = {
  steam: string;
  slot: 1 | 2;
  kills: number;
  deaths: number;
  assists: number;
  score: number;
  mvp: number;
  headshots: number;
  damage: number;
  awpKills: number;
};

function buildPlayerStats(steam: string, slot: 1 | 2, seed: number): SimPlayer {
  const kills = 8 + (seed % 18);
  const deaths = 6 + ((seed * 3) % 16);
  return {
    steam,
    slot,
    kills,
    deaths,
    assists: 2 + (seed % 8),
    score: kills * 2 + (seed % 12),
    mvp: seed % 4,
    headshots: Math.floor(kills * (0.25 + (seed % 5) * 0.05)),
    damage: kills * 90 + seed * 12,
    awpKills: seed % 6,
  };
}

function buildStatsJson(opts: {
  ichSteam: string;
  fullRoster: boolean;
  winnerTeam: 'A' | 'B';
}): string {
  const players: SimPlayer[] = opts.fullRoster
    ? [
        buildPlayerStats(ADMIN_STEAM_DEFAULT, 1, 0),
        ...([1, 2, 3, 4] as const).map((i) => buildPlayerStats(botSteam(i), 1, i)),
        buildPlayerStats(opts.ichSteam, 2, 10),
        ...([6, 7, 8, 9] as const).map((i) => buildPlayerStats(botSteam(i), 2, i + 10)),
      ]
    : [
        buildPlayerStats(opts.ichSteam, 2, 10),
        buildPlayerStats(botSteam(1), 1, 1),
      ];

  const mvpSteam = players.reduce((best, p) => (p.kills > best.kills ? p : best)).steam;

  return JSON.stringify({
    players,
    rounds: [
      { roundNumber: 1, winnerTeam: opts.winnerTeam, reason: 'ct_win', bombPlanted: false },
      { roundNumber: 2, winnerTeam: opts.winnerTeam, reason: 'terrorists_win', bombPlanted: true },
      { roundNumber: 3, winnerTeam: opts.winnerTeam === 'A' ? 'B' : 'A', reason: 'ct_win', bombPlanted: false },
    ],
    deaths: [
      {
        roundNumber: 1,
        victimSteamId: players[0]!.steam,
        killerSteamId: mvpSteam,
        weapon: 'ak47',
        headshot: true,
        victimTeam: 'A',
        x: 120.5,
        y: -980.2,
        z: 64.0,
      },
      {
        roundNumber: 2,
        victimSteamId: players[1]?.steam ?? players[0]!.steam,
        killerSteamId: mvpSteam,
        weapon: 'awp',
        headshot: true,
        victimTeam: 'A',
        x: 450.0,
        y: -600.0,
        z: 72.0,
      },
    ],
    highlights: [
      { steamId: mvpSteam, type: 'ACE', roundNumber: 10, detail: 'Ace' },
      { steamId: mvpSteam, type: 'MULTI_KILL', roundNumber: 5, detail: '3 kills' },
    ],
  });
}

function buildMatchTeams(opts: { ichSteam: string; fullRoster: boolean }) {
  if (opts.fullRoster) {
    return {
      teamA: {
        name: 'Team Alpha',
        players: [
          { steamId: ADMIN_STEAM_DEFAULT, name: 'Admin' },
          ...([1, 2, 3, 4] as const).map((i) => ({
            steamId: botSteam(i),
            name: `Bot Alpha ${i}`,
          })),
        ],
      },
      teamB: {
        name: 'Team Beta',
        players: [
          { steamId: opts.ichSteam, name: 'Player' },
          ...([6, 7, 8, 9] as const).map((i) => ({
            steamId: botSteam(i),
            name: `Bot Beta ${i}`,
          })),
        ],
      },
    };
  }

  return {
    teamA: {
      name: 'Team Alpha',
      players: [
        { steamId: botSteam(1), name: 'Bot Alpha 1' },
        { steamId: botSteam(2), name: 'Bot Alpha 2' },
      ],
    },
    teamB: {
      name: 'Team Ichi',
      players: [
        { steamId: opts.ichSteam, name: 'Player' },
        { steamId: botSteam(3), name: 'Bot Beta 1' },
      ],
    },
  };
}

async function main(): Promise<void> {
  const opts = parseArgs();
  const siteUrl = process.env.CLUTCH_SITE_URL?.trim() || process.env.SITE_ORIGIN?.trim() || '';
  const syncKey = process.env.CSGO_SKINS_SYNC_KEY?.trim() || '';

  console.log('=== Clutch — simulate match pipeline (sem CS:GO) ===');
  console.log(`roomId:    ${opts.roomId}`);
  console.log(`steam:     ${opts.ichSteam}`);
  console.log(`score:     ${opts.scoreA}:${opts.scoreB} (winner ${opts.winnerTeam})`);
  console.log(`roster:    ${opts.fullRoster ? '10 jogadores (admin + bots do site)' : '2 jogadores'}`);
  console.log(`site:      ${siteUrl || '(CLUTCH_SITE_URL não definido)'}`);
  console.log(`sync key:  ${syncKey ? 'set' : 'MISSING'}`);
  if (siteUrl) {
    const reachable = await probeSiteReachable(siteUrl);
    console.log(`site reach: ${reachable ? 'OK' : 'FAIL (fetch failed — rode: bash scripts/check-site-dns.sh)'}`);
  }
  console.log('');

  const teams = buildMatchTeams(opts);
  const match = matchManager.createMatch({
    roomId: opts.roomId,
    ...teams,
    mapPool: ['de_dust2', 'de_mirage'],
  });

  match.status = 'live';
  match.selectedMap = 'de_dust2';
  stateStore.matches.set(match.id, match);
  stateStore.persist();

  const statsJson = buildStatsJson({
    ichSteam: opts.ichSteam,
    fullRoster: opts.fullRoster,
    winnerTeam: opts.winnerTeam,
  });
  const now = Math.floor(Date.now() / 1000);
  const startedAt = now - 1800;
  const finishedAt = now;

  console.log(`csgoMatchId: ${match.id}`);
  console.log('');

  if (opts.dryRun) {
    console.log('DRY RUN — stats_json preview:');
    console.log(statsJson.slice(0, 400) + '...');
    return;
  }

  ensureMatchLiveTableWritable();
  const dbPath = getMatchLiveDbPath();
  const db = new Database(dbPath);
  db.prepare(
    `REPLACE INTO clutch_match_live (
      match_id, score_team_a, score_team_b, score_ct, score_t, round_num,
      phase, winner, max_rounds, started_at, finished_at, stats_json, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, 'finished', ?, 30, ?, ?, ?, ?)`,
  ).run(
    match.id,
    opts.scoreA,
    opts.scoreB,
    opts.scoreA,
    opts.scoreB,
    opts.scoreA + opts.scoreB,
    opts.winnerTeam,
    startedAt,
    finishedAt,
    statsJson,
    now,
  );
  db.close();

  console.log(`SQLite:    ${dbPath}`);
  console.log('Aguardando persistência do store.json...');
  await sleep(250);

  console.log('Encaminhando resultado ao site...');
  await processMatchLiveDbChanges();

  console.log('');
  console.log('=== Concluído ===');
  console.log('Verifique:');
  console.log(`  Site: /dashboard/partidas/${opts.roomId}`);
  console.log(`  VPS:  sqlite3 ${dbPath} "SELECT match_id, phase FROM clutch_match_live WHERE match_id='${match.id}';"`);
  console.log('');
  console.log('Se session_not_found no site, crie uma sessão ranked ou passe --room-id de uma sessão ativa.');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
