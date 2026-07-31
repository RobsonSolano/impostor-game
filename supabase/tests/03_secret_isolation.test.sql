-- IMP-06 — isolamento do segredo
--
-- ESTE É O TESTE MAIS IMPORTANTE DO PROJETO.
-- Um vazamento da palavra ou do impostor é falha SILENCIOSA: o jogo continua
-- funcionando perfeitamente, só que trapaceável. Nenhum teste de UI pega isso.
-- Se este arquivo for removido ou enfraquecido, o projeto perde a única garantia
-- que sustenta a mecânica. Ver .specs/codebase/CONCERNS.md #1.
--
-- Diferente dos outros arquivos, aqui trocamos de verdade para o role
-- `authenticated` — é justamente o que o role consegue ler que está sob teste.
begin;
create extension if not exists pgtap;

select plan(12);

-- ---------------------------------------------------------------------------
-- Cenário: 4 jogadores, partida em andamento
-- ---------------------------------------------------------------------------

create temporary table c as select tests.seed_room(4) as ctx;

select tests.act_as(((select ctx -> 'users' from c) ->> 0)::uuid);
select start_game((select (ctx ->> 'room_id')::uuid from c));
select tests.clear_identity();

create temporary table ids as
with room as (select (ctx ->> 'room_id')::uuid as room_id from c),
     rd   as (select impostor_player_id, word_id from rounds where room_id = (select room_id from room))
select
  (select room_id from room) as room_id,
  (select user_id from players where id = (select impostor_player_id from rd)) as impostor_uid,
  (select user_id from players
    where room_id = (select room_id from room)
      and id <> (select impostor_player_id from rd)
    limit 1) as truther_uid,
  (select text from words where id = (select word_id from rd)) as secret_word;

create temporary table t_outsider as select tests.create_anon_user('forasteiro') as uid;

-- As tabelas temporárias do cenário pertencem a `postgres`. Como este arquivo
-- realmente troca para o role `authenticated`, ele precisa poder lê-las — senão
-- o teste falha por privilégio de andaime, não por regra de negócio.
grant select on c, ids, t_outsider to authenticated;

-- ---------------------------------------------------------------------------
-- Como um jogador VERDADEIRO
-- ---------------------------------------------------------------------------

select tests.authenticate_as((select truther_uid from ids));

-- As duas tabelas de segredo: sem grant e sem policy = ninguém passa.
select throws_ok(
  'select * from rounds',
  '42501',
  null,
  'IMP-06: jogador não consegue ler a tabela rounds (palavra e impostor)'
);

select throws_ok(
  'select * from votes',
  '42501',
  null,
  'IMP-06: jogador não consegue ler a tabela votes (em quem os outros votaram)'
);

-- Cards: só o meu.
select is(
  (select count(*)::int from player_cards),
  1,
  'IMP-06: jogador vê apenas o próprio card, não os dos outros 3'
);

-- Controle positivo: o mecanismo tem que ENTREGAR o segredo certo, não só bloquear.
select is(
  (select word_text from player_cards),
  (select secret_word from ids),
  'IMP-06: o verdadeiro recebe a palavra correta no próprio card'
);

-- Sala: vejo a minha, e ela não contém segredo.
select is(
  (select count(*)::int from rooms),
  1,
  'IMP-06: jogador vê somente a própria sala'
);

select is(
  (select revealed_word from rooms),
  null,
  'IMP-06: revealed_word está NULL antes de GAME_OVER'
);

select is(
  (select revealed_impostor_id from rooms),
  null,
  'IMP-06: revealed_impostor_id está NULL antes de GAME_OVER'
);

select is(
  (select count(*)::int from players),
  4,
  'IMP-06: jogador vê o roster completo da própria sala'
);

select is(
  (select count(*)::int from words),
  200,
  'IMP-06: banco de palavras é legível (conhecer as 200 não revela a sorteada)'
);

reset role;

-- ---------------------------------------------------------------------------
-- Como o IMPOSTOR
-- ---------------------------------------------------------------------------

select tests.authenticate_as((select impostor_uid from ids));

select is(
  (select word_text from player_cards),
  null,
  'IMP-06: o impostor não tem a palavra em lugar nenhum que ele possa ler'
);

reset role;

-- ---------------------------------------------------------------------------
-- Como alguém que NÃO está na sala
-- ---------------------------------------------------------------------------

select tests.authenticate_as((select uid from t_outsider));

select is(
  (select count(*)::int from rooms),
  0,
  'IMP-06: quem não está na sala não enxerga a sala'
);

select is(
  (select count(*)::int from players),
  0,
  'IMP-06: quem não está na sala não enxerga os jogadores'
);

reset role;

select * from finish();
rollback;
