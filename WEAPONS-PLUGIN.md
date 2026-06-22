# Weapons & Knives (`!ws`) — Comandos e uso

Plugin: **Weapons & Knives** (kgns) — skins de armas, facas, float, StatTrak e name tag.  
Versão de referência: **v1.7.8**  
Requisitos no servidor: **SourceMod**, extensão **PTaH**, `core.cfg` com `"FollowCSGOServerGuidelines" "no"`.

---

## Comandos no chat (jogadores)

Use no **chat** do jogo (`Y` ou `U`). O prefixo `!` vem do `PublicChatTrigger` no `core.cfg`.

| Comando | Alias | O que faz |
|---------|-------|-----------|
| `!ws` | — | Abre o **menu principal** de skins de armas |
| `!skin` | — | Igual `!ws` |
| `!skins` | — | Igual `!ws` |
| `!knife` | — | Abre o menu de **faca** (modelo + skin da faca) |
| `!wslang` | — | Troca o **idioma** do menu (inglês, turco, etc.) |
| `/ws` | `/skin`, `/skins` | Igual `!ws`, mas **não aparece** no chat (trigger silencioso `/`) |
| `/knife` | — | Menu de faca silencioso |

> **Nota:** `!nametag` existia em versões antigas. Nas versões recentes, name tag é configurado **dentro do menu `!ws`** (opções da arma).

### Atalhos de console do jogo (bind)

O plugin também registra (podem ser bloqueados em servidores competitivos):

| Comando interno | Equivalente |
|-----------------|-------------|
| `buyammo1` | Menu `!ws` |
| `buyammo2` | Menu `!knife` |

### Busca de skin (versões com search)

Em builds/forks que incluem busca:

```text
!ws asiimov
!ws dragon
```

Mostra skins que batem com o texto. Na **v1.7.8 oficial** isso pode **não** existir.

---

## Comandos no console do servidor (RCON / screen)

Só funcionam no **console do servidor** ou com **admin** no cliente (depende de flags).

| Comando | Quem | O que faz |
|---------|------|-----------|
| `sm_ws` | Jogador (console) | Menu de armas (se o cliente permite) |
| `sm_skin` | Jogador | Igual `sm_ws` |
| `sm_skins` | Jogador | Igual `sm_ws` |
| `sm_knife` | Jogador | Menu de faca |
| `sm_wslang` | Jogador | Idioma do menu |
| `sm_plugins reload weapons` | Admin | Recarrega o plugin (pode exigir restart de mapa) |
| `sm plugins list` | Admin | Ver se `Weapons & Knives` está **Loaded** |
| `meta list` | Admin | Ver se **PTaH** está carregado |
| `mp_restartgame 1` | Admin | Reinicia o round (útil após trocar skin) |

---

## Como usar os menus

### Menu `!ws` (armas)

1. Digite `!ws` no chat.
2. Escolha uma opção (varia por versão/idioma):
   - **Knives** — atalho para facas (ou use `!knife` direto).
   - **All weapons** / lista por categoria — escolhe a arma.
3. Na arma escolhida:
   - **Skin** — paint da arma.
   - **Wear / Float** — condição (Factory New, etc.) ou valor customizado.
   - **StatTrak** — liga/desliga contador.
   - **Seed** — padrão da skin (se habilitado).
   - **Name tag** — etiqueta na arma (se habilitado).
4. Após escolher, a arma em mão **atualiza**; se não mudar:
   - morra e respawne, ou
   - `mp_restartgame 1`, ou
   - compre a arma de novo.

### Menu `!knife` (faca)

1. Digite `!knife` no chat.
2. Escolha o **modelo** da faca (Karambit, M9, Butterfly, etc.).
3. Escolha a **skin** da faca.
4. Opções extras (se no menu): float, StatTrak, name tag.
5. A faca atualiza na próxima spawn ou após restart de round.

### StatTrak

- O contador **não** sobe na mesma arma instantaneamente após kill; atualiza quando você **pega uma arma nova** / novo round.
- `sm_weapons_knife_stattrak_mode` controla se todas as facas compartilham o mesmo contador ou um por tipo.

---

## Configuração do servidor (`cfg/sourcemod/weapons.cfg`)

Arquivo gerado após o primeiro load do plugin. CVars principais:

| Cvar | Default | Descrição |
|------|---------|-----------|
| `sm_weapons_db_connection` | `storage-local` | Banco SQLite local (`databases.cfg`) |
| `sm_weapons_table_prefix` | `""` | Prefixo das tabelas MySQL |
| `sm_weapons_chat_prefix` | `[oyunhost.net]` | Prefixo nas mensagens do plugin no chat |
| `sm_weapons_knife_stattrak_mode` | `0` | `0` = StatTrak único para facas; `1` = por tipo de faca |
| `sm_weapons_enable_float` | `1` | Menu de float/wear |
| `sm_weapons_enable_nametag` | `1` | Name tags no menu |
| `sm_weapons_enable_stattrak` | `1` | StatTrak no menu |
| `sm_weapons_enable_seed` | `1` | Seed no menu |
| `sm_weapons_float_increment_size` | `0.05` | Passo ao ajustar float |
| `sm_weapons_enable_overwrite` | `1` | `!ws` pode “tomar” skin de arma dropada no chão |
| `sm_weapons_grace_period` | `0` | Segundos após início do round para permitir `!ws`; `0` = sempre |
| `sm_weapons_inactive_days` | `30` | Dias para apagar dados de jogador inativo (`0` = nunca) |

Edite e aplique:

```text
exec sourcemod/weapons.cfg
```

ou reinicie o servidor.

---

## `core.cfg` (obrigatório para skins funcionar)

```text
"FollowCSGOServerGuidelines" "no"
```

Sem isso o menu abre mas a skin **não aplica** (erro `Cannot set m_iItemIDLow` no log).

Reinício **completo** do `srcds` após alterar `core.cfg`.

---

## Arquivos importantes na VPS

```text
/home/csgo/server/csgo/addons/sourcemod/plugins/weapons.smx
/home/csgo/server/csgo/addons/sourcemod/extensions/PTaH.ext.2.csgo.so
/home/csgo/server/csgo/addons/sourcemod/configs/core.cfg
/home/csgo/server/csgo/cfg/sourcemod/weapons.cfg
/home/csgo/server/csgo/addons/sourcemod/configs/weapons/   # listas de skins por idioma
/home/csgo/server/csgo/addons/sourcemod/logs/errors_*.log
```

---

## Integração com a API Clutch (skins da loja)

O `!ws` é menu **manual**. Para aplicar skins que o jogador **comprou/equipou** no site:

1. API: `GET /api/skins/export` (header `x-api-key`).
2. Cron na VPS gera arquivo KeyValues (ex.: `skins.txt`).
3. Plugin bridge ou lógica customizada lê o arquivo no spawn.

Fluxo documentado em `README.md` (seção Skins). O `!ws` continua útil para teste e skins fora do loadout.

---

## Troubleshooting rápido

| Problema | Solução |
|----------|---------|
| Menu abre, skin não muda | `FollowCSGOServerGuidelines` → `no` + restart completo |
| `!knife` ok, armas não | Escolher skin dentro de `!ws` → All weapons → arma específica |
| Faca sem paint | Usar `!knife`, não só skin de knife dentro de `!ws` |
| Erro no log PTaH | Reinstalar PTaH Linux; tentar v1.1.3 se GLIBC falhar |
| Comando não responde | Estar **vivo**, no time, fora do `grace_period` |

---

## Links

- Plugin: https://github.com/kgns/weapons  
- PTaH: https://github.com/komashchenko/PTaH  
- AlliedModders: https://forums.alliedmods.net/showthread.php?t=298770  
