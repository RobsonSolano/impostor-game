# Arquitetura

## Princípio central: o banco é a autoridade do jogo

O cliente **nunca** decide nada de jogo. Ele lê estado e chama RPC. Toda transição de fase é uma função `SECURITY DEFINER` no Postgres que:

1. Toma lock da linha da sala (`SELECT ... FOR UPDATE`).
2. Valida quem está chamando via `auth.uid()`.
3. Valida se a transição é legal a partir do `status` atual.
4. Escreve o novo estado.

O `UPDATE` resultante é, ele mesmo, o evento de Realtime que sincroniza todos os celulares. Não existe "servidor de jogo" separado.

Por que não Server Actions com service role: latência extra, e o lock ainda teria que existir no banco. A corrida real (dois votos chegando juntos, palpite chegando junto com a expiração do timer) só se resolve em transação.

## Como o segredo do impostor não vaza

Este é o problema de design mais importante do projeto.

RLS do Postgres filtra **linhas**, não **colunas**. Se a palavra secreta estivesse em `rooms`, todo jogador inscrito no Realtime daquela sala receberia o payload completo — e leria a palavra no DevTools em 5 segundos.

Separação adotada:

```
rounds        ← segredo bruto (word_id, impostor_player_id, opções do palpite)
              ← ZERO grants para anon/authenticated. Só funções SECURITY DEFINER tocam.

player_cards  ← uma linha por (rodada, jogador): is_impostor, word_text
              ← RLS: só leio a linha cujo player pertence ao meu auth.uid()
              ← impostor recebe word_text = NULL

rooms         ← estado público da mesa: status, rodada, contadores, resultado
              ← revealed_word / revealed_impostor_id só são preenchidos em GAME_OVER
```

`votes` também não tem grant de `SELECT`: o progresso da votação aparece como contador em `rooms.votes_cast`, e a apuração final como `rooms.last_vote_tally` (jsonb). Assim ninguém descobre em quem o outro votou antes da revelação.

## Fluxo de dados

```
┌────────────┐   rpc()      ┌──────────────────────┐
│  Cliente   │ ───────────► │  Funções SQL         │
│ (browser)  │              │  SECURITY DEFINER    │
│            │              └──────────┬───────────┘
│            │                         │ UPDATE
│            │   postgres_changes      ▼
│            │ ◄─────────── ┌──────────────────────┐
└────────────┘   (realtime) │  rooms / players     │
      │                     └──────────────────────┘
      │  fetch pontual
      ▼
┌──────────────────┐
│  player_cards    │  ← só a MINHA linha (RLS)
└──────────────────┘
```

- **Realtime (`postgres_changes`)**: `rooms` filtrado por `id`, `players` filtrado por `room_id`. São as duas únicas subscriptions.
- **Fetch pontual**: `player_cards` é buscado quando o `status` entra em `WORD_REVEAL` ou `LAST_CHANCE`. Não precisa de subscription — o gatilho é a mudança de `rooms.status`, que já chega por Realtime.

## Máquina de estados

```
LOBBY
  │ start_game (host, min 3 jogadores)
  ▼
WORD_REVEAL ──── todos confirmaram (confirm_word_seen)
  │                              │
  │                              ▼
  │                        DISCUSSION ◄──────────┐
  │                              │ open_voting   │ empate ou "pular" venceu
  │                              ▼               │ (discussion_round + 1)
  │                          VOTING ─────────────┘
  │                              │ maioria simples em alguém
  │                    ┌─────────┴──────────┐
  │                    ▼                    ▼
  │            votado = impostor     votado = inocente
  │                    │                    │
  │                    ▼                    │
  │              LAST_CHANCE                │
  │              (15s, 4 opções)            │
  │                    │                    │
  │           ┌────────┴────────┐           │
  │           ▼                 ▼           ▼
  │      acertou           errou/expirou    │
  │           │                 │           │
  ▼           ▼                 ▼           ▼
GAME_OVER (outcome: IMPOSTOR_STEAL | TRUTHERS_WIN | IMPOSTOR_WIN)
  │ play_again (host) → nova palavra, novo impostor
  └──────► WORD_REVEAL
```

A fase de discussão **não** tem ordem de fala nem timer. O grupo conversa ao vivo; o app só espera o host tocar em "Abrir votação".

## Estrutura de rotas

| Rota | Tipo | Papel |
|---|---|---|
| `/` | Client | Criar sala ou entrar com nickname + código |
| `/sala/[code]` | Server shell + Client | Resolve `await params`, monta o cliente de jogo que faz o switch por `status` |

Uma rota só para o jogo inteiro. As fases são componentes trocados por estado, não por navegação — evita perder a conexão de Realtime a cada transição.

## Sessão e identidade

`supabase.auth.signInAnonymously()` no primeiro acesso gera um `auth.users` real e um `auth.uid()` estável na sessão. `players.user_id` referencia esse uid; `players.id` é a identidade *dentro da sala* (o mesmo usuário pode estar em salas diferentes). Fechar a aba e voltar mantém a sessão (cookie) e portanto o mesmo `player_id`.
