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

type CliOptions = {
  roomId: string;
  ichSteam: string;
  scoreA: number;
  scoreB: number;
  dryRun: boolean;
};

function parseArgs(): CliOptions {
  const args = process.argv.slice(2);
  let roomId = '';
  let ichSteam = '76561198367970104';
  let scoreA = 8;
  let scoreB = 13;
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

  return { roomId, ichSteam, scoreA, scoreB, dryRun };
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function probeSiteReachable(baseUrl: string): Promise<boolean> {
  if (!baseUrl) return false;
  try {
    const res = await fetch(baseUrl.replace(/\/+$/, '') + '/', {
      signal: AbortSignal.timeout(8_000),
    });
    return res.ok || res.status < 500;
  } catch {
    return false;
  }
}

function buildStatsJson(ichSteam: string): string {
  const botA = '76561197960287931';
  return JSON.stringify({
    players: [
      {
        steam: ichSteam,
        slot: 2,
        kills: 24,
        deaths: 12,
        assists: 5,
        score: 55,
        mvp: 3,
        headshots: 10,
        damage: 2400,
        awpKills: 8,
      },
      {
        steam: botA,
        slot: 1,
        kills: 18,
        deaths: 16,
        assists: 4,
        score: 42,
        mvp: 1,
        headshots: 6,
        damage: 1900,
        awpKills: 2,
      },
    ],
    rounds: [
      { roundNumber: 1, winnerTeam: 'B', reason: 'ct_win', bombPlanted: false },
      { roundNumber: 2, winnerTeam: 'B', reason: 'terrorists_win', bombPlanted: true },
      { roundNumber: 3, winnerTeam: 'A', reason: 'ct_win', bombPlanted: false },
    ],
    deaths: [
      {
        roundNumber: 1,
        victimSteamId: botA,
        killerSteamId: ichSteam,
        weapon: 'ak47',
        headshot: true,
        victimTeam: 'A',
        x: 120.5,
        y: -980.2,
        z: 64.0,
      },
      {
        roundNumber: 2,
        victimSteamId: botA,
        killerSteamId: ichSteam,
        weapon: 'awp',
        headshot: true,
        victimTeam: 'A',
        x: 450.0,
        y: -600.0,
        z: 72.0,
      },
    ],
    highlights: [
      { steamId: ichSteam, type: 'ACE', roundNumber: 10, detail: 'Ace' },
      { steamId: ichSteam, type: 'MULTI_KILL', roundNumber: 5, detail: '3 kills' },
    ],
  });
}

async function main(): Promise<void> {
  const opts = parseArgs();
  const siteUrl = process.env.CLUTCH_SITE_URL?.trim() || process.env.SITE_ORIGIN?.trim() || '';
  const syncKey = process.env.CSGO_SKINS_SYNC_KEY?.trim() || '';

  console.log('=== Clutch — simulate match pipeline (sem CS:GO) ===');
  console.log(`roomId:    ${opts.roomId}`);
  console.log(`steam B:   ${opts.ichSteam}`);
  console.log(`score:     ${opts.scoreA}:${opts.scoreB} (winner B)`);
  console.log(`site:      ${siteUrl || '(CLUTCH_SITE_URL não definido)'}`);
  console.log(`sync key:  ${syncKey ? 'set' : 'MISSING'}`);
  if (siteUrl) {
    const reachable = await probeSiteReachable(siteUrl);
    console.log(`site reach: ${reachable ? 'OK' : 'FAIL (fetch failed — rode: bash scripts/check-site-dns.sh)'}`);
  }
  console.log('');

  const match = matchManager.createMatch({
    roomId: opts.roomId,
    teamA: {
      name: 'Team Alpha',
      players: [
        { steamId: '76561197960287931', name: 'Bot Alpha 1' },
        { steamId: '76561197960287932', name: 'Bot Alpha 2' },
      ],
    },
    teamB: {
      name: 'Team Ichi',
      players: [
        { steamId: opts.ichSteam, name: 'ichi' },
        { steamId: '76561197960287933', name: 'Bot Beta 1' },
      ],
    },
    mapPool: ['de_dust2', 'de_mirage'],
  });

  match.status = 'live';
  match.selectedMap = 'de_dust2';
  stateStore.matches.set(match.id, match);
  stateStore.persist();

  const statsJson = buildStatsJson(opts.ichSteam);
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
    ) VALUES (?, ?, ?, ?, ?, ?, 'finished', 'B', 30, ?, ?, ?, ?)`,
  ).run(
    match.id,
    opts.scoreA,
    opts.scoreB,
    opts.scoreA,
    opts.scoreB,
    opts.scoreA + opts.scoreB,
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
