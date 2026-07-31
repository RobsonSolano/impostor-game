-- IMP-14, IMP-15 — inocente eliminado vs impostor eliminado
begin;
create extension if not exists pgtap;

select plan(14);

create temporary table w as select id from words where text = 'Hospital';

-- ---------------------------------------------------------------------------
-- IMP-14 — inocente eliminado: o impostor ganha na hora
--
-- Impostor = p3. Votos 0,2,3 → p1 (inocente). p1 → p0. Placar: p1=3, p0=1.
-- ---------------------------------------------------------------------------

create temporary table ca as select tests.seed_room(4) as ctx;
create temporary table ra as select (ctx ->> 'room_id')::uuid as id from ca;

select tests.start_and_reveal(
  (select ctx from ca),
  (select id from w),
  ((select ctx -> 'players' from ca) ->> 3)::uuid
);

select tests.run_voting(
  (select ctx from ca),
  '[{"voter":0,"target":1},{"voter":2,"target":1},{"voter":3,"target":1},{"voter":1,"target":0}]'::jsonb
);

select is(
  (select status from rooms where id = (select id from ra)),
  'GAME_OVER'::room_status,
  'IMP-14: eliminar um inocente encerra a partida'
);

select is(
  (select outcome from rooms where id = (select id from ra)),
  'IMPOSTOR_WIN'::game_outcome,
  'IMP-14: resultado é vitória do impostor'
);

select is(
  (select eliminated_player_id from rooms where id = (select id from ra)),
  ((select ctx -> 'players' from ca) ->> 1)::uuid,
  'IMP-14: o eliminado registrado é quem levou a maioria'
);

select is(
  (select revealed_word from rooms where id = (select id from ra)),
  'Hospital',
  'IMP-14: a palavra é revelada só agora, em GAME_OVER'
);

select is(
  (select revealed_impostor_id from rooms where id = (select id from ra)),
  ((select ctx -> 'players' from ca) ->> 3)::uuid,
  'IMP-14: o impostor é revelado em GAME_OVER'
);

select is(
  (select score from players where id = ((select ctx -> 'players' from ca) ->> 3)::uuid),
  2,
  'IMP-18: impostor vencedor por engano da mesa soma 2 pontos'
);

select is(
  (select coalesce(sum(score), 0)::int from players
   where room_id = (select id from ra)
     and id <> ((select ctx -> 'players' from ca) ->> 3)::uuid),
  0,
  'IMP-18: nenhum verdadeiro pontua quando o impostor ganha'
);

select is(
  (select games_played from rooms where id = (select id from ra)),
  1,
  'IMP-14: a partida concluída é contabilizada'
);

-- ---------------------------------------------------------------------------
-- IMP-15 — impostor eliminado: abre a Última Chance
--
-- Impostor = p3. Votos 0,1,2 → p3. p3 → p0. Placar: p3=3, p0=1.
-- ---------------------------------------------------------------------------

create temporary table cb as select tests.seed_room(4) as ctx;
create temporary table rb as select (ctx ->> 'room_id')::uuid as id from cb;

select tests.start_and_reveal(
  (select ctx from cb),
  (select id from w),
  ((select ctx -> 'players' from cb) ->> 3)::uuid
);

select tests.run_voting(
  (select ctx from cb),
  '[{"voter":0,"target":3},{"voter":1,"target":3},{"voter":2,"target":3},{"voter":3,"target":0}]'::jsonb
);

select is(
  (select status from rooms where id = (select id from rb)),
  'LAST_CHANCE'::room_status,
  'IMP-15: descobrir o impostor abre a Última Chance, não encerra a partida'
);

select ok(
  (select guess_deadline from rooms where id = (select id from rb)) > now(),
  'IMP-15: um prazo futuro é gravado para o palpite'
);

select ok(
  (select guess_deadline from rooms where id = (select id from rb)) <= now() + interval '5 seconds',
  'IMP-15: o prazo é de no máximo 5 segundos'
);

-- As 4 opções chegam ao card do impostor SOMENTE agora.
select is(
  (select array_length(last_chance_options, 1) from player_cards
   where room_id = (select id from rb)
     and player_id = ((select ctx -> 'players' from cb) ->> 3)::uuid),
  4,
  'IMP-15: o impostor recebe exatamente 4 opções'
);

select ok(
  'Hospital' = any (
    select unnest(last_chance_options) from player_cards
    where room_id = (select id from rb)
      and player_id = ((select ctx -> 'players' from cb) ->> 3)::uuid
  ),
  'IMP-15: a palavra correta está entre as 4 opções'
);

select is(
  (select count(*)::int from player_cards
   where room_id = (select id from rb) and last_chance_options is not null),
  1,
  'IMP-15: as opções aparecem só no card do impostor, em nenhum outro'
);

select * from finish();
rollback;
