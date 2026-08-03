-- Turnos de dicas escritas (IMP-30 a IMP-37)
--
-- A fase DISCUSSION deixa de ser "o app não pede nada" e passa a ter ritmo: uma
-- ordem sorteada, e cada jogador escreve UMA palavra com prazo.
--
-- O nome do status continua DISCUSSION de propósito: o papel da fase é o mesmo
-- (entre revelar o card e votar), e a conversa continua acontecendo — agora nos
-- intervalos entre turnos. Renomear o enum só geraria churn em código e teste.

-- ---------------------------------------------------------------------------
-- Estado do turno em `rooms` (público, sincronizado por Realtime)
-- ---------------------------------------------------------------------------

alter table rooms
  add column clue_turn_index int not null default 0,
  add column turn_deadline   timestamptz;

comment on column rooms.clue_turn_index is
  'Posição da ordem sorteada que está jogando agora. Avança até passar do último '
  'jogador ativo, e então os turnos estão concluídos e o host decide.';

comment on column rooms.turn_deadline is
  'Prazo do turno atual. NULL = nenhum turno correndo (turnos concluídos ou fase '
  'errada). Quem manda no prazo é esta coluna; o contador na tela só desenha.';

-- ---------------------------------------------------------------------------
-- Faltas por palavra vulgar (IMP-34)
-- ---------------------------------------------------------------------------

alter table players
  add column profanity_strikes int not null default 0;

comment on column players.profanity_strikes is
  'Tentativas de enviar palavra vulgar. Acumula ao longo da SALA, não por rodada. '
  'Na terceira o jogador é expulso.';

-- ---------------------------------------------------------------------------
-- round_clues — a ordem sorteada E as dicas dadas
-- ---------------------------------------------------------------------------
--
-- Uma tabela para as duas coisas porque a ordem é pública (IMP-30) e `rounds` não
-- tem grant para o cliente. As linhas nascem com `word` nulo no início da rodada
-- de dicas: a ordem já é legível, a palavra aparece quando enviada.

create table round_clues (
  round_id         uuid        not null references rounds(id)  on delete cascade,
  discussion_round int         not null,
  player_id        uuid        not null references players(id) on delete cascade,
  turn_index       int         not null,
  word             text,
  timed_out        boolean     not null default false,
  submitted_at     timestamptz,

  primary key (round_id, discussion_round, player_id),
  -- Duas pessoas não ocupam a mesma posição na ordem.
  unique (round_id, discussion_round, turn_index),

  -- Mesma regra de formato de `is_valid_clue`, como rede no banco.
  constraint round_clues_word_chk check (
    word is null
    or (word ~ '^[A-Za-zÀ-ÖØ-öø-ÿ]+(-[A-Za-zÀ-ÖØ-öø-ÿ]+)*$'
        and char_length(word) between 2 and 20)
  )
);

comment on table round_clues is
  'Ordem de fala sorteada e as dicas escritas. Legível por quem está na sala: as '
  'dicas SÃO o jogo, é sobre elas que a mesa desconfia.';

create index round_clues_room_idx on round_clues (round_id, discussion_round, turn_index);

alter table round_clues enable row level security;

create policy round_clues_select_own_room on round_clues
  for select to authenticated
  using (
    exists (
      select 1 from players p
      where p.id = round_clues.player_id and is_room_member(p.room_id)
    )
  );

grant select on round_clues to authenticated;

-- ---------------------------------------------------------------------------
-- Palavrões (IMP-34)
-- ---------------------------------------------------------------------------
--
-- Sem grant para o cliente: a lista não precisa ser pública, e a checagem roda
-- em função SECURITY DEFINER. O cliente faz uma verificação própria só para
-- feedback imediato; a autoridade é aqui.

create table profanity_words (
  word text primary key
);

comment on table profanity_words is
  'Termos vulgares recusados como dica. Comparação normalizada (minúsculas, sem '
  'acento) para pegar variações de escrita.';

-- Normalização sem depender da extensão `unaccent`: `translate` é determinístico
-- e não adiciona dependência de extensão ao projeto.
create or replace function normalize_word(p_word text)
returns text
language sql
immutable
set search_path = public, pg_temp
as $$
  select translate(
           lower(btrim(coalesce(p_word, ''))),
           'áàâãäéèêëíìîïóòôõöúùûüçñ',
           'aaaaaeeeeiiiiooooouuuucn'
         );
$$;

insert into profanity_words (word) values
  ('merda'), ('bosta'), ('caralho'), ('porra'), ('foder'), ('fodase'),
  ('buceta'), ('boceta'), ('xoxota'), ('pinto'), ('pica'), ('rola'),
  ('cacete'), ('punheta'), ('pornografia'), ('pornô'), ('porno'),
  ('puta'), ('puto'), ('putaria'), ('vagabunda'), ('vadia'), ('piranha'),
  ('viado'), ('bicha'), ('traveco'), ('sapatao'), ('sapatão'),
  ('corno'), ('chifrudo'), ('otario'), ('otário'), ('babaca'),
  ('idiota'), ('imbecil'), ('retardado'), ('mongoloide'), ('debiloide'),
  ('escroto'), ('arrombado'), ('desgraçado'), ('desgracado'),
  ('filhadaputa'), ('fdp'), ('vtnc'), ('pqp'), ('krl'), ('crl'),
  ('bunda'), ('peido'), ('cocô'), ('coco'), ('xixi'), ('penis'), ('pênis'),
  ('vagina'), ('seio'), ('peito'), ('teta'), ('mamilo'),
  ('drogado'), ('maconha'), ('cocaina'), ('cocaína'), ('crack'),
  ('macaco'), ('preto'), ('nazista'), ('hitler'),
  ('matar'), ('morrer'), ('suicidio'), ('suicídio'), ('estupro'), ('estuprar')
on conflict (word) do nothing;

-- `coco` e `peito` entram por precaução de contexto infantil, mesmo sendo
-- palavras comuns: o custo de recusar é o jogador escolher outra em 15s, e o
-- custo de aceitar é a criança levar um deboche. Se incomodar, é uma linha aqui.

create or replace function is_profane(p_word text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from profanity_words
    where normalize_word(profanity_words.word) = normalize_word(p_word)
  );
$$;

-- ---------------------------------------------------------------------------
-- Validação de formato (IMP-32)
-- ---------------------------------------------------------------------------

create or replace function is_valid_clue(p_word text)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$
  -- Um único termo: letras (com acento), hífen só entre letras, 2 a 20 chars.
  -- Não valida se a palavra existe: dicionário embutido recusaria "Pikachu" e
  -- "nerf" no meio de um turno de 15 segundos. Ver IMP-32.
  select btrim(coalesce(p_word, '')) ~ '^[A-Za-zÀ-ÖØ-öø-ÿ]+(-[A-Za-zÀ-ÖØ-öø-ÿ]+)*$'
     and char_length(btrim(coalesce(p_word, ''))) between 2 and 20;
$$;

-- ---------------------------------------------------------------------------
-- Turnos
-- ---------------------------------------------------------------------------

/** Primeiro turno tem 15s (sem dica anterior para ler); os seguintes, 20s. */
create or replace function clue_turn_seconds(p_turn_index int)
returns int
language sql
immutable
as $$
  select case when p_turn_index = 0 then 15 else 20 end;
$$;

/**
 * Sorteia a ordem e abre o primeiro turno. (IMP-30, IMP-31)
 *
 * Interna: chamada por `confirm_word_seen` e por `next_clue_round`.
 */
create or replace function begin_clue_round(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_room  rooms;
  v_first int;
begin
  select * into v_room from rooms where id = p_room_id;

  if v_room.active_round_id is null then
    raise exception 'Sala sem rodada ativa' using errcode = 'IM002';
  end if;

  insert into round_clues (round_id, discussion_round, player_id, turn_index)
  select
    v_room.active_round_id,
    v_room.discussion_round,
    p.id,
    (row_number() over (order by random())) - 1
  from players p
  where p.room_id = p_room_id and p.is_alive
  on conflict do nothing;

  select min(turn_index) into v_first
  from round_clues
  where round_id = v_room.active_round_id
    and discussion_round = v_room.discussion_round;

  update rooms set
    clue_turn_index = coalesce(v_first, 0),
    turn_deadline   = now() + make_interval(secs => clue_turn_seconds(coalesce(v_first, 0)))
  where id = p_room_id;
end;
$$;

/**
 * Passa para o próximo jogador ativo da ordem. (IMP-35, IMP-36)
 *
 * Pula quem não está mais ativo: um expulso no meio da rodada continua na ordem
 * (a linha registra a posição), mas não tem turno.
 *
 * Sem próximo, os turnos estão concluídos: `turn_deadline` vira NULL e a decisão
 * passa ao host (IMP-37).
 */
create or replace function advance_clue_turn(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_room rooms;
  v_next int;
begin
  select * into v_room from rooms where id = p_room_id;

  select min(rc.turn_index) into v_next
  from round_clues rc
  join players p on p.id = rc.player_id
  where rc.round_id = v_room.active_round_id
    and rc.discussion_round = v_room.discussion_round
    and rc.turn_index > v_room.clue_turn_index
    and p.is_alive;

  if v_next is null then
    update rooms set
      clue_turn_index = clue_turn_index + 1,
      turn_deadline   = null
    where id = p_room_id;
  else
    update rooms set
      clue_turn_index = v_next,
      turn_deadline   = now() + make_interval(secs => clue_turn_seconds(v_next))
    where id = p_room_id;
  end if;
end;
$$;

/** Todos os jogadores ativos já passaram pelo turno? (IMP-37) */
create or replace function clue_turns_done(p_room_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select not exists (
    select 1
    from round_clues rc
    join players p on p.id = rc.player_id
    join rooms r on r.id = p_room_id
    where rc.round_id = r.active_round_id
      and rc.discussion_round = r.discussion_round
      and rc.turn_index >= r.clue_turn_index
      and p.is_alive
  );
$$;

/**
 * Expulsa por acumular faltas. (IMP-34)
 *
 * Reaproveita as regras de saída que já existem: host expulso encerra a sala
 * (igual a host saindo), e impostor expulso entrega a vitória aos verdadeiros
 * (igual a IMP-27) — a mesa não pode continuar caçando alguém que não está mais lá.
 */
create or replace function kick_player(p_room_id uuid, p_player_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_room  rooms;
  v_round rounds;
  v_turn  int;
begin
  select * into v_room from rooms where id = p_room_id;

  if p_player_id = v_room.host_player_id then
    perform close_room(p_room_id);
    return;
  end if;

  select turn_index into v_turn
  from round_clues
  where round_id = v_room.active_round_id
    and discussion_round = v_room.discussion_round
    and player_id = p_player_id;

  update players set is_alive = false where id = p_player_id;

  select * into v_round from rounds where id = v_room.active_round_id;
  if v_round.id is not null
     and v_round.resolved_at is null
     and v_round.impostor_player_id = p_player_id then
    perform finish_game(p_room_id, 'TRUTHERS_WIN');
    return;
  end if;

  -- Era a vez dele: o turno não pode ficar preso num jogador que saiu.
  if v_turn is not null and v_turn = v_room.clue_turn_index then
    perform advance_clue_turn(p_room_id);
  end if;
end;
$$;

/**
 * Envia a dica do turno. (IMP-32, IMP-33, IMP-34, IMP-35)
 *
 * Retorna jsonb em vez de só levantar exceção porque a falta por palavra vulgar
 * PRECISA ser persistida: exceção em plpgsql desfaz a transação inteira, e o
 * contador de faltas voltaria a zero junto. Erros que não gravam nada (fase
 * errada, não é sua vez, formato inválido) continuam levantando exceção.
 */
create or replace function submit_clue(p_room_id uuid, p_word text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_room    rooms;
  v_player  players;
  v_turn    int;
  v_word    text := btrim(coalesce(p_word, ''));
  v_strikes int;
begin
  perform require_uid();
  select * into v_room from rooms where id = p_room_id for update;
  if v_room.id is null then
    raise exception 'Sala não encontrada' using errcode = 'IM003';
  end if;

  perform assert_status(v_room, 'DISCUSSION');

  v_player := current_player(p_room_id);

  select turn_index into v_turn
  from round_clues
  where round_id = v_room.active_round_id
    and discussion_round = v_room.discussion_round
    and player_id = v_player.id;

  if v_turn is null or v_turn <> v_room.clue_turn_index then
    raise exception 'Não é a sua vez' using errcode = 'IM001';
  end if;

  if v_room.turn_deadline is null or now() > v_room.turn_deadline then
    raise exception 'O tempo do seu turno acabou' using errcode = 'IM002';
  end if;

  if not is_valid_clue(v_word) then
    raise exception 'Escreva uma única palavra, de 2 a 20 letras (hífen é permitido)'
      using errcode = 'IM004';
  end if;

  -- Palavra vulgar: conta falta, NÃO consome o turno (o prazo segue correndo e
  -- ele pode enviar outra), e na terceira expulsa.
  if is_profane(v_word) then
    update players
    set profanity_strikes = profanity_strikes + 1
    where id = v_player.id
    returning profanity_strikes into v_strikes;

    if v_strikes >= 3 then
      perform kick_player(p_room_id, v_player.id);
      return jsonb_build_object('ok', false, 'reason', 'PROFANITY',
                                'strikes', v_strikes, 'kicked', true);
    end if;

    return jsonb_build_object('ok', false, 'reason', 'PROFANITY',
                              'strikes', v_strikes, 'kicked', false);
  end if;

  -- A palavra secreta NÃO é bloqueada de propósito: recusar confirmaria ao
  -- impostor que ele acertou. Ver IMP-33.
  update round_clues set
    word         = v_word,
    submitted_at = now()
  where round_id = v_room.active_round_id
    and discussion_round = v_room.discussion_round
    and player_id = v_player.id;

  perform advance_clue_turn(p_room_id);

  return jsonb_build_object('ok', true, 'word', v_word);
end;
$$;

/**
 * Fecha o turno cujo prazo venceu. (IMP-36)
 *
 * Chamada por qualquer cliente cujo contador zerou — o Postgres não dispara nada
 * sozinho. Idempotente: antes do prazo é no-op, e depois de já ter avançado o
 * turno atual é outro, então a chamada repetida não faz nada.
 */
create or replace function expire_clue_turn(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_room rooms;
begin
  perform require_uid();
  select * into v_room from rooms where id = p_room_id for update;
  if v_room.id is null then
    raise exception 'Sala não encontrada' using errcode = 'IM003';
  end if;

  perform current_player(p_room_id);

  if v_room.status <> 'DISCUSSION' or v_room.turn_deadline is null then
    return;
  end if;

  if now() <= v_room.turn_deadline then
    return;
  end if;

  update round_clues set timed_out = true
  where round_id = v_room.active_round_id
    and discussion_round = v_room.discussion_round
    and turn_index = v_room.clue_turn_index
    and word is null;

  perform advance_clue_turn(p_room_id);
end;
$$;

/**
 * Nova rodada de dicas, mantendo as anteriores visíveis. (IMP-37)
 */
create or replace function next_clue_round(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_room   rooms;
  v_player players;
begin
  perform require_uid();
  select * into v_room from rooms where id = p_room_id for update;
  if v_room.id is null then
    raise exception 'Sala não encontrada' using errcode = 'IM003';
  end if;

  perform assert_status(v_room, 'DISCUSSION');

  v_player := current_player(p_room_id);
  if v_player.id <> v_room.host_player_id then
    raise exception 'Só o host pode começar uma nova rodada' using errcode = 'IM001';
  end if;

  if not clue_turns_done(p_room_id) then
    raise exception 'Ainda há jogadores para dar a dica' using errcode = 'IM002';
  end if;

  update rooms set discussion_round = discussion_round + 1 where id = p_room_id;
  perform begin_clue_round(p_room_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- Ajustes nas transições existentes
-- ---------------------------------------------------------------------------

/** Entrar em DISCUSSION agora também sorteia a ordem e abre o primeiro turno. */
create or replace function confirm_word_seen(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_room    rooms;
  v_player  players;
  v_pending int;
begin
  perform require_uid();
  select * into v_room from rooms where id = p_room_id for update;
  if v_room.id is null then
    raise exception 'Sala não encontrada' using errcode = 'IM003';
  end if;

  perform assert_status(v_room, 'WORD_REVEAL');

  v_player := current_player(p_room_id);
  update players set has_seen_card = true where id = v_player.id;

  select count(*) into v_pending
  from players
  where room_id = p_room_id and is_alive and not has_seen_card;

  if v_pending = 0 then
    update rooms
    set status = 'DISCUSSION', discussion_round = 1
    where id = p_room_id;

    perform begin_clue_round(p_room_id);
  end if;
end;
$$;

/** A votação só abre depois de todos terem passado pelo turno. (IMP-37) */
create or replace function open_voting(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_room   rooms;
  v_player players;
begin
  perform require_uid();
  select * into v_room from rooms where id = p_room_id for update;
  if v_room.id is null then
    raise exception 'Sala não encontrada' using errcode = 'IM003';
  end if;

  perform assert_status(v_room, 'DISCUSSION');

  v_player := current_player(p_room_id);
  if v_player.id <> v_room.host_player_id then
    raise exception 'Só o host pode abrir a votação' using errcode = 'IM001';
  end if;

  if not clue_turns_done(p_room_id) then
    raise exception 'Ainda há jogadores para dar a dica' using errcode = 'IM002';
  end if;

  update players set has_voted = false where room_id = p_room_id;

  update rooms set
    status        = 'VOTING',
    voting_cycle  = voting_cycle + 1,
    votes_cast    = 0,
    turn_deadline = null
  where id = p_room_id;
end;
$$;

/** Empate ou "pular" volta para DISCUSSION: precisa de turnos novos. */
create or replace function resolve_voting(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_room        rooms;
  v_round       rounds;
  v_skip        int;
  v_top         int;
  v_winners     uuid[];
  v_eliminated  uuid;
  v_tally       jsonb;
begin
  select * into v_room from rooms where id = p_room_id;
  select * into v_round from rounds where id = v_room.active_round_id;

  if v_round.id is null or v_round.resolved_at is not null then
    return;
  end if;

  select count(*) filter (where target_player_id is null)
  into v_skip
  from votes
  where round_id = v_round.id and voting_cycle = v_room.voting_cycle;

  select coalesce(max(c), 0)
  into v_top
  from (
    select count(*) as c
    from votes
    where round_id = v_round.id
      and voting_cycle = v_room.voting_cycle
      and target_player_id is not null
    group by target_player_id
  ) t;

  select coalesce(array_agg(target_player_id), '{}'::uuid[])
  into v_winners
  from (
    select target_player_id, count(*) as c
    from votes
    where round_id = v_round.id
      and voting_cycle = v_room.voting_cycle
      and target_player_id is not null
    group by target_player_id
  ) t
  where t.c = v_top and v_top > 0;

  v_tally := jsonb_build_object(
    'cycle', v_room.voting_cycle,
    'skip',  v_skip,
    'top',   v_top,
    'players', coalesce((
      select jsonb_object_agg(target_player_id::text, c)
      from (
        select target_player_id, count(*) as c
        from votes
        where round_id = v_round.id
          and voting_cycle = v_room.voting_cycle
          and target_player_id is not null
        group by target_player_id
      ) t
    ), '{}'::jsonb)
  );

  -- "Pular" vencendo ou empatando com o topo, ou empate entre jogadores:
  -- ninguém é eliminado e a mesa volta a conversar. (IMP-13)
  if v_skip >= v_top or array_length(v_winners, 1) is null or array_length(v_winners, 1) > 1 then
    update players set has_voted = false where room_id = p_room_id;

    update rooms set
      status           = 'DISCUSSION',
      discussion_round = discussion_round + 1,
      votes_cast       = 0,
      last_vote_tally  = v_tally
    where id = p_room_id;

    -- Voltando para a discussão, a mesa dá dicas de novo: ordem nova sorteada.
    perform begin_clue_round(p_room_id);
    return;
  end if;

  v_eliminated := v_winners[1];

  if v_eliminated = v_round.impostor_player_id then
    -- Impostor descoberto: 5 segundos para roubar a vitória. (IMP-15)
    -- Prazo curto de propósito: a mesa inteira fica parada olhando o contador
    -- até saber o resultado, e espera longa mata o ritmo do jogo ao vivo.
    -- As 4 opções só chegam ao card AGORA — antes disso elas conteriam a resposta.
    update player_cards
    set last_chance_options = (
      select array_agg(w.text order by array_position(v_round.last_chance_word_ids, w.id))
      from words w
      where w.id = any (v_round.last_chance_word_ids)
    )
    where round_id = v_round.id and player_id = v_eliminated;

    update rooms set
      status               = 'LAST_CHANCE',
      eliminated_player_id = v_eliminated,
      guess_deadline       = now() + interval '5 seconds',
      votes_cast           = 0,
      last_vote_tally      = v_tally
    where id = p_room_id;
  else
    -- Inocente eliminado: impostor ganha na hora. (IMP-14)
    update rooms set last_vote_tally = v_tally where id = p_room_id;
    perform finish_game(p_room_id, 'IMPOSTOR_WIN', v_eliminated);
  end if;
end;
$$;

/**
 * `begin_round` é quem zera o estado da partida — `play_again` só valida e
 * delega. O reset de turno entra aqui pelo mesmo motivo.
 */
create or replace function begin_round(
  p_room_id           uuid,
  p_force_word_id     int  default null,
  p_force_impostor_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_word_id     int;
  v_category    word_category;
  v_impostor_id uuid;
  v_round_id    uuid;
  v_number      int;
  v_options     int[];
  v_word_text   text;
begin
  select coalesce(max(round_number), 0) + 1 into v_number
  from rounds where room_id = p_room_id;

  -- ORDEM IMPORTA: o impostor é sorteado ANTES da palavra.
  -- Uma sala sem impostor não tem jogo, então esta é a primeira coisa a existir
  -- e a primeira a falhar se algo estiver errado.
  if p_force_impostor_id is not null then
    v_impostor_id := p_force_impostor_id;
  else
    select id into v_impostor_id
    from players
    where room_id = p_room_id and is_alive
    order by random()
    limit 1;
  end if;

  -- Guarda explícita. `rounds.impostor_player_id` é NOT NULL, então o insert já
  -- falharia — mas com mensagem de constraint, não de regra. Falhar aqui deixa
  -- claro o que aconteceu.
  if v_impostor_id is null then
    raise exception 'Não há jogador elegível para ser o impostor' using errcode = 'IM005';
  end if;

  if not exists (
    select 1 from players
    where id = v_impostor_id and room_id = p_room_id and is_alive
  ) then
    raise exception 'O impostor sorteado não é um jogador ativo desta sala'
      using errcode = 'IM004';
  end if;

  -- Palavra ainda não usada nesta sala. Se o baralho esgotar, libera tudo de novo.
  if p_force_word_id is not null then
    v_word_id := p_force_word_id;
  else
    select id into v_word_id
    from words
    where id not in (select word_id from rounds where room_id = p_room_id)
    order by random()
    limit 1;

    if v_word_id is null then
      select id into v_word_id from words order by random() limit 1;
    end if;
  end if;

  select category, text into v_category, v_word_text from words where id = v_word_id;
  if v_word_text is null then
    raise exception 'Palavra % não existe', v_word_id using errcode = 'IM004';
  end if;

  -- As 4 opções da Última Chance: a correta + 3 da MESMA categoria, embaralhadas.
  with distractors as (
    select id from words
    where category = v_category and id <> v_word_id
    order by random()
    limit 3
  )
  select array_agg(id order by random())
  into v_options
  from (select v_word_id as id union all select id from distractors) u;

  insert into rounds (room_id, round_number, word_id, impostor_player_id, last_chance_word_ids)
  values (p_room_id, v_number, v_word_id, v_impostor_id, v_options)
  returning id into v_round_id;

  -- Card individual. O impostor recebe word_text NULL — a palavra não trafega
  -- para ele em nenhum momento.
  insert into player_cards (round_id, player_id, room_id, is_impostor, word_text)
  select v_round_id,
         p.id,
         p_room_id,
         p.id = v_impostor_id,
         case when p.id = v_impostor_id then null else v_word_text end
  from players p
  where p.room_id = p_room_id and p.is_alive;

  update players set has_seen_card = false, has_voted = false where room_id = p_room_id;

  -- Limpa o resultado da partida anterior no mesmo UPDATE que sai de GAME_OVER,
  -- para não violar rooms_reveal_only_when_over_chk.
  update rooms set
    status               = 'WORD_REVEAL',
    active_round_id      = v_round_id,
    discussion_round     = 1,
    voting_cycle         = 0,
    votes_cast           = 0,
    -- Estado de turno da partida anterior não sobrevive à nova.
    clue_turn_index      = 0,
    turn_deadline        = null,
    guess_deadline       = null,
    outcome              = null,
    eliminated_player_id = null,
    revealed_word        = null,
    revealed_impostor_id = null,
    last_vote_tally      = null
  where id = p_room_id;

  return v_round_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
--
-- CREATE FUNCTION concede EXECUTE a PUBLIC por padrão. As internas ficam
-- fechadas: `begin_clue_round` exposta deixaria qualquer jogador re-sortear a
-- ordem, e `kick_player` deixaria um jogador expulsar outro.

revoke all on function normalize_word(text)          from public;
revoke all on function is_profane(text)              from public;
revoke all on function is_valid_clue(text)           from public;
revoke all on function clue_turn_seconds(int)        from public;
revoke all on function begin_clue_round(uuid)        from public;
revoke all on function advance_clue_turn(uuid)       from public;
revoke all on function clue_turns_done(uuid)         from public;
revoke all on function kick_player(uuid, uuid)       from public;
revoke all on function submit_clue(uuid, text)       from public;
revoke all on function expire_clue_turn(uuid)        from public;
revoke all on function next_clue_round(uuid)         from public;

grant execute on function submit_clue(uuid, text)  to authenticated;
grant execute on function expire_clue_turn(uuid)   to authenticated;
grant execute on function next_clue_round(uuid)    to authenticated;

-- ---------------------------------------------------------------------------
-- Realtime
-- ---------------------------------------------------------------------------
--
-- As dicas precisam aparecer para todos no instante em que são enviadas, então
-- `round_clues` entra na publicação. É seguro: a tabela não guarda segredo — a
-- ordem é pública e a palavra só existe na linha depois de enviada.
--
-- `rounds`, `votes` e `player_cards` continuam FORA da publicação de propósito:
-- um evento de Realtime carrega a linha inteira, e isso vazaria a palavra secreta,
-- o impostor e os votos.

alter publication supabase_realtime add table round_clues;
alter table round_clues replica identity full;
