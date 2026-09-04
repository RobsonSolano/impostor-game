-- IMP-40 — salas públicas e listagem
--
-- O teste que importa aqui é de VAZAMENTO, não de funcionalidade.
--
-- `list_public_rooms` é `SECURITY DEFINER`: ela ignora RLS por definição, e a
-- projeção de colunas dela é a única barreira entre um estranho e o segredo da
-- partida. A tentação óbvia ao implementar isso era afrouxar a policy de
-- `rooms` — que vazaria `revealed_word` e `revealed_impostor_id` da sala
-- pública inteira, porque RLS filtra linhas e não colunas (AGENTS.md, regra 2).
--
-- Se alguém trocar a projeção por `select r.*` algum dia, é aqui que quebra.
begin;
create extension if not exists pgtap;

select plan(15);

-- ---------------------------------------------------------------------------
-- Padrão: sala nasce PRIVADA
-- ---------------------------------------------------------------------------

select tests.act_as(tests.create_anon_user('host-privado'));
create temporary table priv as
  select (create_room('Host Privado') ->> 'room_id')::uuid as room_id;

select is(
  (select is_public from rooms where id = (select room_id from priv)),
  false,
  'Sala criada sem informar visibilidade nasce PRIVADA'
);

select is(
  (select title from rooms where id = (select room_id from priv)),
  null,
  'Sala sem título fica com title nulo, não string vazia'
);

-- A chamada de 1 argumento tem que continuar caindo na função NOVA (com
-- defaults), não numa sobrecarga antiga que ignoraria is_public.
select is(
  (select count(*)::int from pg_proc where proname = 'create_room'),
  1,
  'Existe UMA só create_room — sem sobrecarga antiga sobrando'
);

select tests.clear_identity();

-- ---------------------------------------------------------------------------
-- Sala pública aparece na listagem; privada não
-- ---------------------------------------------------------------------------

select tests.act_as(tests.create_anon_user('host-publico'));
create temporary table pub as
  select (create_room('Host Publico', true, 'Mesa do Bar') ->> 'room_id')::uuid as room_id;
select tests.clear_identity();

-- Um terceiro, que não é membro de nenhuma das duas salas.
create temporary table estranho as select tests.create_anon_user('estranho') as uid;
select tests.act_as((select uid from estranho));

select is(
  (select count(*)::int from list_public_rooms() l
   where l.code = (select code from rooms where id = (select room_id from pub))),
  1,
  'Sala pública em LOBBY aparece para quem não é membro'
);

select is(
  (select count(*)::int from list_public_rooms() l
   where l.code = (select code from rooms where id = (select room_id from priv))),
  0,
  'Sala privada NÃO aparece na listagem'
);

select is(
  (select l.host_name from list_public_rooms() l
   where l.code = (select code from rooms where id = (select room_id from pub))),
  'Host Publico',
  'A listagem traz o nome do host'
);

select is(
  (select l.players from list_public_rooms() l
   where l.code = (select code from rooms where id = (select room_id from pub))),
  1,
  'A listagem traz a contagem de jogadores'
);

-- ---------------------------------------------------------------------------
-- A projeção não pode carregar segredo
-- ---------------------------------------------------------------------------

-- As colunas de uma função `returns table` são parâmetros OUT, e não aparecem
-- em `information_schema.columns` — é em `parameters` que elas vivem.
select bag_eq(
  $$select p.parameter_name::text
      from information_schema.parameters p
      join information_schema.routines r on r.specific_name = p.specific_name
     where r.routine_name = 'list_public_rooms' and p.parameter_mode = 'OUT'$$,
  $$values ('code'),('title'),('host_name'),('players'),('created_at')$$,
  'list_public_rooms devolve SOMENTE code, title, host_name, players e created_at'
);

select is(
  (select count(*)::int
     from information_schema.parameters p
     join information_schema.routines r on r.specific_name = p.specific_name
    where r.routine_name = 'list_public_rooms'
      and p.parameter_mode = 'OUT'
      and p.parameter_name in ('revealed_word', 'revealed_impostor_id', 'last_vote_tally',
                               'active_round_id', 'id', 'host_player_id')),
  0,
  'Nenhuma coluna de segredo ou identificador interno na projeção'
);

-- A policy de rooms continua sendo "sou membro": um estranho não lê a linha da
-- sala pública direto na tabela, só pela projeção da função.
select is(
  (select count(*)::int from pg_policies
   where tablename = 'rooms' and policyname = 'rooms_select_member'),
  1,
  'A policy rooms_select_member continua existindo, intocada'
);

select tests.clear_identity();

-- ---------------------------------------------------------------------------
-- Partida em andamento sai da listagem
-- ---------------------------------------------------------------------------

create temporary table pub2 as select tests.seed_room(3) as ctx;
update rooms set is_public = true, title = 'Vai comecar'
  where id = (select (ctx ->> 'room_id')::uuid from pub2);

select tests.act_as((select uid from estranho));
select is(
  (select count(*)::int from list_public_rooms() l
   where l.code = (select code from rooms where id = (select (ctx ->> 'room_id')::uuid from pub2))),
  1,
  'Sala pública em LOBBY está listada antes de começar'
);
select tests.clear_identity();

select tests.act_as(((select ctx -> 'users' from pub2) ->> 0)::uuid);
select start_game((select (ctx ->> 'room_id')::uuid from pub2));
select tests.clear_identity();

select tests.act_as((select uid from estranho));
select is(
  (select count(*)::int from list_public_rooms() l
   where l.code = (select code from rooms where id = (select (ctx ->> 'room_id')::uuid from pub2))),
  0,
  'Partida iniciada sai da listagem — nem o código dela vaza'
);

-- ---------------------------------------------------------------------------
-- Busca
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::int from list_public_rooms('mesa do') l
   where l.code = (select code from rooms where id = (select room_id from pub))),
  1,
  'Busca encontra por parte do título, sem diferenciar maiúscula'
);

select is(
  (select count(*)::int from list_public_rooms('nao existe nada assim') l),
  0,
  'Busca sem resultado devolve lista vazia, não erro'
);

select tests.clear_identity();

-- ---------------------------------------------------------------------------
-- Palavrão no título de sala pública
-- ---------------------------------------------------------------------------

select tests.act_as(tests.create_anon_user('host-boca-suja'));
select throws_ok(
  format(
    $$select create_room('Host Sujo', true, 'sala do %s')$$,
    (select word from profanity_words limit 1)
  ),
  'IM004',
  null,
  'Título de sala PÚBLICA com palavrão é recusado'
);

select finish();
rollback;
