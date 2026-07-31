-- Jogo do Impostor — schema base
--
-- Princípio de segurança que governa este arquivo:
-- RLS do Postgres filtra LINHAS, não COLUNAS. Toda coluna de `rooms` é visível
-- para qualquer jogador inscrito no Realtime daquela sala. Por isso a palavra
-- secreta e a identidade do impostor NÃO vivem em `rooms` — vivem em `rounds`
-- (sem nenhum grant para o cliente) e são entregues individualmente por
-- `player_cards`. Ver .specs/codebase/ARCHITECTURE.md.

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

create type word_category as enum (
  'LUGARES',
  'COMIDAS',
  'ANIMAIS',
  'PROFISSOES',
  'OBJETOS',
  'TECH',
  'ESPORTES',
  'CULTURA_POP',
  'TRANSPORTES',
  'EVENTOS'
);

create type room_status as enum (
  'LOBBY',
  'WORD_REVEAL',
  'DISCUSSION',
  'VOTING',
  'LAST_CHANCE',
  'GAME_OVER',
  -- Terminal: o host encerrou a sala e todos voltam para a tela inicial.
  -- Estado em vez de DELETE porque apagar a linha derrubaria os `players` por
  -- cascade, e sem eles o Realtime não consegue avaliar a policy
  -- "sou jogador desta sala" para entregar o aviso aos outros celulares —
  -- que ficariam presos olhando uma sala inexistente.
  'CLOSED'
);

create type game_outcome as enum (
  'TRUTHERS_WIN',   -- verdadeiros descobriram o impostor
  'IMPOSTOR_WIN',   -- um inocente foi eliminado
  'IMPOSTOR_STEAL'  -- impostor foi descoberto mas acertou a palavra na Última Chance
);

-- ---------------------------------------------------------------------------
-- words — banco de palavras
-- ---------------------------------------------------------------------------

create table words (
  id       int generated always as identity primary key,
  text     text          not null unique,
  category word_category not null,

  -- UMA palavra, nunca uma frase. O jogo é dar dicas sobre a palavra secreta;
  -- "Entrevista de Emprego" já entrega metade do jogo no próprio enunciado e
  -- ainda estoura o layout do card. O check existe porque a lista vai crescer, e
  -- a regra tem que valer para quem adicionar palavra no futuro.
  constraint words_single_word_chk check (text ~ '^\S+$'),

  -- Público-alvo inclui criança de 9 anos: palavra curta e concreta. O limite não
  -- garante que seja fácil, mas barra o tipo de termo comprido e abstrato que
  -- ninguém dessa idade sabe explicar.
  constraint words_len_chk check (char_length(text) between 3 and 15)
);

comment on table words is
  'Banco de palavras do jogo. Leitura liberada: conhecer as 200 palavras não '
  'revela qual foi sorteada. Usada também para montar os distratores da Última Chance.';

create index words_category_idx on words (category);

-- ---------------------------------------------------------------------------
-- rooms — estado PÚBLICO da mesa
-- ---------------------------------------------------------------------------

create table rooms (
  id                   uuid        primary key default gen_random_uuid(),
  -- `text`, NUNCA `char(4)`. O decodificador WAL→JSON do Realtime trata `bpchar`
  -- como char de 1 caractere e entrega `"code": "F"` no lugar de `"F2VQ"` — todo
  -- celular passaria a mostrar 1 letra depois do primeiro UPDATE na sala. O
  -- comprimento é garantido pelo check de alfabeto abaixo.
  code                 text        not null unique,
  status               room_status not null default 'LOBBY',

  -- FKs adicionadas depois: players e rounds referenciam rooms
  host_player_id       uuid,
  active_round_id      uuid,

  discussion_round     int         not null default 1,
  voting_cycle         int         not null default 0,
  votes_cast           int         not null default 0,

  guess_deadline       timestamptz,

  -- Resultado. Só preenchido em GAME_OVER — é o que permite revelar o segredo
  -- sem vazá-lo antes da hora.
  outcome              game_outcome,
  eliminated_player_id uuid,
  revealed_word        text,
  revealed_impostor_id uuid,
  last_vote_tally      jsonb,

  games_played         int         not null default 0,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),

  constraint rooms_code_alphabet_chk check (code ~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{4}$'),
  constraint rooms_discussion_round_chk check (discussion_round >= 1),
  constraint rooms_votes_cast_chk check (votes_cast >= 0),

  -- O segredo só é revelado junto com o fim da partida. Se alguém tentar
  -- preencher revealed_* antes, o banco recusa. CLOSED entra na lista porque uma
  -- sala encerrada depois de uma partida conserva o resultado dela.
  constraint rooms_reveal_only_when_over_chk check (
    status in ('GAME_OVER', 'CLOSED')
    or (revealed_word is null and revealed_impostor_id is null and outcome is null)
  )
);

comment on table rooms is
  'Estado público da mesa, legível por todos os jogadores da sala via Realtime. '
  'NUNCA adicionar coluna de segredo ativo aqui (palavra da rodada, impostor) — '
  'RLS não filtra colunas.';

comment on column rooms.votes_cast is
  'Progresso da votação do ciclo atual. Existe para mostrar "3 de 4 votaram" sem '
  'expor a tabela votes, que revelaria em quem cada um votou.';

create index rooms_status_idx on rooms (status);

-- ---------------------------------------------------------------------------
-- players
-- ---------------------------------------------------------------------------

create table players (
  id            uuid        primary key default gen_random_uuid(),
  room_id       uuid        not null references rooms (id) on delete cascade,
  user_id       uuid        not null references auth.users (id) on delete cascade,
  name          text        not null,
  avatar_color  text        not null,
  is_alive      boolean     not null default true,
  score         int         not null default 0,
  has_seen_card boolean     not null default false,
  has_voted     boolean     not null default false,
  joined_at     timestamptz not null default now(),

  constraint players_name_len_chk check (char_length(btrim(name)) between 1 and 20),
  -- O mesmo usuário não duplica na mesma sala: reentrar devolve o mesmo player.
  constraint players_room_user_uniq unique (room_id, user_id)
);

comment on column players.id is
  'Identidade DENTRO da sala. Um mesmo user_id pode ter players em salas diferentes.';

comment on column players.has_voted is
  'Já votei no ciclo atual? Existe porque `votes` é ilegível para o cliente e '
  '`rooms.votes_cast` é só o total — sem esta coluna, recarregar a página durante '
  'a votação mostraria a tela de votar novamente. Revela QUE votou, nunca EM QUEM.';

-- Nome único por sala, case-insensitive.
create unique index players_room_name_uniq on players (room_id, lower(btrim(name)));
create index players_room_idx on players (room_id);
create index players_user_idx on players (user_id);

-- ---------------------------------------------------------------------------
-- rounds — SEGREDO. Nenhum grant para anon/authenticated.
-- ---------------------------------------------------------------------------

create table rounds (
  id                   uuid        primary key default gen_random_uuid(),
  room_id              uuid        not null references rooms (id) on delete cascade,
  round_number         int         not null,
  word_id              int         not null references words (id),
  impostor_player_id   uuid        not null references players (id) on delete cascade,
  last_chance_word_ids int[]       not null default '{}',
  created_at           timestamptz not null default now(),
  resolved_at          timestamptz,

  constraint rounds_room_number_uniq unique (room_id, round_number)
);

comment on table rounds is
  'SEGREDO DA RODADA. Esta tabela não recebe GRANT nenhum para anon/authenticated — '
  'somente funções SECURITY DEFINER a alcançam. Se um dia aparecer uma policy de '
  'SELECT aqui, o jogo inteiro fica trapaceável.';

create index rounds_room_idx on rounds (room_id);

-- Agora que players e rounds existem, fechar as FKs de rooms.
alter table rooms
  add constraint rooms_host_player_fk
    foreign key (host_player_id) references players (id) on delete set null,
  add constraint rooms_active_round_fk
    foreign key (active_round_id) references rounds (id) on delete set null,
  add constraint rooms_eliminated_player_fk
    foreign key (eliminated_player_id) references players (id) on delete set null;

-- ---------------------------------------------------------------------------
-- player_cards — visão individual e secreta
-- ---------------------------------------------------------------------------

create table player_cards (
  round_id            uuid    not null references rounds (id) on delete cascade,
  player_id           uuid    not null references players (id) on delete cascade,
  room_id             uuid    not null references rooms (id) on delete cascade,
  is_impostor         boolean not null,
  word_text           text,
  last_chance_options text[],

  primary key (round_id, player_id),

  -- O impostor nunca tem palavra; o verdadeiro sempre tem.
  constraint player_cards_word_matches_role_chk check (
    (is_impostor and word_text is null) or (not is_impostor and word_text is not null)
  ),
  -- As 4 opções da Última Chance só existem no card do impostor.
  constraint player_cards_options_only_impostor_chk check (
    last_chance_options is null or is_impostor
  )
);

comment on table player_cards is
  'Uma linha por (rodada, jogador) com o que AQUELE jogador pode ver. RLS garante '
  'que cada um leia só a própria linha. word_text é NULL para o impostor.';

create index player_cards_player_idx on player_cards (player_id);

-- ---------------------------------------------------------------------------
-- votes — sem SELECT para o cliente
-- ---------------------------------------------------------------------------

create table votes (
  id               uuid        primary key default gen_random_uuid(),
  room_id          uuid        not null references rooms (id) on delete cascade,
  round_id         uuid        not null references rounds (id) on delete cascade,
  voting_cycle     int         not null,
  voter_player_id  uuid        not null references players (id) on delete cascade,
  target_player_id uuid                 references players (id) on delete cascade,
  created_at       timestamptz not null default now(),

  -- Um voto por jogador por ciclo, garantido pelo banco e não pela UI.
  constraint votes_one_per_cycle_uniq unique (round_id, voting_cycle, voter_player_id),
  -- Ninguém vota em si mesmo.
  constraint votes_no_self_chk check (target_player_id is null or target_player_id <> voter_player_id)
);

comment on table votes is
  'target_player_id NULL = "Pular Votação". Sem grant de SELECT para o cliente: '
  'saber em quem o outro votou antes da apuração estragaria o jogo.';

create index votes_cycle_idx on votes (round_id, voting_cycle);

-- ---------------------------------------------------------------------------
-- updated_at
-- ---------------------------------------------------------------------------

create or replace function touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger rooms_touch_updated_at
  before update on rooms
  for each row
  execute function touch_updated_at();

-- ---------------------------------------------------------------------------
-- Realtime — só as duas tabelas públicas
-- ---------------------------------------------------------------------------

alter publication supabase_realtime add table rooms;
alter publication supabase_realtime add table players;

-- Realtime precisa da linha completa no payload de UPDATE para o cliente
-- comparar fases sem refetch.
alter table rooms replica identity full;
alter table players replica identity full;
