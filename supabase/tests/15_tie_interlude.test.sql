-- IMP-39 — pausa de 10s anunciando a votação indecisa antes de recomeçar as dicas
--
-- Origem: sala XMQQ. A mesa votou, deu empate 2 a 2, e a tela voltou direto para
-- os turnos — sem explicar nada e com o relógio do primeiro jogador já correndo
-- enquanto ele lia o resultado.
begin;
create extension if not exists pgtap;

select plan(13);

create temporary table c as select tests.seed_room(4) as ctx;
create temporary table r as select (ctx ->> 'room_id')::uuid as id from c;
create temporary table w as select id from words where text = 'Praia';

select tests.start_and_reveal(
  (select ctx from c),
  (select id from w),
  ((select ctx -> 'players' from c) ->> 3)::uuid
);

-- Empate 2 a 2: 0,1 → p2 e 2,3 → p0.
select tests.run_voting(
  (select ctx from c),
  '[{"voter":0,"target":2},{"voter":1,"target":2},{"voter":2,"target":0},{"voter":3,"target":0}]'::jsonb
);

-- ---------------------------------------------------------------------------
-- A pausa existe e segura a largada
-- ---------------------------------------------------------------------------

select is(
  (select status from rooms where id = (select id from r)),
  'DISCUSSION'::room_status,
  'IMP-13: empate devolve para a discussão'
);

select ok(
  (select clue_round_starts_at from rooms where id = (select id from r)) > now(),
  'IMP-39: a largada da rodada nova fica agendada para o futuro'
);

select ok(
  (select clue_round_starts_at from rooms where id = (select id from r))
    <= now() + interval '10 seconds',
  'IMP-39: a pausa é de no máximo 10 segundos'
);

select is(
  (select turn_deadline from rooms where id = (select id from r)),
  null,
  'IMP-39: nenhum turno corre durante o anúncio — ninguém perde tempo lendo'
);

select is(
  (select count(*)::int from round_clues rc
   join rooms rm on rm.id = (select id from r)
   where rc.round_id = rm.active_round_id and rc.discussion_round = rm.discussion_round),
  0,
  'IMP-39: a ordem da rodada nova ainda não foi sorteada'
);

-- ---------------------------------------------------------------------------
-- Durante a pausa a rodada NÃO conta como concluída
--
-- Sem isto, "não há ninguém pendente" seria lido como "acabou", e o host
-- conseguiria abrir a votação pulando a rodada de dicas inteira.
-- ---------------------------------------------------------------------------

select ok(
  not clue_turns_done((select id from r)),
  'IMP-39: durante a pausa a rodada não está concluída — ela nem começou'
);

select tests.act_as(((select ctx -> 'users' from c) ->> 0)::uuid);

select throws_ok(
  format('select open_voting(%L)', (select id from r)),
  'IM002',
  null,
  'IMP-39: o host não abre a votação durante a pausa'
);

select throws_ok(
  format('select next_clue_round(%L)', (select id from r)),
  'IM002',
  null,
  'IMP-39: o host não pula para outra rodada durante a pausa'
);

-- Antes da hora, largar é no-op.
select start_clue_round_now((select id from r));
select tests.clear_identity();

select is(
  (select turn_deadline from rooms where id = (select id from r)),
  null,
  'IMP-39: largar antes da hora não faz nada'
);

-- ---------------------------------------------------------------------------
-- Vencida a pausa, a rodada larga
-- ---------------------------------------------------------------------------

update rooms set clue_round_starts_at = now() - interval '1 second'
where id = (select id from r);

select tests.act_as(((select ctx -> 'users' from c) ->> 1)::uuid);
select start_clue_round_now((select id from r));
select tests.clear_identity();

select is(
  (select clue_round_starts_at from rooms where id = (select id from r)),
  null,
  'IMP-39: a espera é limpa ao largar'
);

select ok(
  (select turn_deadline from rooms where id = (select id from r)) > now(),
  'IMP-39: o primeiro turno começa com o prazo cheio, só depois do anúncio'
);

select is(
  (select count(*)::int from round_clues rc
   join rooms rm on rm.id = (select id from r)
   where rc.round_id = rm.active_round_id and rc.discussion_round = rm.discussion_round),
  4,
  'IMP-39: a ordem nova é sorteada na largada'
);

-- Qualquer cliente pode chamar, e todos chamam: repetir não pode reiniciar nada.
create temporary table antes as
  select turn_deadline as prazo from rooms where id = (select id from r);

select tests.act_as(((select ctx -> 'users' from c) ->> 2)::uuid);
select start_clue_round_now((select id from r));
select tests.clear_identity();

select is(
  (select turn_deadline from rooms where id = (select id from r)),
  (select prazo from antes),
  'IMP-39: chamar de novo depois de largar não re-sorteia nem reinicia o prazo'
);

select * from finish();
rollback;
