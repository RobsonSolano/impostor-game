-- IMP-25, IMP-26 — host encerra a sala; jogador comum apenas sai
begin;
create extension if not exists pgtap;

select plan(14);

-- ---------------------------------------------------------------------------
-- IMP-26 — jogador comum saindo do LOBBY é removido de vez
-- ---------------------------------------------------------------------------

create temporary table ca as select tests.seed_room(4) as ctx;
create temporary table ra as select (ctx ->> 'room_id')::uuid as id from ca;

select tests.act_as(((select ctx -> 'users' from ca) ->> 2)::uuid);
select leave_room((select id from ra));
select tests.clear_identity();

select is(
  (select count(*)::int from players where room_id = (select id from ra)),
  3,
  'IMP-26: sair no lobby remove o jogador, não deixa ele apagado ocupando vaga'
);

select is(
  (select status from rooms where id = (select id from ra)),
  'LOBBY'::room_status,
  'IMP-26: a saída de um jogador comum não encerra a sala'
);

-- ---------------------------------------------------------------------------
-- IMP-26 — jogador comum saindo no meio da partida vira "não vivo"
-- ---------------------------------------------------------------------------

create temporary table cb as select tests.seed_room(4) as ctx;
create temporary table rb as select (ctx ->> 'room_id')::uuid as id from cb;
create temporary table w as select id from words where text = 'Praia';

select tests.start_and_reveal(
  (select ctx from cb),
  (select id from w),
  ((select ctx -> 'players' from cb) ->> 3)::uuid
);

select tests.act_as(((select ctx -> 'users' from cb) ->> 2)::uuid);
select leave_room((select id from rb));
select tests.clear_identity();

select is(
  (select count(*)::int from players where room_id = (select id from rb)),
  4,
  'IMP-26: em partida em andamento o jogador é preservado (histórico de votos)'
);

select is(
  (select is_alive from players where id = ((select ctx -> 'players' from cb) ->> 2)::uuid),
  false,
  'IMP-26: quem sai no meio da partida fica marcado como fora'
);

-- A apuração passa a esperar 3 votos, não 4.
select tests.run_voting(
  (select ctx from cb),
  '[{"voter":0,"target":3},{"voter":1,"target":3},{"voter":3,"target":0}]'::jsonb
);

select is(
  (select status from rooms where id = (select id from rb)),
  'LAST_CHANCE'::room_status,
  'IMP-26: a apuração conta apenas os jogadores que ficaram'
);

-- ---------------------------------------------------------------------------
-- IMP-25 — host encerra a sala para todos
-- ---------------------------------------------------------------------------

create temporary table cc as select tests.seed_room(3) as ctx;
create temporary table rc as select (ctx ->> 'room_id')::uuid as id from cc;

-- Jogador comum não encerra.
select tests.act_as(((select ctx -> 'users' from cc) ->> 1)::uuid);
select throws_ok(
  format('select close_room(%L)', (select id from rc)),
  'IM001',
  null,
  'IMP-25: jogador comum não encerra a sala'
);
select tests.clear_identity();

-- O host saindo encerra, em vez de virar "não vivo".
select tests.act_as(((select ctx -> 'users' from cc) ->> 0)::uuid);
select leave_room((select id from rc));
select tests.clear_identity();

select is(
  (select status from rooms where id = (select id from rc)),
  'CLOSED'::room_status,
  'IMP-25: o host saindo encerra a sala'
);

select is(
  (select count(*)::int from players where room_id = (select id from rc)),
  3,
  'IMP-25: os jogadores continuam existindo — é o que permite o Realtime avisar todos'
);

-- Sala encerrada é inerte: ninguém entra, nada mais roda.
create temporary table t_novo as select tests.create_anon_user('novo') as uid;
select tests.act_as((select uid from t_novo));
select throws_ok(
  format('select join_room(%L, %L)', (select code from rooms where id = (select id from rc)), 'Novo'),
  'IM002',
  null,
  'IMP-25: não se entra em sala encerrada'
);
select tests.clear_identity();

select tests.act_as(((select ctx -> 'users' from cc) ->> 0)::uuid);

select throws_ok(
  format('select start_game(%L)', (select id from rc)),
  'IM002',
  null,
  'IMP-25: não se inicia partida em sala encerrada'
);

select throws_ok(
  format('select open_voting(%L)', (select id from rc)),
  'IM002',
  null,
  'IMP-25: não se abre votação em sala encerrada'
);

select throws_ok(
  format('select play_again(%L)', (select id from rc)),
  'IM002',
  null,
  'IMP-25: não se começa nova partida em sala encerrada'
);

-- Dois toques no botão não são erro.
select lives_ok(
  format('select close_room(%L)', (select id from rc)),
  'IMP-25: encerrar duas vezes é idempotente'
);

select tests.clear_identity();

-- ---------------------------------------------------------------------------
-- IMP-25 — encerrar depois de uma partida conserva o resultado
-- ---------------------------------------------------------------------------

create temporary table cd as select tests.reach_last_chance('Cinema') as ctx;
create temporary table rd as select (ctx ->> 'room_id')::uuid as id from cd;

select tests.act_as(((select ctx -> 'users' from cd) ->> 3)::uuid);
select submit_impostor_guess((select id from rd), 'Cinema');
select tests.act_as(((select ctx -> 'users' from cd) ->> 0)::uuid);
select close_room((select id from rd));
select tests.clear_identity();

select is(
  (select revealed_word from rooms where id = (select id from rd)),
  'Cinema',
  'IMP-25: encerrar após GAME_OVER não apaga o resultado já revelado'
);

select * from finish();
rollback;
