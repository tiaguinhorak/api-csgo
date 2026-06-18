import fs from 'fs';
import path from 'path';
import type { GameServer } from '../models/server';
import type { Match } from '../models/match';

type Snapshot = {
  servers: GameServer[];
  matches: Match[];
};

const dataDir = process.env.DATA_DIR || path.join(process.cwd(), 'data');
const storePath = path.join(dataDir, 'store.json');

function readSnapshot(): Snapshot {
  try {
    if (!fs.existsSync(storePath)) {
      return { servers: [], matches: [] };
    }
    const parsed = JSON.parse(fs.readFileSync(storePath, 'utf8')) as Partial<Snapshot>;
    return {
      servers: Array.isArray(parsed.servers) ? parsed.servers : [],
      matches: Array.isArray(parsed.matches) ? parsed.matches : [],
    };
  } catch {
    return { servers: [], matches: [] };
  }
}

function writeSnapshot(snapshot: Snapshot): void {
  fs.mkdirSync(dataDir, { recursive: true });
  fs.writeFileSync(storePath, JSON.stringify(snapshot, null, 2), 'utf8');
}

class StateStore {
  readonly servers = new Map<string, GameServer>();
  readonly matches = new Map<string, Match>();
  private flushTimer: ReturnType<typeof setTimeout> | null = null;

  constructor() {
    const snapshot = readSnapshot();
    for (const server of snapshot.servers) {
      this.servers.set(server.id, server);
    }
    for (const match of snapshot.matches) {
      this.matches.set(match.id, match);
    }
  }

  persist(): void {
    if (this.flushTimer) clearTimeout(this.flushTimer);
    this.flushTimer = setTimeout(() => {
      this.flushTimer = null;
      writeSnapshot({
        servers: Array.from(this.servers.values()),
        matches: Array.from(this.matches.values()),
      });
    }, 150);
  }
}

export const stateStore = new StateStore();
