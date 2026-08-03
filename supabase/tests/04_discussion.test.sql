-- IMP-08, IMP-09, IMP-10 — todos prontos, discussão, host abre a votação
begin;
create extension if not exists pgtap;

select plan(12);

create temporary table c as select tests.seed_room(4) as ctx;
create temporary table r as select (ctx ->> 'room_id')::uuid as id from c;

select tests.act_as(((select ctx -> 'users' from c) ->> 0)::uuid);
select start_game((select id from r));
select tests.clear_identity();

select is(
  (select status from rooms where id = (select id from r)),
  'WORD_REVEAL'::room_status,
  'IMP-08: partida começa em WORD_REVEAL'
);

-- ---------------------------------------------------------------------------
-- IMP-08 — a fase só fecha quando o ÚLTIMO jogador confirma
-- ---------------------------------------------------------------------------

select tests.act_as(((select ctx -> 'users' from c) ->> 0)::uuid);
select confirm_word_seen((select id from r));
select tests.act_as(((select ctx -> 'users' from c) ->> 1)::uuid);
select confirm_word_seen((select id from r));
select tests.act_as(((select ctx -> 'users' from c) ->> 2)::uuid);
select confirm_word_seen((select id from r));
select tests.clear_identity();

select is(
  (select status from rooms where id = (select id from r)),
  'WORD_REVEAL'::room_status,
  'IMP-08: com 3 de 4 confirmados, a sala continua em WORD_REVEAL'
);

select is(
  (select count(*)::int from players where room_id = (select id from r) and not has_seen_card),
  1,
  'IMP-08: resta exatamente 1 jogador sem confirmar'
);

select tests.act_as(((select ctx -> 'users' from c) ->> 3)::uuid);
select confirm_word_seen((select id from r));
select tests.clear_identity();

select is(
  (select status from rooms where id = (select id from r)),
  'DISCUSSION'::room_status,
  'IMP-08: o último a confirmar abre a discussão para todos'
);

select is(
  (select discussion_round from rooms where id = (select id from r)),
  1,
  'IMP-08: discussão começa na rodada 1'
);

-- ---------------------------------------------------------------------------
-- IMP-37 — a votação não abre antes de todos darem a dica
-- ---------------------------------------------------------------------------

select tests.act_as(((select ctx -> 'users' from c) ->> 0)::uuid);
select throws_ok(
  format('select open_voting(%L)', (select id from r)),
  'IM002',
  null,
  'IMP-37: host não abre a votação com turnos de dica pendentes'
);
select tests.clear_identity();

select is(
  (select status from rooms where id = (select id from r)),
  'DISCUSSION'::room_status,
  'IMP-37: a recusa não altera a fase'
);

-- Todos cumprem o turno.
select tests.finish_clue_turns((select id from r));

-- ---------------------------------------------------------------------------
-- IMP-09 / IMP-10 — só o host abre a votação
-- ---------------------------------------------------------------------------

select tests.act_as(((select ctx -> 'users' from c) ->> 2)::uuid);
select throws_ok(
  format('select open_voting(%L)', (select id from r)),
  'IM001',
  null,
  'IMP-09: jogador comum não abre a votação'
);
select tests.clear_identity();

select tests.act_as(((select ctx -> 'users' from c) ->> 0)::uuid);
select lives_ok(
  format('select open_voting(%L)', (select id from r)),
  'IMP-10: host abre a votação'
);
select tests.clear_identity();

select is(
  (select status from rooms where id = (select id from r)),
  'VOTING'::room_status,
  'IMP-10: sala vai para VOTING'
);

select is(
  (select voting_cycle from rooms where id = (select id from r)),
  1,
  'IMP-10: primeiro ciclo de votação é o 1'
);

select is(
  (select votes_cast from rooms where id = (select id from r)),
  0,
  'IMP-10: contador de votos começa zerado'
);

select * from finish();
rollback;
