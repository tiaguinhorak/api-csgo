'use strict';

const fs = require('fs');
const path = require('path');

const {
  syncPlayerStickersToDb,
  closeStickersDatabase,
} = require('../dist/services/stickers-db-sync');

const inputPath = process.argv[2] || '/tmp/clutch-site-stickers.json';

async function main() {
  if (!fs.existsSync(inputPath)) {
    console.error(`Missing ${inputPath} — run fetch-site-stickers.sh first`);
    process.exit(1);
  }

  const raw = fs.readFileSync(inputPath, 'utf8');
  const data = JSON.parse(raw);
  const stickers = data.stickers;

  if (!Array.isArray(stickers)) {
    console.error('Invalid JSON: expected { stickers: [...] }');
    process.exit(1);
  }

  let synced = 0;
  const errors = [];

  for (const row of stickers) {
    if (!row?.steamId || !Array.isArray(row.entries)) {
      continue;
    }
    try {
      await syncPlayerStickersToDb(row.steamId, row.entries, {
        replacePlayerState: true,
      });
      synced += 1;
      console.log(`OK ${row.steamId} (${row.entries.length} weapons)`);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      errors.push(`${row.steamId}: ${message}`);
      console.error(`FAIL ${row.steamId}: ${message}`);
    }
  }

  console.log(
    JSON.stringify({
      ok: errors.length === 0,
      synced,
      errors,
      input: path.resolve(inputPath),
    }),
  );

  if (synced === 0 || errors.length > 0) {
    process.exit(1);
  }
}

main()
  .catch((err) => {
    console.error(err);
    process.exit(1);
  })
  .finally(() => {
    try {
      closeStickersDatabase();
    } catch {
      /* ignore */
    }
  });
