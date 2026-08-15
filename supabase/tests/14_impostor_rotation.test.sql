-- IMP-38 — sorteio do impostor ponderado por tempo sem ser impostor
--
-- Duas camadas: o PESO é determinístico e verificado exato; o SORTEIO é aleatório
-- e verificado por propriedade, com margem folgada para não virar teste instável.
begin;
create extension if not exists pgtap;

select plan(12);

create temporary table c as select tests.seed_room(4) as ctx;
create temporary table r as select (ctx ->> 'room_id')::uuid as id from c;
create temporary table p0 as select ((ctx -> 'players') ->> 0)::uuid as id from c;
create temporary table p1 as select ((ctx -> 'players') ->> 1)::uuid as id from c;

-- ---------------------------------------------------------------------------
-- Peso: determinístico, conferido no valor exato
-- ---------------------------------------------------------------------------

select is(
  impostor_weight((select id from r), (select id from p0), 1),
  1,
  'IMP-38: sem histórico e na rodada 1, o peso é 1'
);

select is(
  impostor_weight((select id from r), (select id from p0), 5),
  25,
  'IMP-38: quem nunca foi impostor tem o peso máximo da rodada (5² = 25)'
);

-- Joga a rodada 1 com o jogador 0 como impostor.
select tests.act_as(((select ctx -> 'users' from c) ->> 0)::uuid);
select start_game((select id from r), (select id from words where text = 'Praia'), (select id from p0));
select tests.clear_identity();

select is(
  impostor_weight((select id from r), (select id from p0), 2),
  1,
  'IMP-38: quem acabou de ser impostor tem peso 1 — improvável, NUNCA impossível'
);

select cmp_ok(
  impostor_weight((select id from r), (select id from p0), 2),
  '>',
  0,
  'IMP-38: o peso nunca é zero — exclusão é o que esta regra evita'
);

select is(
  impostor_weight((select id from r), (select id from p1), 2),
  4,
  'IMP-38: quem não foi impostor na rodada 1 pesa 4 na rodada 2'
);

select is(
  impostor_weight((select id from r), (select id from p0), 4),
  9,
  'IMP-38: o peso cresce ao quadrado da distância (3 rodadas → 9)'
);

-- ---------------------------------------------------------------------------
-- Sorteio: propriedades, com margem para não ficar instável
-- ---------------------------------------------------------------------------

create temporary table sorteios (n int, impostor uuid);

do $$
declare
  v_room uuid := (select id from r);
  v_rid  uuid;
  i      int;
begin
  for i in 1 .. 200 loop
    v_rid := begin_round(v_room);
    insert into sorteios
    select i, impostor_player_id from rounds where id = v_rid;
  end loop;
end;
$$;

select is((select count(*)::int from sorteios), 200, 'Cenário: 200 sorteios');

select is(
  (select count(distinct impostor)::int from sorteios),
  4,
  'IMP-38: em 200 rodadas, todos os 4 jogadores foram impostor'
);

-- A propriedade que separa esta regra da exclusão: repetir É possível.
-- Com ~3,4% de repetição, a chance de nenhuma em 199 pares é ~1 em 600 mil.
select cmp_ok(
  (select count(*)::int
   from sorteios a join sorteios b on b.n = a.n + 1
   where a.impostor = b.impostor),
  '>',
  0,
  'IMP-38: repetir na rodada seguinte continua possível (senão a mesa deduziria)'
);

-- E é raro: uniforme daria ~50 repetições em 199; ponderado dá ~7.
select cmp_ok(
  (select count(*)::int
   from sorteios a join sorteios b on b.n = a.n + 1
   where a.impostor = b.impostor),
  '<',
  30,
  'IMP-38: mas é bem mais raro que no sorteio uniforme (~50 em 199)'
);

-- Nada de 4 seguidas: com 3,4% por elo, a chance em 200 rodadas é ~1 em 4 mil.
select is(
  (select count(*)::int
   from sorteios a
   join sorteios b on b.n = a.n + 1
   join sorteios c2 on c2.n = a.n + 2
   join sorteios d on d.n = a.n + 3
   where a.impostor = b.impostor
     and b.impostor = c2.impostor
     and c2.impostor = d.impostor),
  0,
  'IMP-38: quatro rodadas seguidas com o mesmo impostor não acontece'
);

-- Distribuição: ninguém monopoliza. Uniforme puro chega a 3,5 de diferença em 12
-- jogos; aqui a folga é generosa para o teste não ficar instável.
select cmp_ok(
  -- `count(*)` é bigint; sem o cast, `cmp_ok` não resolve o tipo e aborta a
  -- transação sem falhar nenhuma asserção — o teste some em vez de quebrar.
  (select (max(c2) - min(c2))::int from (select count(*) as c2 from sorteios group by impostor) t),
  '<',
  40,
  'IMP-38: nenhum jogador monopoliza o papel ao longo de 200 rodadas'
);

select * from finish();
rollback;
