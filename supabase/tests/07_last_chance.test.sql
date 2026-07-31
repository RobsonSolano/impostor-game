-- IMP-16, IMP-17, IMP-18, IMP-19 — Última Chance, pontuação e nova partida
begin;
create extension if not exists pgtap;

select plan(22);

-- ---------------------------------------------------------------------------
-- IMP-16 — impostor acerta e rouba a vitória
-- ---------------------------------------------------------------------------

create temporary table ca as select tests.reach_last_chance('Hospital') as ctx;
create temporary table ra as select (ctx ->> 'room_id')::uuid as id from ca;

select tests.act_as(((select ctx -> 'users' from ca) ->> 3)::uuid);
create temporary table ga as
  select submit_impostor_guess((select id from ra), 'Hospital') as res;
select tests.clear_identity();

select is(
  (select (res ->> 'correct')::boolean from ga),
  true,
  'IMP-16: o palpite correto é reconhecido'
);

select is(
  (select status from rooms where id = (select id from ra)),
  'GAME_OVER'::room_status,
  'IMP-16: acertar encerra a partida'
);

select is(
  (select outcome from rooms where id = (select id from ra)),
  'IMPOSTOR_STEAL'::game_outcome,
  'IMP-16: o impostor rouba a vitória'
);

select is(
  (select score from players where id = ((select ctx -> 'players' from ca) ->> 3)::uuid),
  3,
  'IMP-18: roubo de vitória vale 3 pontos para o impostor'
);

select is(
  (select coalesce(sum(score), 0)::int from players
   where room_id = (select id from ra)
     and id <> ((select ctx -> 'players' from ca) ->> 3)::uuid),
  0,
  'IMP-18: os verdadeiros não pontuam quando o impostor rouba'
);

-- ---------------------------------------------------------------------------
-- IMP-17 — impostor erra: os verdadeiros ganham
-- ---------------------------------------------------------------------------

create temporary table cb as select tests.reach_last_chance('Hospital') as ctx;
create temporary table rb as select (ctx ->> 'room_id')::uuid as id from cb;

select tests.act_as(((select ctx -> 'users' from cb) ->> 3)::uuid);
create temporary table gb as
  select submit_impostor_guess((select id from rb), 'Aeroporto') as res;
select tests.clear_identity();

select is(
  (select (res ->> 'correct')::boolean from gb),
  false,
  'IMP-17: o palpite errado é reconhecido'
);

select is(
  (select outcome from rooms where id = (select id from rb)),
  'TRUTHERS_WIN'::game_outcome,
  'IMP-17: errar entrega a vitória aos verdadeiros'
);

select is(
  (select coalesce(sum(score), 0)::int from players
   where room_id = (select id from rb)
     and id <> ((select ctx -> 'players' from cb) ->> 3)::uuid),
  3,
  'IMP-18: cada um dos 3 verdadeiros soma 1 ponto'
);

select is(
  (select score from players where id = ((select ctx -> 'players' from cb) ->> 3)::uuid),
  0,
  'IMP-18: o impostor descoberto não pontua'
);

-- ---------------------------------------------------------------------------
-- IMP-17 — prazo expirado
-- ---------------------------------------------------------------------------

create temporary table cc as select tests.reach_last_chance('Hospital') as ctx;
create temporary table rc as select (ctx ->> 'room_id')::uuid as id from cc;

-- Antes do prazo, expirar é no-op: o impostor ainda pode palpitar.
select tests.act_as(((select ctx -> 'users' from cc) ->> 0)::uuid);
select expire_last_chance((select id from rc));
select tests.clear_identity();

select is(
  (select status from rooms where id = (select id from rc)),
  'LAST_CHANCE'::room_status,
  'IMP-17: expirar antes do prazo não faz nada'
);

-- Força o prazo para o passado, como se os 5 segundos tivessem corrido.
update rooms set guess_deadline = now() - interval '1 second' where id = (select id from rc);

-- Qualquer jogador da sala pode finalizar — não só o impostor nem só o host.
select tests.act_as(((select ctx -> 'users' from cc) ->> 1)::uuid);
select expire_last_chance((select id from rc));
select tests.clear_identity();

select is(
  (select status from rooms where id = (select id from rc)),
  'GAME_OVER'::room_status,
  'IMP-17: prazo vencido encerra a partida'
);

select is(
  (select outcome from rooms where id = (select id from rc)),
  'TRUTHERS_WIN'::game_outcome,
  'IMP-17: perder o prazo entrega a vitória aos verdadeiros'
);

-- Idempotência: vários celulares chamam expire ao mesmo tempo quando o timer
-- local zera. A pontuação não pode ser aplicada duas vezes. (IMP-22)
select tests.act_as(((select ctx -> 'users' from cc) ->> 2)::uuid);
select expire_last_chance((select id from rc));
select expire_last_chance((select id from rc));
select tests.clear_identity();

select is(
  (select coalesce(sum(score), 0)::int from players
   where room_id = (select id from rc)
     and id <> ((select ctx -> 'players' from cc) ->> 3)::uuid),
  3,
  'IMP-22: chamar expire várias vezes não pontua em dobro'
);

select tests.act_as(((select ctx -> 'users' from cc) ->> 3)::uuid);
select throws_ok(
  format('select submit_impostor_guess(%L, %L)', (select id from rc), 'Hospital'),
  'IM002',
  null,
  'IMP-17: palpite após o encerramento é recusado'
);
select tests.clear_identity();

-- ---------------------------------------------------------------------------
-- IMP-19 — jogar novamente com nova palavra
-- ---------------------------------------------------------------------------

select tests.act_as(((select ctx -> 'users' from cb) ->> 1)::uuid);
select throws_ok(
  format('select play_again(%L)', (select id from rb)),
  'IM001',
  null,
  'IMP-19: jogador comum não começa uma nova partida'
);
select tests.clear_identity();

select tests.act_as(((select ctx -> 'users' from cb) ->> 0)::uuid);
select play_again((select id from rb));
select tests.clear_identity();

select is(
  (select status from rooms where id = (select id from rb)),
  'WORD_REVEAL'::room_status,
  'IMP-19: nova partida volta todos para a revelação do card'
);

select isnt(
  (select word_id from rounds where room_id = (select id from rb) and round_number = 2),
  (select id from words where text = 'Hospital'),
  'IMP-19: a nova rodada sorteia uma palavra que ainda não foi usada na sala'
);

select is(
  (select discussion_round from rooms where id = (select id from rb)),
  1,
  'IMP-19: a contagem de rodadas de discussão reinicia'
);

select is(
  (select voting_cycle from rooms where id = (select id from rb)),
  0,
  'IMP-19: o ciclo de votação reinicia'
);

select is(
  (select coalesce(sum(score), 0)::int from players where room_id = (select id from rb)),
  3,
  'IMP-19: o placar acumulado da sala é preservado entre partidas'
);

select is(
  (select revealed_word from rooms where id = (select id from rb)),
  null,
  'IMP-19: o resultado da partida anterior é limpo ao começar a nova'
);

select is(
  (select count(*)::int from players where room_id = (select id from rb) and has_seen_card),
  0,
  'IMP-19: todos precisam ver o card de novo'
);

select * from finish();
rollback;
