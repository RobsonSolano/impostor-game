-- IMP-03, IMP-04, IMP-05 — mínimo de jogadores, controle do host, sorteio
begin;
create extension if not exists pgtap;

select plan(12);

-- ---------------------------------------------------------------------------
-- IMP-03 — mínimo de 3 jogadores
-- ---------------------------------------------------------------------------

create temporary table c2 as select tests.seed_room(2) as ctx;

select tests.act_as(((select ctx -> 'users' from c2) ->> 0)::uuid);
select throws_ok(
  format('select start_game(%L)', (select ctx ->> 'room_id' from c2)),
  'IM005',
  null,
  'IMP-03: host não inicia partida com 2 jogadores'
);
select tests.clear_identity();

select is(
  (select status from rooms where id = (select (ctx ->> 'room_id')::uuid from c2)),
  'LOBBY'::room_status,
  'IMP-03: sala permanece em LOBBY após tentativa recusada'
);

-- ---------------------------------------------------------------------------
-- IMP-04 — só o host controla
-- ---------------------------------------------------------------------------

create temporary table c4 as select tests.seed_room(4) as ctx;

select tests.act_as(((select ctx -> 'users' from c4) ->> 1)::uuid);
select throws_ok(
  format('select start_game(%L)', (select ctx ->> 'room_id' from c4)),
  'IM001',
  null,
  'IMP-04: jogador que não é host não inicia a partida'
);
select tests.clear_identity();

-- Alguém de fora da sala também não.
create temporary table t_outsider as select tests.create_anon_user('forasteiro') as uid;
select tests.act_as((select uid from t_outsider));
select throws_ok(
  format('select start_game(%L)', (select ctx ->> 'room_id' from c4)),
  'IM001',
  null,
  'IMP-04: quem não está na sala não inicia a partida'
);
select tests.clear_identity();

-- ---------------------------------------------------------------------------
-- IMP-05 — sorteio de palavra e impostor
-- ---------------------------------------------------------------------------

select tests.act_as(((select ctx -> 'users' from c4) ->> 0)::uuid);
select lives_ok(
  format('select start_game(%L)', (select ctx ->> 'room_id' from c4)),
  'IMP-05: host inicia a partida com 4 jogadores'
);
select tests.clear_identity();

select is(
  (select status from rooms where id = (select (ctx ->> 'room_id')::uuid from c4)),
  'WORD_REVEAL'::room_status,
  'IMP-05: sala vai para WORD_REVEAL'
);

select is(
  (select count(*)::int from player_cards
   where room_id = (select (ctx ->> 'room_id')::uuid from c4)),
  4,
  'IMP-05: existe um card por jogador'
);

select is(
  (select count(*)::int from player_cards
   where room_id = (select (ctx ->> 'room_id')::uuid from c4) and is_impostor),
  1,
  'IMP-05: existe exatamente 1 impostor'
);

select is(
  (select count(distinct word_text)::int from player_cards
   where room_id = (select (ctx ->> 'room_id')::uuid from c4) and not is_impostor),
  1,
  'IMP-05: todos os verdadeiros recebem a MESMA palavra'
);

select is(
  (select count(*)::int from player_cards
   where room_id = (select (ctx ->> 'room_id')::uuid from c4)
     and is_impostor and word_text is not null),
  0,
  'IMP-05: o impostor não recebe palavra nenhuma'
);

-- As 4 opções da Última Chance nascem preparadas mas NÃO chegam ao card ainda —
-- vê-las antes da hora entregaria a resposta.
select is(
  (select array_length(last_chance_word_ids, 1) from rounds
   where room_id = (select (ctx ->> 'room_id')::uuid from c4)),
  4,
  'IMP-15: a rodada guarda 4 opções para a Última Chance'
);

select is(
  (select count(*)::int from player_cards
   where room_id = (select (ctx ->> 'room_id')::uuid from c4)
     and last_chance_options is not null),
  0,
  'IMP-15: as opções ainda não estão visíveis em nenhum card em WORD_REVEAL'
);

select * from finish();
rollback;
