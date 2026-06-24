# Instalação unificada Clutch (VPS CS:GO)

Um **único stack** para ranked, warmup, deathmatch, surf, retake, KZ, etc. O que muda entre servidores é só o `.env` (perfil da sala + IP/porta/screen).

## Quick start (nova VPS — um script)

`./install.sh` faz **tudo** no Ubuntu (idempotente — só instala o que falta):

1. apt (git, screen, libs 32-bit para srcds)
2. Node.js 20
3. SteamCMD
4. CS:GO Legacy dedicado (Steam app **740**)
5. MetaMod + SourceMod
6. npm build + **pm2** (api-csgo)
7. plugins Clutch (skins, gloves, gate, stickers)
8. sync allowlist + loadouts do site

**Não precisa Docker.** CS:GO Legacy + SourceMod rodam melhor no host.

```bash
# VPS Ubuntu — usuário dedicado (recomendado)
sudo adduser csgo
sudo usermod -aG sudo csgo
su - csgo

git clone https://github.com/tiaguinhorak/api-csgo.git
cd api-csgo
cp .env.example .env
nano .env   # SERVER_PROFILE, CSGO_SKINS_SYNC_KEY, GSLT, RCON, screen

./install.sh --start-game   # bootstrap + deploy + inicia srcds
```

Só atualizar código/plugins depois:

```bash
cd ~/api-csgo && ./deploy.sh
```

Opções úteis:

| Comando | Quando |
|---------|--------|
| `./install.sh` | VPS nova ou reinstalar stack |
| `./install.sh --skip-csgo` | CS:GO já baixado |
| `./install.sh --skip-bootstrap` | só npm/pm2/plugins |
| `./install.sh --start-game` | deploy + screen srcds |

## O que é igual em TODOS os servidores

| Componente | Descrição |
|------------|-----------|
| api-csgo (pm2) | player-sync, SQLite skins/gloves, RCON |
| `z_clutch_gloves` + `z_clutch_skins_bridge` | skins do site, 1x por partida |
| `clutch_platform_gate` | Steam allowlist |
| Stickers (opcional) | weaponstickers |
| Sync site → SQLite | loadouts + weapons_english.cfg |
| `CSGO_SKINS_SYNC_KEY` | **mesmo valor** no site e em cada VPS |

## O que muda por servidor (.env)

| Variável | Exemplo ranked | Exemplo deathmatch |
|----------|----------------|-------------------|
| `SERVER_PROFILE` | `ranked` | `deathmatch` |
| `SERVER_NAME` | `Clutch #1` | `DM SP #1` |
| `SERVER_MODE_LABEL` | `Competitivo` | `Deathmatch` |
| `CSGO_SERVER_POOL` | `ranked` | `warmup` |
| `CLUTCH_CS_SCREEN` | `csgo-clutch-#1` | `csgo-dm-#1` |
| `CSGO_GSLT_TOKEN` | token Steam | outro token |
| `CSGO_GAME_TYPE/MODE` | 0/1 | conforme modo |
| `CSGO_PUBLIC_HOST` | IP público | IP público |

Perfis `warmup`, `deathmatch`, `surf`, `retake`, `kz`, `casual`, etc. usam o **mesmo pipeline público**:

- skins instantâneas (`defer_live=0`)
- sem match tracker
- extras: nolobby, steamfix, ptah
- `BIND_HOST=0.0.0.0` (site push via LAN)

Perfil `ranked`:

- match tracker
- skins staged durante partida (defer default)
- pool `ranked` na API (fila 5v5)

## Site (Hostinger)

Cada nova VPS precisa aparecer no push de equip:

```env
CSGO_API_URL=http://188.220.168.233:3001
CSGO_WARMUP_API_URL=http://192.168.100.5:3001
CSGO_API_URLS=http://dm-vps:3001,http://surf-vps:3001
```

`CSGO_SKINS_SYNC_KEY` e `API_KEY` iguais em site e todas as VPS.

## Docker?

**Não.** Este repo não usa Docker para o stack de jogo.

| Parte | Docker? | Recomendação |
|-------|---------|--------------|
| **Tudo (CS:GO + API + plugins)** | Não implementado | **`./install.sh`** no Ubuntu |
| **api-csgo** | Possível no futuro | Hoje: pm2 local via deploy |
| **CS:GO srcds** | Problemático | SteamCMD, GSLT, screen, app 740 Legacy |
| **Site Next.js** | Hostinger/Vercel | Separado do VPS de jogo |

**Conclusão:** um único script bash (`install.sh`) cobre npm, pm2, download do servidor, skins e plugins. Docker só faria sentido depois para **só a API**, não para CS:GO Legacy completo.

## Scripts

| Script | Uso |
|--------|-----|
| `./install.sh` | **Completo:** OS + CS:GO + npm + pm2 + plugins + sync |
| `./deploy.sh` | Git pull + build + plugins + sync (sem baixar CS:GO) |
| `scripts/bootstrap-vps.sh` | Só pré-requisitos + SteamCMD + CS:GO + SourceMod |
| `scripts/deploy-unified.sh` | Mesmo que deploy.sh |
| `scripts/deploy-unified.sh --profile=surf` | Override perfil |
| `scripts/start-csgo-screen.sh` | Subir srcds no screen |

## Checklist novo servidor

1. Copiar `.env.example` → `.env`
2. `SERVER_PROFILE` + `SERVER_MODE_LABEL` + `CLUTCH_CS_SCREEN`
3. `CSGO_SKINS_SYNC_KEY` = site
4. `CSGO_GSLT_TOKEN` = token Steam Game Server Login
5. `./install.sh --start-game`
6. No **site** `.env`: adicionar URL em `CSGO_API_URLS`
7. No admin site: editar servidor → modo (Deathmatch, etc.) se necessário

## Troubleshooting skins

Igual em qualquer VPS — um deploy resolve:

```bash
cd ~/api-csgo && ./deploy.sh
bash scripts/reload-clutch-skins-ingame.sh
```

Verificar bridge ≥ 3.8.7, gloves 1.4.3, sem `gloves.smx` kgns ativo.
