-- Jogo do Impostor — máquina de estados
--
-- Toda função pública aqui:
--   1. valida auth.uid()
--   2. toma lock da linha da sala (SELECT ... FOR UPDATE)
--   3. valida se a transição é legal a partir do status atual
--   4. escreve o novo estado
--
-- O UPDATE resultante É o evento de Realtime que sincroniza os celulares.
-- Não existe servidor de jogo além disto.
--
-- Códigos de erro (SQLSTATE) para o cliente distinguir regra de falha real:
--   IM001  proibido        (não é host / não é da sala / não é o impostor)
--   IM002  fase errada     (ação não permitida no status atual, ou prazo vencido)
--   IM003  não encontrado  (sala inexistente)
--   IM004  entrada inválida
--   IM005  conflito        (já votou, nome em uso, sala cheia, jogadores insuficientes)

-- ---------------------------------------------------------------------------
-- Helpers internos
-- ---------------------------------------------------------------------------

create or replace function require_uid()
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Sessão não autenticada' using errcode = 'IM001';
  end if;
  return v_uid;
end;
$$;

create or replace function gen_room_code()
returns text
language sql
volatile
set search_path = public, pg_temp
as $$
  -- Alfabeto sem I, O, 0 e 1: o código é lido em voz alta e digitado à mão.
  select string_agg(
           substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', (floor(random() * 32) + 1)::int, 1),
           ''
         )
  from generate_series(1, 4);
$$;

create or replace function pick_avatar_color(p_room_id uuid)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_palette text[] := array[
    '#ef4444', '#f97316', '#eab308', '#22c55e', '#14b8a6',
    '#3b82f6', '#8b5cf6', '#ec4899', '#f43f5e', '#84cc16',
    '#06b6d4', '#a855f7'
  ];
  v_color text;
begin
  -- Primeira cor livre da paleta, para a mesa ficar visualmente distinta.
  select c into v_color
  from unnest(v_palette) as c
  where not exists (
    select 1 from players where players.room_id = p_room_id and players.avatar_color = c
  )
  limit 1;

  return coalesce(v_color, v_palette[1 + floor(random() * array_length(v_palette, 1))::int]);
end;
$$;

-- Jogador da sala correspondente à sessão atual.
create or replace function current_player(p_room_id uuid)
returns players
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player players;
begin
  select * into v_player
  from players
  where players.room_id = p_room_id
    and players.user_id = auth.uid();

  if v_player.id is null then
    raise exception 'Você não está nesta sala' using errcode = 'IM001';
  end if;

  return v_player;
end;
$$;

create or replace function assert_status(p_room rooms, p_expected room_status)
returns void
language plpgsql
immutable
set search_path = public, pg_temp
as $$
begin
  if p_room.status <> p_expected then
    raise exception 'Ação não permitida na fase % (esperado %)', p_room.status, p_expected
      using errcode = 'IM002';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Sala
-- ---------------------------------------------------------------------------

create or replace function create_room(p_name text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid       uuid := require_uid();
  v_name      text := btrim(coalesce(p_name, ''));
  v_room_id   uuid;
  v_player_id uuid;
  v_code      text;
  v_attempt   int  := 0;
begin
  if char_length(v_name) < 1 or char_length(v_name) > 20 then
    raise exception 'O nome precisa ter entre 1 e 20 caracteres' using errcode = 'IM004';
  end if;

  -- Colisão de código é rara (32^4 ≈ 1,05 milhão) mas possível. Retry silencioso.
  loop
    v_attempt := v_attempt + 1;
    v_code := gen_room_code();
    begin
      insert into rooms (code) values (v_code) returning id into v_room_id;
      exit;
    exception when unique_violation then
      if v_attempt >= 20 then
        raise exception 'Não foi possível gerar um código de sala' using errcode = 'IM005';
      end if;
    end;
  end loop;

  insert into players (room_id, user_id, name, avatar_color)
  values (v_room_id, v_uid, v_name, pick_avatar_color(v_room_id))
  returning id into v_player_id;

  update rooms set host_player_id = v_player_id where id = v_room_id;

  return jsonb_build_object('room_id', v_room_id, 'player_id', v_player_id, 'code', v_code);
end;
$$;

create or replace function join_room(p_code text, p_name text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid         uuid := require_uid();
  v_name        text := btrim(coalesce(p_name, ''));
  v_code        text := upper(btrim(coalesce(p_code, '')));
  v_room        rooms;
  v_player_id   uuid;
  v_player_count int;
begin
  if char_length(v_name) < 1 or char_length(v_name) > 20 then
    raise exception 'O nome precisa ter entre 1 e 20 caracteres' using errcode = 'IM004';
  end if;

  select * into v_room from rooms where rooms.code = v_code for update;
  if v_room.id is null then
    raise exception 'Sala não encontrada' using errcode = 'IM003';
  end if;

  -- Reentrada: mesmo usuário na mesma sala devolve o mesmo player, em qualquer
  -- fase. É o que permite recarregar a página no meio da partida.
  select id into v_player_id
  from players
  where players.room_id = v_room.id and players.user_id = v_uid;

  if v_player_id is not null then
    return jsonb_build_object('room_id', v_room.id, 'player_id', v_player_id, 'code', v_room.code);
  end if;

  if v_room.status <> 'LOBBY' then
    raise exception 'Essa partida já começou' using errcode = 'IM002';
  end if;

  select count(*) into v_player_count from players where players.room_id = v_room.id;
  if v_player_count >= 12 then
    raise exception 'Sala cheia' using errcode = 'IM005';
  end if;

  begin
    insert into players (room_id, user_id, name, avatar_color)
    values (v_room.id, v_uid, v_name, pick_avatar_color(v_room.id))
    returning id into v_player_id;
  exception when unique_violation then
    raise exception 'Esse nome já está em uso na sala' using errcode = 'IM005';
  end;

  return jsonb_build_object('room_id', v_room.id, 'player_id', v_player_id, 'code', v_room.code);
end;
$$;

create or replace function leave_room(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_room   rooms;
  v_player players;
  v_round  rounds;
  v_alive  int;
begin
  perform require_uid();
  select * into v_room from rooms where id = p_room_id for update;
  if v_room.id is null then
    raise exception 'Sala não encontrada' using errcode = 'IM003';
  end if;

  v_player := current_player(p_room_id);

  -- O host não "sai": ele encerra a sala para todos. (IMP-25)
  if v_player.id = v_room.host_player_id then
    perform close_room(p_room_id);
    return;
  end if;

  if v_room.status = 'LOBBY' then
    -- Ainda no lobby: remover de vez, para não ocupar vaga nem aparecer apagado
    -- no roster de uma partida que nem começou.
    delete from players where id = v_player.id;
    return;
  end if;

  update players set is_alive = false where id = v_player.id;

  -- O IMPOSTOR ABANDONANDO ENCERRA A RODADA. (IMP-27)
  -- Sem isto, a mesa continuaria caçando alguém que não está mais lá: qualquer
  -- voto acabaria eliminando um inocente e dando a vitória a um impostor ausente.
  -- Uma partida em andamento sem impostor presente não é jogo.
  select * into v_round from rounds where id = v_room.active_round_id;
  if v_round.id is not null
     and v_round.resolved_at is null
     and v_player.id = v_round.impostor_player_id then
    perform finish_game(p_room_id, 'TRUTHERS_WIN');
    return;
  end if;

  -- Sair no meio da votação não pode travar a apuração: se os que ficaram já
  -- votaram todos, resolve agora.
  if v_room.status = 'VOTING' then
    select count(*) into v_alive from players where room_id = p_room_id and is_alive;
    if v_alive > 0 and v_room.votes_cast >= v_alive then
      perform resolve_voting(p_room_id);
    end if;
  end if;
end;
$$;

/**
 * Encerra a sala para todos (IMP-25).
 *
 * Só o host. Transição terminal: `join_room` exige LOBBY e toda outra RPC exige
 * uma fase específica, então uma sala CLOSED fica inerte — e o código dela deixa
 * de ser utilizável.
 *
 * Por que não `DELETE FROM rooms`: os `players` cairiam por cascade na mesma
 * transação, e sem eles a policy `is_room_member` falha — o Realtime não teria
 * como autorizar a entrega do evento aos outros celulares, que ficariam presos
 * numa sala inexistente. A remoção física fica para a limpeza periódica
 * (ROADMAP milestone 2).
 */
create or replace function close_room(p_room_id uuid)
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

  -- Idempotente: dois toques no botão não são erro.
  if v_room.status = 'CLOSED' then
    return;
  end if;

  v_player := current_player(p_room_id);
  if v_player.id <> v_room.host_player_id then
    raise exception 'Só o host pode encerrar a sala' using errcode = 'IM001';
  end if;

  update rooms set status = 'CLOSED', guess_deadline = null where id = p_room_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Início de rodada (interno)
-- ---------------------------------------------------------------------------

-- p_force_* existem SOMENTE para os testes pgTAP: sem eles não há como testar
-- "o impostor foi eliminado" de forma determinística. Ignorados quando nulos.
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

create or replace function start_game(
  p_room_id           uuid,
  p_force_word_id     int  default null,
  p_force_impostor_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_room   rooms;
  v_player players;
  v_alive  int;
begin
  perform require_uid();
  select * into v_room from rooms where id = p_room_id for update;
  if v_room.id is null then
    raise exception 'Sala não encontrada' using errcode = 'IM003';
  end if;

  perform assert_status(v_room, 'LOBBY');

  v_player := current_player(p_room_id);
  if v_player.id <> v_room.host_player_id then
    raise exception 'Só o host pode iniciar a partida' using errcode = 'IM001';
  end if;

  select count(*) into v_alive from players where room_id = p_room_id and is_alive;
  if v_alive < 3 then
    raise exception 'São necessários no mínimo 3 jogadores (há %)', v_alive
      using errcode = 'IM005';
  end if;

  perform begin_round(p_room_id, p_force_word_id, p_force_impostor_id);
end;
$$;

create or replace function play_again(
  p_room_id           uuid,
  p_force_word_id     int  default null,
  p_force_impostor_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_room   rooms;
  v_player players;
  v_alive  int;
begin
  perform require_uid();
  select * into v_room from rooms where id = p_room_id for update;
  if v_room.id is null then
    raise exception 'Sala não encontrada' using errcode = 'IM003';
  end if;

  perform assert_status(v_room, 'GAME_OVER');

  v_player := current_player(p_room_id);
  if v_player.id <> v_room.host_player_id then
    raise exception 'Só o host pode começar uma nova partida' using errcode = 'IM001';
  end if;

  select count(*) into v_alive from players where room_id = p_room_id and is_alive;
  if v_alive < 3 then
    raise exception 'São necessários no mínimo 3 jogadores (há %)', v_alive
      using errcode = 'IM005';
  end if;

  perform begin_round(p_room_id, p_force_word_id, p_force_impostor_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- Revelação do card
-- ---------------------------------------------------------------------------

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
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Discussão → votação
-- ---------------------------------------------------------------------------

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

  -- Zera as marcas do ciclo anterior: quem votou na rodada indecisa precisa
  -- poder votar de novo nesta.
  update players set has_voted = false where room_id = p_room_id;

  update rooms set
    status       = 'VOTING',
    voting_cycle = voting_cycle + 1,
    votes_cast   = 0
  where id = p_room_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Votação e apuração
-- ---------------------------------------------------------------------------

create or replace function cast_vote(p_room_id uuid, p_target_player_id uuid default null)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_room     rooms;
  v_player   players;
  v_alive    int;
  v_target_ok boolean;
begin
  perform require_uid();
  select * into v_room from rooms where id = p_room_id for update;
  if v_room.id is null then
    raise exception 'Sala não encontrada' using errcode = 'IM003';
  end if;

  perform assert_status(v_room, 'VOTING');

  v_player := current_player(p_room_id);
  if not v_player.is_alive then
    raise exception 'Você não está mais na partida' using errcode = 'IM001';
  end if;

  if p_target_player_id is not null then
    if p_target_player_id = v_player.id then
      raise exception 'Você não pode votar em si mesmo' using errcode = 'IM004';
    end if;

    select exists (
      select 1 from players
      where id = p_target_player_id and room_id = p_room_id and is_alive
    ) into v_target_ok;

    if not v_target_ok then
      raise exception 'Esse jogador não está na partida' using errcode = 'IM004';
    end if;
  end if;

  -- A unicidade é do banco, não da UI: dois toques rápidos não geram dois votos.
  begin
    insert into votes (room_id, round_id, voting_cycle, voter_player_id, target_player_id)
    values (p_room_id, v_room.active_round_id, v_room.voting_cycle, v_player.id, p_target_player_id);
  exception when unique_violation then
    raise exception 'Você já votou nesta rodada' using errcode = 'IM005';
  end;

  update players set has_voted = true where id = v_player.id;
  update rooms set votes_cast = votes_cast + 1 where id = p_room_id;

  select count(*) into v_alive from players where room_id = p_room_id and is_alive;

  -- Último voto do ciclo apura na hora, sem ninguém precisar tocar em nada.
  if v_room.votes_cast + 1 >= v_alive then
    perform resolve_voting(p_room_id);
  end if;
end;
$$;

-- Apuração. Interna: chamada por cast_vote/leave_room com a sala já travada.
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

-- ---------------------------------------------------------------------------
-- Fim de jogo
-- ---------------------------------------------------------------------------

-- Idempotente por rounds.resolved_at: a corrida entre um palpite chegando e o
-- prazo expirando resolve em um único resultado. (IMP-22)
create or replace function finish_game(
  p_room_id     uuid,
  p_outcome     game_outcome,
  p_eliminated  uuid default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_room  rooms;
  v_round rounds;
  v_word  text;
begin
  select * into v_room from rooms where id = p_room_id;
  select * into v_round from rounds where id = v_room.active_round_id;

  if v_round.id is null or v_round.resolved_at is not null then
    return;
  end if;

  update rounds set resolved_at = now() where id = v_round.id;

  select text into v_word from words where id = v_round.word_id;

  if p_outcome = 'TRUTHERS_WIN' then
    update players set score = score + 1
    where room_id = p_room_id and is_alive and id <> v_round.impostor_player_id;
  elsif p_outcome = 'IMPOSTOR_WIN' then
    update players set score = score + 2 where id = v_round.impostor_player_id;
  else -- IMPOSTOR_STEAL
    update players set score = score + 3 where id = v_round.impostor_player_id;
  end if;

  update rooms set
    status               = 'GAME_OVER',
    outcome              = p_outcome,
    eliminated_player_id = coalesce(p_eliminated, eliminated_player_id),
    revealed_word        = v_word,
    revealed_impostor_id = v_round.impostor_player_id,
    guess_deadline       = null,
    votes_cast           = 0,
    games_played         = games_played + 1
  where id = p_room_id;
end;
$$;

create or replace function submit_impostor_guess(p_room_id uuid, p_word_text text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_room    rooms;
  v_round   rounds;
  v_player  players;
  v_word    text;
  v_correct boolean;
begin
  perform require_uid();
  select * into v_room from rooms where id = p_room_id for update;
  if v_room.id is null then
    raise exception 'Sala não encontrada' using errcode = 'IM003';
  end if;

  perform assert_status(v_room, 'LAST_CHANCE');

  select * into v_round from rounds where id = v_room.active_round_id;
  v_player := current_player(p_room_id);

  if v_player.id <> v_round.impostor_player_id then
    raise exception 'Só o impostor pode dar o palpite' using errcode = 'IM001';
  end if;

  if now() > v_room.guess_deadline then
    raise exception 'O prazo do palpite expirou' using errcode = 'IM002';
  end if;

  select text into v_word from words where id = v_round.word_id;
  v_correct := lower(btrim(coalesce(p_word_text, ''))) = lower(v_word);

  perform finish_game(
    p_room_id,
    case when v_correct then 'IMPOSTOR_STEAL'::game_outcome else 'TRUTHERS_WIN'::game_outcome end
  );

  return jsonb_build_object('correct', v_correct, 'word', v_word);
end;
$$;

-- Chamada por qualquer cliente quando o timer local zera. Postgres não dispara
-- nada sozinho — basta um celular vivo na sala. (ver CONCERNS.md #3)
create or replace function expire_last_chance(p_room_id uuid)
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

  -- No-op silencioso: outro cliente já finalizou, ou o prazo ainda não venceu.
  if v_room.status <> 'LAST_CHANCE' or now() <= v_room.guess_deadline then
    return;
  end if;

  perform finish_game(p_room_id, 'TRUTHERS_WIN');
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants
--
-- CREATE FUNCTION concede EXECUTE a PUBLIC por padrão. As funções internas
-- precisam ser explicitamente fechadas, senão o cliente chama begin_round()
-- e escolhe o próprio impostor.
-- ---------------------------------------------------------------------------

revoke execute on function require_uid()                          from public, anon, authenticated;
revoke execute on function gen_room_code()                        from public, anon, authenticated;
revoke execute on function pick_avatar_color(uuid)                from public, anon, authenticated;
revoke execute on function current_player(uuid)                   from public, anon, authenticated;
revoke execute on function assert_status(rooms, room_status)       from public, anon, authenticated;
revoke execute on function begin_round(uuid, int, uuid)            from public, anon, authenticated;
revoke execute on function resolve_voting(uuid)                    from public, anon, authenticated;
revoke execute on function finish_game(uuid, game_outcome, uuid)   from public, anon, authenticated;
revoke execute on function touch_updated_at()                      from public, anon, authenticated;

grant execute on function create_room(text)                        to authenticated;
grant execute on function join_room(text, text)                    to authenticated;
grant execute on function leave_room(uuid)                         to authenticated;
grant execute on function close_room(uuid)                         to authenticated;
grant execute on function start_game(uuid, int, uuid)              to authenticated;
grant execute on function play_again(uuid, int, uuid)              to authenticated;
grant execute on function confirm_word_seen(uuid)                  to authenticated;
grant execute on function open_voting(uuid)                        to authenticated;
grant execute on function cast_vote(uuid, uuid)                    to authenticated;
grant execute on function submit_impostor_guess(uuid, text)         to authenticated;
grant execute on function expire_last_chance(uuid)                 to authenticated;
