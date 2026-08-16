-- IMP-30, IMP-31, IMP-35, IMP-36, IMP-37 — ordem sorteada, prazo e fim dos turnos
begin;
create extension if not exists pgtap;

select plan(22);

create temporary table c as select tests.seed_room(4) as ctx;
create temporary table r as select (ctx ->> 'room_id')::uuid as id from c;
create temporary table w as select id from words where text = 'Praia';

select tests.start_and_reveal(
  (select ctx from c),
  (select id from w),
  ((select ctx -> 'players' from c) ->> 3)::uuid
);

create temporary table rd as
  select active_round_id as round_id from rooms where id = (select id from r);

-- ---------------------------------------------------------------------------
-- IMP-30 — ordem sorteada
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::int from round_clues
   where round_id = (select round_id from rd) and discussion_round = 1),
  4,
  'IMP-30: a ordem tem uma posição por jogador ativo'
);

select is(
  (select count(distinct turn_index)::int from round_clues
   where round_id = (select round_id from rd) and discussion_round = 1),
  4,
  'IMP-30: as posições são distintas'
);

select is(
  (select array_agg(turn_index order by turn_index)::int[] from round_clues
   where round_id = (select round_id from rd) and discussion_round = 1),
  array[0, 1, 2, 3],
  'IMP-30: as posições vão de 0 a 3, sem buraco'
);

select is(
  (select count(distinct player_id)::int from round_clues
   where round_id = (select round_id from rd) and discussion_round = 1),
  4,
  'IMP-30: cada jogador aparece uma única vez'
);

select is(
  (select count(*)::int from round_clues
   where round_id = (select round_id from rd) and discussion_round = 1 and word is not null),
  0,
  'IMP-30: a ordem já existe, mas nenhuma dica foi dada ainda'
);

-- ---------------------------------------------------------------------------
-- IMP-31 — prazo do turno
-- ---------------------------------------------------------------------------

select is(
  (select clue_turn_index from rooms where id = (select id from r)),
  0,
  'IMP-31: o turno começa na primeira posição'
);

select ok(
  (select turn_deadline from rooms where id = (select id from r)) > now(),
  'IMP-31: um prazo futuro é gravado'
);

select ok(
  (select turn_deadline from rooms where id = (select id from r)) <= now() + interval '30 seconds',
  'IMP-31: o prazo do turno é de 30 segundos'
);

-- ---------------------------------------------------------------------------
-- IMP-35 — só quem está na vez envia; enviar revela e passa o turno
-- ---------------------------------------------------------------------------

-- Alguém que não é o da vez.
select tests.act_as((
  select p.user_id from players p
  where p.room_id = (select id from r)
    and p.id <> tests.turn_player((select id from r))
  limit 1
));
select throws_ok(
  format('select submit_clue(%L, %L)', (select id from r), 'areia'),
  'IM001',
  null,
  'IMP-35: quem não está na vez não envia dica'
);
select tests.clear_identity();

create temporary table t1 as select tests.turn_player((select id from r)) as player_id;

select tests.act_as(tests.turn_user((select id from r)));
select is(
  (select submit_clue((select id from r), 'areia') ->> 'ok'),
  'true',
  'IMP-35: o jogador da vez envia a dica'
);
select tests.clear_identity();

select is(
  (select word from round_clues
   where round_id = (select round_id from rd) and discussion_round = 1
     and player_id = (select player_id from t1)),
  'areia',
  'IMP-35: a dica fica registrada e visível'
);

select is(
  (select clue_turn_index from rooms where id = (select id from r)),
  1,
  'IMP-35: o turno passa para a próxima posição'
);

-- Uniforme: o primeiro tinha 15s por não ter dica anterior para ler, e era quem
-- mais estourava o prazo. Ver IMP-39.
select ok(
  (select turn_deadline from rooms where id = (select id from r)) > now() + interval '25 seconds',
  'IMP-31: todo turno tem os mesmos 30 segundos, sem primeiro turno encurtado'
);

-- ---------------------------------------------------------------------------
-- IMP-36 — prazo estourado passa o turno sem palavra
-- ---------------------------------------------------------------------------

-- Antes do prazo, expirar é no-op.
select tests.act_as(((select ctx -> 'users' from c) ->> 0)::uuid);
select expire_clue_turn((select id from r));
select tests.clear_identity();

select is(
  (select clue_turn_index from rooms where id = (select id from r)),
  1,
  'IMP-36: expirar antes do prazo não passa o turno'
);

create temporary table t2 as select tests.turn_player((select id from r)) as player_id;

-- Força o prazo para o passado.
update rooms set turn_deadline = now() - interval '1 second' where id = (select id from r);

select tests.act_as(((select ctx -> 'users' from c) ->> 0)::uuid);
select expire_clue_turn((select id from r));
select tests.clear_identity();

select is(
  (select clue_turn_index from rooms where id = (select id from r)),
  2,
  'IMP-36: prazo vencido passa o turno'
);

select is(
  (select timed_out from round_clues
   where round_id = (select round_id from rd) and discussion_round = 1
     and player_id = (select player_id from t2)),
  true,
  'IMP-36: a posição fica registrada como sem palavra'
);

select is(
  (select word from round_clues
   where round_id = (select round_id from rd) and discussion_round = 1
     and player_id = (select player_id from t2)),
  null,
  'IMP-36: nenhuma palavra é inventada para quem perdeu o prazo'
);

-- ---------------------------------------------------------------------------
-- IMP-37 — fim dos turnos e decisão do host
-- ---------------------------------------------------------------------------

select tests.finish_clue_turns((select id from r));

select ok(
  clue_turns_done((select id from r)),
  'IMP-37: com todos atendidos, os turnos estão concluídos'
);

select is(
  (select turn_deadline from rooms where id = (select id from r)),
  null,
  'IMP-37: sem turno correndo, não há prazo — a decisão é do host'
);

-- Jogador comum não começa nova rodada.
select tests.act_as(((select ctx -> 'users' from c) ->> 1)::uuid);
select throws_ok(
  format('select next_clue_round(%L)', (select id from r)),
  'IM001',
  null,
  'IMP-37: jogador comum não começa nova rodada de dicas'
);
select tests.clear_identity();

select tests.act_as(((select ctx -> 'users' from c) ->> 0)::uuid);
select next_clue_round((select id from r));
select tests.clear_identity();

select is(
  (select discussion_round from rooms where id = (select id from r)),
  2,
  'IMP-37: "Nova rodada" avança a rodada de discussão'
);

select is(
  (select count(*)::int from round_clues
   where round_id = (select round_id from rd) and discussion_round = 1 and word is not null),
  3,
  'IMP-37: as dicas da rodada anterior continuam visíveis'
);

select * from finish();
rollback;
