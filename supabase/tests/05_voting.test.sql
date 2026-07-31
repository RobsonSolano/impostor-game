-- IMP-11, IMP-12, IMP-13 — registro de voto, apuração automática, ciclo de repetição
begin;
create extension if not exists pgtap;

select plan(17);

-- Impostor fixo no índice 3, para o host (índice 0) ser sempre um verdadeiro.
create temporary table c as select tests.seed_room(4) as ctx;
create temporary table r as select (ctx ->> 'room_id')::uuid as id from c;
create temporary table w as select id from words where text = 'Hospital';

select tests.start_and_reveal(
  (select ctx from c),
  (select id from w),
  ((select ctx -> 'players' from c) ->> 3)::uuid
);

select tests.act_as(((select ctx -> 'users' from c) ->> 0)::uuid);
select open_voting((select id from r));
select tests.clear_identity();

-- ---------------------------------------------------------------------------
-- IMP-11 — regras do voto
-- ---------------------------------------------------------------------------

select tests.act_as(((select ctx -> 'users' from c) ->> 0)::uuid);

select throws_ok(
  format('select cast_vote(%L, %L)', (select id from r), ((select ctx -> 'players' from c) ->> 0)::uuid),
  'IM004',
  null,
  'IMP-11: ninguém vota em si mesmo'
);

select throws_ok(
  format('select cast_vote(%L, %L)', (select id from r), gen_random_uuid()),
  'IM004',
  null,
  'IMP-11: voto em jogador que não está na sala é recusado'
);

select lives_ok(
  format('select cast_vote(%L, %L)', (select id from r), ((select ctx -> 'players' from c) ->> 1)::uuid),
  'IMP-11: voto válido é aceito'
);

select throws_ok(
  format('select cast_vote(%L, %L)', (select id from r), ((select ctx -> 'players' from c) ->> 2)::uuid),
  'IM005',
  null,
  'IMP-11: segundo voto no mesmo ciclo é recusado'
);

select tests.clear_identity();

select is(
  (select votes_cast from rooms where id = (select id from r)),
  1,
  'IMP-11: contador de votos reflete 1 voto registrado'
);

select is(
  (select count(*)::int from votes where room_id = (select id from r)),
  1,
  'IMP-11: a tentativa de voto duplicado não gravou linha extra'
);

select is(
  (select status from rooms where id = (select id from r)),
  'VOTING'::room_status,
  'IMP-12: com 1 de 4 votos a sala continua em VOTING'
);

-- has_voted é o que permite recarregar a página no meio da votação sem a tela
-- oferecer votar de novo. Revela QUE votou, nunca EM QUEM.
select is(
  (select has_voted from players where id = ((select ctx -> 'players' from c) ->> 0)::uuid),
  true,
  'IMP-11: quem votou fica marcado como votou'
);

select is(
  (select count(*)::int from players where room_id = (select id from r) and has_voted),
  1,
  'IMP-11: a marca de voto não aparece em quem ainda não votou'
);

-- ---------------------------------------------------------------------------
-- IMP-12 / IMP-13 — todos votaram, "pular" vence: volta para a discussão
--
-- Voto 0 já foi em p1. Os outros três pulam: skip = 3 > top = 1.
-- ---------------------------------------------------------------------------

select tests.act_as(((select ctx -> 'users' from c) ->> 1)::uuid);
select cast_vote((select id from r), null);
select tests.act_as(((select ctx -> 'users' from c) ->> 2)::uuid);
select cast_vote((select id from r), null);
select tests.act_as(((select ctx -> 'users' from c) ->> 3)::uuid);
select cast_vote((select id from r), null);
select tests.clear_identity();

select is(
  (select status from rooms where id = (select id from r)),
  'DISCUSSION'::room_status,
  'IMP-13: "Pular Votação" vencendo devolve a sala para DISCUSSION'
);

select is(
  (select discussion_round from rooms where id = (select id from r)),
  2,
  'IMP-13: a rodada de discussão avança para 2'
);

select is(
  (select eliminated_player_id from rooms where id = (select id from r)),
  null,
  'IMP-13: ninguém é eliminado quando "pular" vence'
);

select is(
  (select (last_vote_tally ->> 'skip')::int from rooms where id = (select id from r)),
  3,
  'IMP-13: a apuração registrada mostra os 3 votos de "pular"'
);

select is(
  (select votes_cast from rooms where id = (select id from r)),
  0,
  'IMP-13: contador de votos é zerado para o próximo ciclo'
);

select is(
  (select count(*)::int from players where room_id = (select id from r) and has_voted),
  0,
  'IMP-13: as marcas de voto são zeradas para todos votarem de novo'
);

-- ---------------------------------------------------------------------------
-- IMP-13 — empate entre jogadores também devolve para a discussão
--
-- Segundo ciclo: 0→p2, 1→p2, 2→p0, 3→p0. Empate 2 a 2 no topo.
-- ---------------------------------------------------------------------------

select tests.run_voting(
  (select ctx from c),
  '[{"voter":0,"target":2},{"voter":1,"target":2},{"voter":2,"target":0},{"voter":3,"target":0}]'::jsonb
);

select is(
  (select status from rooms where id = (select id from r)),
  'DISCUSSION'::room_status,
  'IMP-13: empate no topo devolve a sala para DISCUSSION'
);

select is(
  (select discussion_round from rooms where id = (select id from r)),
  3,
  'IMP-13: o ciclo (discussão → votação) pode repetir indefinidamente'
);

select * from finish();
rollback;
