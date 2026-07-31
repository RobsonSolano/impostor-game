-- IMP-05, IMP-19, IMP-27 — nunca uma rodada sem impostor
--
-- O sorteio do impostor é aleatório, e teste de coisa aleatória feito uma vez só
-- não prova nada. Aqui a rodada é sorteada 30 vezes e o invariante é verificado
-- em todas: exatamente 1 impostor, vivo, com card, entre os jogadores da sala.
begin;
create extension if not exists pgtap;

select plan(9);

create temporary table c as select tests.seed_room(4) as ctx;
create temporary table r as select (ctx ->> 'room_id')::uuid as id from c;

create temporary table audit (
  round_id       uuid,
  impostor_id    uuid,
  impostor_count int,
  impostor_alive boolean,
  in_this_room   boolean,
  card_count     int,
  word_count     int
);

do $$
declare
  v_room_id  uuid := (select id from r);
  v_round_id uuid;
  i          int;
begin
  for i in 1 .. 30 loop
    v_round_id := begin_round(v_room_id);

    insert into audit
    select
      v_round_id,
      rd.impostor_player_id,
      (select count(*) from player_cards pc where pc.round_id = v_round_id and pc.is_impostor),
      (select p.is_alive from players p where p.id = rd.impostor_player_id),
      (select p.room_id = v_room_id from players p where p.id = rd.impostor_player_id),
      (select count(*) from player_cards pc where pc.round_id = v_round_id),
      (select count(distinct pc.word_text) from player_cards pc
        where pc.round_id = v_round_id and not pc.is_impostor)
    from rounds rd
    where rd.id = v_round_id;
  end loop;
end;
$$;

select is((select count(*)::int from audit), 30, 'Cenário: 30 rodadas sorteadas');

select is(
  (select count(*)::int from audit where impostor_count <> 1),
  0,
  'IMP-05: nenhuma das 30 rodadas ficou sem impostor ou com mais de um'
);

select ok(
  (select bool_and(impostor_alive) from audit),
  'IMP-05: o impostor sorteado está sempre entre os jogadores ativos'
);

select ok(
  (select bool_and(in_this_room) from audit),
  'IMP-05: o impostor sorteado é sempre da própria sala'
);

select is(
  (select count(*)::int from audit where card_count <> 4),
  0,
  'IMP-05: todos os 4 jogadores recebem card em todas as rodadas'
);

select is(
  (select count(*)::int from audit where word_count <> 1),
  0,
  'IMP-05: os verdadeiros compartilham exatamente uma palavra em todas as rodadas'
);

-- Se o sorteio estivesse travado num jogador, isto acusaria. A chance de 30
-- sorteios caírem no mesmo entre 4 jogadores é (1/4)^29 — efetivamente zero.
select cmp_ok(
  (select count(distinct impostor_id)::int from audit),
  '>',
  1,
  'IMP-19: cada nova partida sorteia o impostor de novo, não repete o mesmo'
);

-- ---------------------------------------------------------------------------
-- IMP-27 — o impostor abandonando encerra a rodada
-- ---------------------------------------------------------------------------

create temporary table cb as select tests.seed_room(4) as ctx;
create temporary table rb as select (ctx ->> 'room_id')::uuid as id from cb;
create temporary table w as select id from words where text = 'Museu';

-- Impostor no índice 2 (nem host, para o abandono não virar encerramento de sala).
select tests.start_and_reveal(
  (select ctx from cb),
  (select id from w),
  ((select ctx -> 'players' from cb) ->> 2)::uuid
);

select tests.act_as(((select ctx -> 'users' from cb) ->> 2)::uuid);
select leave_room((select id from rb));
select tests.clear_identity();

select is(
  (select outcome from rooms where id = (select id from rb)),
  'TRUTHERS_WIN'::game_outcome,
  'IMP-27: impostor abandonando a partida entrega a vitória aos verdadeiros'
);

select is(
  (select coalesce(sum(score), 0)::int from players
   where room_id = (select id from rb)
     and id <> ((select ctx -> 'players' from cb) ->> 2)::uuid),
  3,
  'IMP-27: os 3 verdadeiros que ficaram pontuam'
);

select * from finish();
rollback;
