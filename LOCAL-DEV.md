# Clutch — dev local (site) + CS:GO na VPS

**CS:GO dedicado roda na VPS (Linux).** Não há suporte para servidor CS no Windows nativo.

No PC você pode rodar só o **site** (`npm run dev`) apontando ao Postgres (Hostinger) e à **api-csgo na VPS**.

```
┌─────────────────┐     equip      ┌──────────────────┐     RCON    ┌──────────────────┐
│ Site :3000      │ ──────────────►│ api-csgo VPS     │ ───────────►│ CS:GO srcds VPS  │
│ (local)         │  player-sync   │ :3001            │             │ :27015           │
└────────┬────────┘                └──────────────────┘             └──────────────────┘
         │
         │ DATABASE_URL
         ▼
┌─────────────────┐
│ Postgres (VPS)  │
└─────────────────┘
```

Deploy do jogo: `api-csgo` na VPS com `./install.sh` ou `bash scripts/install-clutch-skins-bridge.sh`.

---

## 1. Pré-requisitos (dev no PC)

| Componente | Notas |
|------------|--------|
| Node 20+ | site local |
| Git | repos `site` e `api-csgo` |
| Postgres | `DATABASE_URL` da Hostinger no `site/.env` |
| CS:GO + api-csgo | **Na VPS** — ver `install.sh` / `UNIFIED-INSTALL.md` |

---

## 2. Site local → VPS

```powershell
cd site
npm run dev
```

No `site/.env`:
- `CSGO_API_URL` = URL da api na VPS (ex. `http://188.220.168.233:3001`)
- `DATABASE_URL` = Postgres Hostinger
- `CSGO_SKINS_SYNC_KEY` = igual à VPS

Equip no site → push na api-csgo da VPS → SQLite na VPS → RCON no srcds.

---

## 3. VPS (CS:GO + api-csgo)

```bash
cd ~/api-csgo
git pull
cp .env.example .env   # editar secrets
./install.sh --skip-bootstrap   # ou install-clutch-skins-bridge.sh
bash scripts/sync-team-loadouts-warmup.sh
```

Ver `UNIFIED-INSTALL.md` e `README` na VPS.

---

## 4. Variáveis críticas

| Variável | site | api-csgo (VPS) |
|----------|------|----------------|
| `CSGO_SKINS_SYNC_KEY` | igual | igual |
| `CSGO_API_URL` | IP VPS :3001 | — |
| `CLUTCH_SITE_URL` | — | URL do site |
| `WEAPONS_DB_PATH` | — | path Linux `.sq3` |
| `DATABASE_URL` | Postgres | — |

---

## 5. Estrutura

```
CsgoPage/
├── site/       Next.js
└── api-csgo/   API + scripts Linux (deploy na VPS)
```
