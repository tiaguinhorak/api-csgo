#!/usr/bin/env bash
# Creates clutch_weaponstickers (+ legacy weaponstickers1) in csgo_weaponstickers.sq3.
# Used by install-clutch-skins-bridge.sh so the bridge can read per-team stickers immediately.

ensure_clutch_stickers_sqlite() {
  local sm_root="${1:?SM root required}"
  local db="${sm_root}/data/sqlite/csgo_weaponstickers.sq3"
  local dir
  dir="$(dirname "${db}")"

  if ! command -v sqlite3 >/dev/null 2>&1; then
    echo "WARN: sqlite3 not installed — bridge will CREATE TABLE on plugin load" >&2
    return 0
  fi

  mkdir -p "${dir}"

  sqlite3 "${db}" <<'SQL'
CREATE TABLE IF NOT EXISTS weaponstickers1 (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  steamid varchar(64) NOT NULL,
  weaponindex int NOT NULL DEFAULT 0,
  slot0 int NOT NULL DEFAULT 0,
  slot1 int NOT NULL DEFAULT 0,
  slot2 int NOT NULL DEFAULT 0,
  slot3 int NOT NULL DEFAULT 0,
  slot4 int NOT NULL DEFAULT 0,
  slot5 int NOT NULL DEFAULT 0,
  wear0 real NOT NULL DEFAULT 0,
  wear1 real NOT NULL DEFAULT 0,
  wear2 real NOT NULL DEFAULT 0,
  wear3 real NOT NULL DEFAULT 0,
  wear4 real NOT NULL DEFAULT 0,
  wear5 real NOT NULL DEFAULT 0,
  rotation0 real NOT NULL DEFAULT 0,
  rotation1 real NOT NULL DEFAULT 0,
  rotation2 real NOT NULL DEFAULT 0,
  rotation3 real NOT NULL DEFAULT 0,
  rotation4 real NOT NULL DEFAULT 0,
  rotation5 real NOT NULL DEFAULT 0,
  last_seen int NOT NULL DEFAULT 0,
  UNIQUE(steamid, weaponindex)
);
CREATE TABLE IF NOT EXISTS clutch_weaponstickers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  steamid varchar(64) NOT NULL,
  weaponindex int NOT NULL DEFAULT 0,
  team varchar(2) NOT NULL DEFAULT 'CT',
  slot0 int NOT NULL DEFAULT 0,
  slot1 int NOT NULL DEFAULT 0,
  slot2 int NOT NULL DEFAULT 0,
  slot3 int NOT NULL DEFAULT 0,
  slot4 int NOT NULL DEFAULT 0,
  slot5 int NOT NULL DEFAULT 0,
  wear0 real NOT NULL DEFAULT 0,
  wear1 real NOT NULL DEFAULT 0,
  wear2 real NOT NULL DEFAULT 0,
  wear3 real NOT NULL DEFAULT 0,
  wear4 real NOT NULL DEFAULT 0,
  wear5 real NOT NULL DEFAULT 0,
  last_seen int NOT NULL DEFAULT 0,
  UNIQUE(steamid, weaponindex, team)
);
SQL

  echo "SQLite sticker tables OK: ${db}"
  sqlite3 "${db}" ".tables" | tr '\n' ' '
  echo ""

  local twin_db="${sm_root}/addons/sourcemod/data/sqlite/csgo_weaponstickers.sq3"
  if [[ -f "${twin_db}" && "${twin_db}" != "${db}" ]]; then
    local twin_rows real_rows
    twin_rows="$(sqlite3 "${twin_db}" "SELECT COUNT(*) FROM clutch_weaponstickers;" 2>/dev/null || echo 0)"
    real_rows="$(sqlite3 "${db}" "SELECT COUNT(*) FROM clutch_weaponstickers;" 2>/dev/null || echo 0)"
    if [[ "${twin_rows}" -eq 0 && "${real_rows}" -gt 0 ]]; then
      echo "Removing empty twin stickers DB (wrong SM sqlite path): ${twin_db}"
      rm -f "${twin_db}"
    fi
  fi
}
