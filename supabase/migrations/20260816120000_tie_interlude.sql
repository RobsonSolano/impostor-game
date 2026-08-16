-- Pausa de 10s após votação indecisa, e 30s para escrever a dica (IMP-39, IMP-31)
--
-- ORIGEM: partida real (sala XMQQ). A mesa votou, deu empate 2 a 2, e a tela
-- voltou direto para os turnos de dicas. Dois problemas de uma vez:
--
-- 1. Ninguém entendia o que tinha acontecido — parecia que o app tinha quebrado.
-- 2. O relógio do primeiro jogador começava a correr NO INSTANTE do empate,
--    enquanto ele ainda estava lendo o resultado. Ele perdia tempo do próprio
--    turno lendo por que voltou.
--
-- Agora a votação indecisa segura a largada por 10 segundos: tempo de ler o
-- placar e de a mesa reagir, com todo mundo começando a rodada nova junto.
--
-- E o tempo de escrita sobe para 30s, uniforme. Metade dos turnos daquela partida
-- estourou o prazo, e turno vazio deixa a votação sem informação — o que ajuda a
-- produzir justamente o empate que originou tudo isto. O primeiro jogador tinha
-- 15s por não ter dica anterior para ler; a assimetria caiu junto, porque ele era
-- quem mais estourava e "você tem 30 segundos" é uma regra que se explica na mesa.

alter table rooms
  add column clue_round_starts_at timestamptz;

comment on column rooms.clue_round_starts_at is
  'Quando a próxima rodada de dicas larga, depois do anúncio de votação indecisa. '
  'NULL fora desse intervalo. Distingue "esperando o anúncio" de "turnos '
  'concluídos, host decide" — nos dois casos `turn_deadline` é NULL.';

/**
 * Tempo de cada turno de dica.
 *
 * Uniforme de propósito: o primeiro jogador tinha 15s por não ter dica anterior
 * para ler, e era justamente quem mais estourava o prazo. Uma regra só é mais
 * fácil de anunciar na mesa.
 */
create or replace function clue_turn_seconds(p_turn_index int)
returns int
language sql
immutable
as $$
  select 30;
$$;

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
    clue_turn_index      = coalesce(v_first, 0),
    turn_deadline        = now() + make_interval(secs => clue_turn_seconds(coalesce(v_first, 0))),
    -- A largada aconteceu: a espera do anúncio não vale mais.
    clue_round_starts_at = null
  where id = p_room_id;
end;
$$;

/**
 * Todos os jogadores ativos já passaram pelo turno? (IMP-37)
 *
 * Durante a espera do anúncio a resposta é FALSE, não TRUE: ali ainda não existem
 * linhas de ordem, e a versão anterior concluía "não há ninguém pendente, logo
 * acabou" — o que deixaria o host abrir a votação pulando a rodada de dicas
 * inteira. A rodada não terminou; ela nem começou.
 */
create or replace function clue_turns_done(p_room_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case
    when (select clue_round_starts_at from rooms where id = p_room_id) is not null
      then false
    else not exists (
      select 1
      from round_clues rc
      join players p on p.id = rc.player_id
      join rooms r on r.id = p_room_id
      where rc.round_id = r.active_round_id
        and rc.discussion_round = r.discussion_round
        and rc.turn_index >= r.clue_turn_index
        and p.is_alive
    )
  end;
$$;

/**
 * Larga a rodada de dicas depois do anúncio de votação indecisa. (IMP-39)
 *
 * Chamada por qualquer cliente cujo contador de 10s zerou — o Postgres não
 * dispara nada sozinho. Idempotente: antes da hora é no-op, e depois de largar a
 * espera já foi limpa, então a chamada repetida não faz nada.
 */
create or replace function start_clue_round_now(p_room_id uuid)
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

  if v_room.status <> 'DISCUSSION' or v_room.clue_round_starts_at is null then
    return;
  end if;

  if now() < v_room.clue_round_starts_at then
    return;
  end if;

  perform begin_clue_round(p_room_id);
end;
$$;

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

    -- NÃO recomeça os turnos agora. A mesa precisa de um instante para LER que
    -- deu empate — e começar o relógio junto com o anúncio roubava tempo do
    -- primeiro jogador, que lia o resultado com o próprio turno já correndo.
    -- `clue_round_starts_at` segura a largada; qualquer cliente cujo contador
    -- zerar chama `start_clue_round_now`. (IMP-39)
    update rooms set clue_round_starts_at = now() + interval '10 seconds'
    where id = p_room_id;
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

/** Partida nova não herda espera de anúncio da anterior. */
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
    -- Sorteio ponderado (IMP-38). `random() ^ (1/peso)` e pegar o maior é
    -- amostragem proporcional ao peso (Efraimidis-Spirakis): peso maior empurra a
    -- chave para perto de 1. Todo jogador ativo continua no sorteio — quem acabou
    -- de ser impostor tem peso 1, não zero.
    select p.id into v_impostor_id
    from players p
    where p.room_id = p_room_id and p.is_alive
    order by power(random(), 1.0 / impostor_weight(p_room_id, p.id, v_number)) desc
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

  -- As 4 opções da Última Chance nascem com a rodada, mas NÃO vão para o card
  -- ainda: vê-las antes da hora entregaria a resposta.
  select array_agg(id) into v_options
  from (
    select w.id
    from words w
    where w.category = v_category and w.id <> v_word_id
    order by random()
    limit 3
  ) t;

  v_options := v_options || v_word_id;

  insert into rounds (room_id, round_number, word_id, impostor_player_id, last_chance_word_ids)
  values (p_room_id, v_number, v_word_id, v_impostor_id, v_options)
  returning id into v_round_id;

  insert into player_cards (round_id, room_id, player_id, is_impostor, word_text)
  select
    v_round_id,
    p_room_id,
    p.id,
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
    clue_round_starts_at = null,
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

revoke all on function start_clue_round_now(uuid) from public;
grant execute on function start_clue_round_now(uuid) to authenticated;
