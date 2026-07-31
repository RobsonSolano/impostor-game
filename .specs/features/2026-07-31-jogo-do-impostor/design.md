# Design — Jogo do Impostor (v1)

## Modelo de dados

```
words ──────────┐
(200 palavras)  │
                ▼
rooms ◄──── rounds ────► player_cards
  │            │  (segredo)   (visão individual)
  │            │
  ├──► players │
  │            │
  └──► votes ◄─┘
```

### `words` — banco de palavras

| Coluna | Tipo | Nota |
|---|---|---|
| `id` | `int` PK | |
| `text` | `text` UNIQUE | Ex: `Hospital` |
| `category` | `word_category` | Enum de 10 categorias |

Leitura liberada para `authenticated` — conhecer as 200 palavras não revela qual foi sorteada. Usada também para montar as 4 opções da Última Chance (3 distratores da **mesma** categoria).

### `rooms` — estado público da mesa

| Coluna | Tipo | Nota |
|---|---|---|
| `id` | `uuid` PK | |
| `code` | `char(4)` UNIQUE | Alfabeto sem `I`/`O`/`0`/`1` |
| `status` | `room_status` | `LOBBY, WORD_REVEAL, DISCUSSION, VOTING, LAST_CHANCE, GAME_OVER` |
| `host_player_id` | `uuid` FK → players | Nullable (a sala nasce antes do host) |
| `active_round_id` | `uuid` FK → rounds | Nullable |
| `discussion_round` | `int` | 1, 2, 3… só para exibição |
| `voting_cycle` | `int` | Incrementa a cada abertura de votação |
| `votes_cast` | `int` | Progresso do ciclo atual, sem revelar em quem |
| `guess_deadline` | `timestamptz` | Prazo da Última Chance |
| `outcome` | `game_outcome` | `TRUTHERS_WIN, IMPOSTOR_WIN, IMPOSTOR_STEAL`. Null até GAME_OVER |
| `eliminated_player_id` | `uuid` | Quem levou a maioria |
| `revealed_word` | `text` | **Só preenchido em GAME_OVER** |
| `revealed_impostor_id` | `uuid` | **Só preenchido em GAME_OVER** |
| `last_vote_tally` | `jsonb` | Apuração do último ciclo, gravada só depois de resolvida |
| `games_played` | `int` | Partidas concluídas na sala |
| `created_at` / `updated_at` | `timestamptz` | |

**Nenhuma coluna de segredo ativo.** É o que permite liberar `SELECT` desta linha via Realtime para todos os jogadores da sala.

### `players`

| Coluna | Tipo | Nota |
|---|---|---|
| `id` | `uuid` PK | Identidade **dentro da sala** |
| `room_id` | `uuid` FK → rooms | |
| `user_id` | `uuid` FK → auth.users | Sessão anônima |
| `name` | `text` | UNIQUE por sala (case-insensitive) |
| `avatar_color` | `text` | Hex, atribuído em ordem de entrada |
| `is_alive` | `boolean` | Reservado para saída de jogador |
| `score` | `int` | Acumulado na sala |
| `has_seen_card` | `boolean` | Reset a cada rodada; fecha a fase WORD_REVEAL |
| `joined_at` | `timestamptz` | Ordem de entrada |

UNIQUE `(room_id, user_id)` — o mesmo usuário não duplica na mesma sala.

### `rounds` — **segredo, sem grants**

| Coluna | Tipo | Nota |
|---|---|---|
| `id` | `uuid` PK | |
| `room_id` | `uuid` FK → rooms | |
| `round_number` | `int` | Nº da partida na sala |
| `word_id` | `int` FK → words | 🔒 |
| `impostor_player_id` | `uuid` FK → players | 🔒 |
| `last_chance_word_ids` | `int[]` | 🔒 As 4 opções, já embaralhadas |
| `resolved_at` | `timestamptz` | |

Zero `GRANT` para `anon`/`authenticated`. Só as funções `SECURITY DEFINER` alcançam.

### `player_cards` — visão individual

| Coluna | Tipo | Nota |
|---|---|---|
| `round_id` | `uuid` FK → rounds | PK composta |
| `player_id` | `uuid` FK → players | PK composta |
| `room_id` | `uuid` FK → rooms | Denormalizado para filtro |
| `is_impostor` | `boolean` | |
| `word_text` | `text` | **NULL** para o impostor |
| `last_chance_options` | `text[]` | Preenchido só no card do impostor, só em LAST_CHANCE |

RLS: `SELECT` permitido apenas quando o `player_id` pertence a um `players` cujo `user_id = auth.uid()`.

### `votes` — sem `SELECT` para o cliente

| Coluna | Tipo | Nota |
|---|---|---|
| `id` | `uuid` PK | |
| `room_id` / `round_id` | `uuid` | |
| `voting_cycle` | `int` | |
| `voter_player_id` | `uuid` | |
| `target_player_id` | `uuid` NULL | `NULL` = "Pular Votação" |

UNIQUE `(round_id, voting_cycle, voter_player_id)` — um voto por ciclo, garantido pelo banco e não pela UI.

## Contratos das RPCs

Todas: `SECURITY DEFINER`, `SET search_path = public, pg_temp`, `SELECT ... FROM rooms WHERE id = p_room_id FOR UPDATE` antes de decidir, validação de `auth.uid()`, e `RAISE EXCEPTION` com `errcode` próprio em violação.

| Função | Quem pode | Fase exigida | Efeito |
|---|---|---|---|
| `create_room(p_name, p_avatar_color)` | qualquer sessão | — | Cria sala + host. Retorna `{room_id, player_id, code}` |
| `join_room(p_code, p_name, p_avatar_color)` | qualquer sessão | LOBBY | Cria player. Retorna `{room_id, player_id, code}` |
| `start_game(p_room_id)` | host | LOBBY (≥3 jogadores) | Sorteia palavra + impostor, cria round e cards → WORD_REVEAL |
| `confirm_word_seen(p_room_id)` | jogador da sala | WORD_REVEAL | Marca `has_seen_card`. Último → DISCUSSION |
| `open_voting(p_room_id)` | host | DISCUSSION | `voting_cycle++`, zera `votes_cast` → VOTING |
| `cast_vote(p_room_id, p_target_player_id)` | jogador vivo | VOTING | Insere voto. Último → apura |
| `submit_impostor_guess(p_room_id, p_word_text)` | impostor | LAST_CHANCE, dentro do prazo | Decide `IMPOSTOR_STEAL` ou `TRUTHERS_WIN` → GAME_OVER |
| `expire_last_chance(p_room_id)` | jogador da sala | LAST_CHANCE, prazo vencido | Idempotente → `TRUTHERS_WIN` |
| `play_again(p_room_id)` | host | GAME_OVER | Nova palavra não repetida, novo impostor → WORD_REVEAL |
| `leave_room(p_room_id)` | jogador da sala | — | Marca `is_alive = false` |

### Interno: apuração (`resolve_voting`)

Chamado por `cast_vote` quando `votes_cast` alcança o número de jogadores vivos. Nunca exposto.

```
tally = contagem por target (NULL agrupado como "skip")
top   = maior contagem entre targets NÃO-nulos
winners = targets com contagem == top

SE skip_count >= top           → devolve para discussão   (IMP-13)
SENÃO SE count(winners) > 1    → devolve para discussão   (IMP-13, empate)
SENÃO eliminado = winners[0]
  SE eliminado == impostor     → LAST_CHANCE              (IMP-15)
  SENÃO                        → GAME_OVER / IMPOSTOR_WIN (IMP-14)
```

"Devolve para discussão" = `discussion_round++`, `status = DISCUSSION`, `votes_cast = 0`, `last_vote_tally` gravado.

### Overrides de teste

`start_game` e `play_again` aceitam `p_force_word_id int DEFAULT NULL` e `p_force_impostor_id uuid DEFAULT NULL`. Ignorados quando nulos. Existem para tornar o sorteio determinístico no pgTAP — sem isso não há como testar "impostor eliminado" de forma estável.

## Cliente

### Realtime

Duas subscriptions em um único canal por sala:

```ts
channel(`room:${roomId}`)
  .on('postgres_changes', { event: '*', schema: 'public', table: 'rooms',   filter: `id=eq.${roomId}` },     …)
  .on('postgres_changes', { event: '*', schema: 'public', table: 'players', filter: `room_id=eq.${roomId}` }, …)
```

`player_cards` **não** entra no Realtime. É buscado quando `rooms.status` vira `WORD_REVEAL` ou `LAST_CHANCE` — o gatilho já chega pela subscription de `rooms`, e uma terceira subscription só adicionaria superfície de RLS-em-Realtime sem ganho.

### Componentes

| Componente | Papel |
|---|---|
| `GameRoom` | Assina o canal, resolve o jogador atual, faz switch em `status` |
| `LobbyPhase` | Código grande e copiável, roster, botão do host com contagem mínima |
| `WordRevealPhase` | `HoldToReveal` + botão "Já vi minha palavra" |
| `DiscussionPhase` | Rodada atual, roster, botão "Abrir votação" só para o host |
| `VotingPhase` | Grid de suspeitos + "Pular Votação", carimbo animado, contador de votos |
| `LastChancePhase` | Impostor: 4 opções + timer de 15s. Demais: tela de suspense |
| `GameOverPhase` | Drumroll 3s → resultado, impostor, palavra, apuração, placar, "Jogar Novamente" |
| `HoldToReveal` | Press-and-hold com progresso de 2s. Lógica testável isolada aqui |

### Estado local permitido

Só o visual: progresso do hold, contagem do drumroll, suspeito selecionado antes de confirmar, segundos restantes do timer. Nada de regra.

## Riscos assumidos neste design

- **Host ausente trava a sala** (`CONCERNS.md` #2). Aceito no v1.
- **`LAST_CHANCE` depende de um cliente vivo chamar `expire_last_chance`** (`CONCERNS.md` #3). Idempotente, então um cliente basta.
- **Jogador fantasma pode travar a apuração** (`CONCERNS.md` #4), já que ela espera todos os vivos votarem.
