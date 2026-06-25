# Clutch — ambiente local (fixar skins antes da VPS)

Objetivo: **site + api-csgo + CS:GO + plugins** na sua máquina (ou WSL).  
**Postgres pode ficar na VPS/Hostinger** — só o jogo e o SQLite rodam local.

```
┌─────────────────┐     equip      ┌──────────────────┐
│ Site :3000      │ ──────────────►│ api-csgo :3001   │
│ (Next.js)       │  player-sync   │ (Node + pm2)     │
└────────┬────────┘                └────────┬─────────┘
         │                                  │
         │ DATABASE_URL                     │ WEAPONS_DB_PATH
         ▼                                  ▼
┌─────────────────┐                ┌──────────────────┐
│ Postgres (VPS)  │                │ sourcemod-local  │
│ inventário      │                │ .sq3 (SQLite)    │
└─────────────────┘                └────────┬─────────┘
                                            │ RCON
                                            ▼
                                   ┌──────────────────┐
                                   │ CS:GO srcds      │
                                   │ :27015           │
                                   │ bridge + gloves  │
                                   └──────────────────┘
```

Quando tudo estiver estável aqui, replica na VPS com os mesmos `.env` (só mudam paths e IPs).

---

## 1. Pré-requisitos

| Componente | Windows | Notas |
|------------|---------|--------|
| Node 20+ | Sim | site + api-csgo |
| Git | Sim | repos `site` e `api-csgo` |
| WSL2 Ubuntu | **Recomendado** | CS:GO Legacy + SourceMod (scripts do repo são bash) |
| SteamCMD + CS:GO 740 | WSL ou Linux VM | `install.sh` automatiza |
| Postgres | Opcional local | Use `DATABASE_URL` da VPS se quiser |

**Por que WSL?** Os scripts `install-clutch-skins-bridge.sh`, `install.sh`, etc. são Linux. No Windows puro o CS dedicado existe, mas o pipeline Clutch foi testado em Ubuntu.

---

## 2. Setup rápido (Windows + WSL)

### 2.1 WSL — CS:GO + SourceMod + plugins

No **Ubuntu WSL**:

```bash
# Clone (ou use pasta montada: /mnt/c/Users/.../CsgoPage/api-csgo)
cd ~
git clone https://github.com/tiaguinhorak/api-csgo.git
cd api-csgo
cp .env.example .env
# Edite: CSGO_SKINS_SYNC_KEY, CSGO_RCON_PASSWORD, CSGO_GSLT_TOKEN (ou vazio em LAN)

./install.sh --start-game
# ou se CS já instalado: ./install.sh --skip-bootstrap --start-game
```

Anota o path do SQLite (padrão WSL):

`/home/csgo/server/csgo/addons/sourcemod/data/sqlite/sourcemod-local.sq3`

### 2.2 api-csgo no Windows (ou WSL)

**Windows (PowerShell)** — na pasta `api-csgo`:

```powershell
Copy-Item env.local.example .env
# Edite .env — WEAPONS_DB_PATH deve apontar ao SQLite do WSL se CS roda no WSL:
# WEAPONS_DB_PATH=\\wsl$\Ubuntu\home\csgo\server\csgo\addons\sourcemod\data\sqlite\sourcemod-local.sq3

npm install
npm run build
npm run pm2:start
curl http://127.0.0.1:3001/health
```

Se api-csgo roda **dentro do WSL** (mais simples para RCON):

```bash
cd ~/api-csgo
cp .env.local.example .env
# WEAPONS_DB_PATH=/home/csgo/server/csgo/addons/sourcemod/data/sqlite/sourcemod-local.sq3
npm install && npm run build && npm run pm2:start
```

### 2.3 Site no Windows

Na pasta `site`:

```powershell
Copy-Item env.local.example .env
# DATABASE_URL = Postgres da VPS (mesmo de produção)
# CSGO_API_URL=http://127.0.0.1:3001
# CSGO_SKINS_SYNC_KEY = igual api-csgo

npm install
npm run dev
```

Abre: http://localhost:3000

### 2.4 Bridge cfg (warmup local)

No WSL, após `install-clutch-skins-bridge.sh`:

```bash
bash scripts/ensure-warmup-bridge-cfg.sh
# defer_live=0, once_per_match=0 — aplica em cada spawn
```

No console do CS (`screen -r` no WSL):

```text
exec sourcemod/clutch_skins_bridge.cfg
sm plugins reload weapons
sm plugins unload z_clutch_skins_bridge
sm plugins load z_clutch_gloves
sm plugins load z_clutch_skins_bridge
clutch_skins_debug 1
```

---

## 3. Fluxo de teste (checklist)

1. **Health api:** `curl http://127.0.0.1:3001/health` → `glovesPlayerSync: true`
2. **Login site** com Steam (APP_URL=http://localhost:3000 no `.env`)
3. **Equipar** skin + luvas + stickers no inventário
4. **Verificar SQLite** (WSL):

```bash
sqlite3 /home/csgo/server/csgo/addons/sourcemod/data/sqlite/sourcemod-local.sq3 \
  "SELECT steamid, team, weapon_id, paintkit FROM clutch_team_loadout LIMIT 10;"
sqlite3 ... "SELECT steamid, t_group, t_glove, ct_group, ct_glove FROM gloves LIMIT 5;"
```

5. **Conectar** ao CS: `connect localhost:27015` (ou IP WSL)
6. **Console CS:** `sm_clutch_gloves_apply` → `sm_clutch_applyskins`
7. **Log:** versão bridge `v3.8.29+`, paints e stickers aplicados

### Sync em massa (sem equipar)

```bash
cd ~/api-csgo
bash scripts/sync-team-loadouts-warmup.sh
```

Local sempre usa `CLUTCH_SITE_URL=http://127.0.0.1:3000` — sem problema de DNS.

---

## 4. Variáveis críticas (local)

| Variável | site | api-csgo |
|----------|------|----------|
| `CSGO_SKINS_SYNC_KEY` | igual | igual |
| `CSGO_API_URL` | `http://127.0.0.1:3001` | — |
| `CLUTCH_SITE_URL` | — | `http://127.0.0.1:3000` |
| `WEAPONS_DB_PATH` | — | path do `.sq3` |
| `CSGO_RCON_LOOPBACK` | — | `1` |
| `DATABASE_URL` | Postgres VPS | — |

---

## 5. Debug comum

| Problema | Solução |
|----------|---------|
| Equip no site, nada no jogo | `curl` player-sync manual; pm2 logs |
| SQLite vazio | api-csgo não escreve — checar `WEAPONS_DB_PATH` |
| Skins vanilla | `sm plugins reload weapons`; bridge v3.8.28+ |
| Stickers somem | `clutch_skins_debug 1`; `sm_weaponstickers_enabled 0` no cfg |
| Luvas erradas | re-equip no site; `sm_clutch_gloves_refresh` |
| RCON falha | `CSGO_RCON_LOOPBACK=1`, senha igual `server.cfg` |

**Verificação automática:**

```bash
bash scripts/verify-local-stack.sh
```

---

## 6. Quando estiver 100% local → VPS

1. Commit fixes em `api-csgo` e `site`
2. Na VPS: `git pull`, `install-clutch-skins-bridge.sh`, `npm run pm2:restart`
3. `site/.env` produção: `CSGO_API_URL` / `CSGO_WARMUP_API_URL` com IP público
4. **Não** copiar `.env` local — só secrets iguais (`CSGO_SKINS_SYNC_KEY`)
5. Postgres continua centralizado (já é)

---

## 7. Estrutura de pastas (este workspace)

```
CsgoPage/
├── site/           Next.js — inventário, equip, push loadout
├── api-csgo/       API player-sync, SQLite, RCON
└── LOCAL-DEV.md    este arquivo
```

CS:GO instalado fora do repo (WSL: `/home/csgo/server`).
