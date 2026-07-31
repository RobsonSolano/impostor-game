-- IMP-01, IMP-02 — criar e entrar em sala
begin;
-- pgTAP em `public` (e não em `extensions`) de propósito: o teste 03 troca para o
-- role `authenticated`, que tem USAGE garantido em public. Rolled back no fim.
create extension if not exists pgtap;

select plan(13);

-- ---------------------------------------------------------------------------
-- Guarda de regressão: o tipo de `rooms.code`
--
-- Com `char(4)` (bpchar) o Realtime entrega `"code": "F"` em vez de `"F2VQ"`:
-- o decodificador WAL→JSON trata bpchar como char de 1 caractere. O bug é
-- invisível na criação (a leitura REST vem certa) e aparece só no primeiro
-- UPDATE da sala, quando todo celular passa a mostrar uma letra só.
-- ---------------------------------------------------------------------------
select col_type_is(
  'public', 'rooms', 'code', 'text',
  'rooms.code é text — bpchar seria truncado para 1 caractere pelo Realtime'
);

-- ---------------------------------------------------------------------------
-- IMP-01 — criar sala
-- ---------------------------------------------------------------------------

create temporary table t_host as select tests.create_anon_user('host') as uid;
select tests.act_as((select uid from t_host));
create temporary table t_room as select create_room('  Robson  ') as res;
select tests.clear_identity();

select matches(
  (select res ->> 'code' from t_room),
  '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{4}$',
  'IMP-01: código tem 4 caracteres do alfabeto sem I/O/0/1'
);

select is(
  (select count(*)::int from players where room_id = (select (res ->> 'room_id')::uuid from t_room)),
  1,
  'IMP-01: sala nasce com o criador como único jogador'
);

select is(
  (select host_player_id from rooms where id = (select (res ->> 'room_id')::uuid from t_room)),
  (select (res ->> 'player_id')::uuid from t_room),
  'IMP-01: criador é registrado como host'
);

select is(
  (select status from rooms where id = (select (res ->> 'room_id')::uuid from t_room)),
  'LOBBY'::room_status,
  'IMP-01: sala nasce em LOBBY'
);

select is(
  (select name from players where id = (select (res ->> 'player_id')::uuid from t_room)),
  'Robson',
  'IMP-01: nome é normalizado (espaços das pontas removidos)'
);

-- ---------------------------------------------------------------------------
-- IMP-02 — entrar em sala
-- ---------------------------------------------------------------------------

create temporary table t_p2 as select tests.create_anon_user('p2') as uid;
select tests.act_as((select uid from t_p2));
-- Código em minúscula e com espaço: normalização acontece no servidor.
create temporary table t_join as
  select join_room(lower('  ' || (select res ->> 'code' from t_room) || ' '), 'Ana') as res;
select tests.clear_identity();

select is(
  (select count(*)::int from players where room_id = (select (res ->> 'room_id')::uuid from t_room)),
  2,
  'IMP-02: entrar com código em minúscula e com espaços funciona'
);

select isnt(
  (select res ->> 'player_id' from t_join),
  (select res ->> 'player_id' from t_room),
  'IMP-02: quem entra recebe player_id próprio'
);

select isnt(
  (select avatar_color from players where id = (select (res ->> 'player_id')::uuid from t_join)),
  (select avatar_color from players where id = (select (res ->> 'player_id')::uuid from t_room)),
  'IMP-02: cores de avatar não se repetem na mesa'
);

-- Reentrada do MESMO usuário devolve o mesmo player (recarregar a página).
select tests.act_as((select uid from t_p2));
select is(
  (select join_room((select res ->> 'code' from t_room), 'OutroNome') ->> 'player_id'),
  (select res ->> 'player_id' from t_join),
  'IMP-02: reentrada do mesmo usuário devolve o mesmo player_id, sem duplicar'
);
select tests.clear_identity();

-- Nome duplicado (case-insensitive) é recusado.
create temporary table t_p3 as select tests.create_anon_user('p3') as uid;
select tests.act_as((select uid from t_p3));
select throws_ok(
  format('select join_room(%L, %L)', (select res ->> 'code' from t_room), 'ana'),
  'IM005',
  null,
  'IMP-02: nome repetido na sala (case-insensitive) é recusado'
);

-- Código inexistente.
select throws_ok(
  format('select join_room(%L, %L)', 'ZZZZ', 'Ninguem'),
  'IM003',
  null,
  'IMP-02: código inexistente é recusado'
);
select tests.clear_identity();

-- Sessão sem autenticação não cria sala.
select throws_ok(
  'select create_room(''Anonimo'')',
  'IM001',
  null,
  'IMP-01: sessão sem auth.uid() não cria sala'
);

select * from finish();
rollback;
