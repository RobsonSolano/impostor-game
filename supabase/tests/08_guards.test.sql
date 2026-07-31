-- IMP-21, IMP-22 — transições ilegais e funções internas fechadas
begin;
create extension if not exists pgtap;

select plan(12);

create temporary table c as select tests.seed_room(4) as ctx;
create temporary table r as select (ctx ->> 'room_id')::uuid as id from c;
create temporary table w as select id from words where text = 'Pizza';

select tests.start_and_reveal(
  (select ctx from c),
  (select id from w),
  ((select ctx -> 'players' from c) ->> 3)::uuid
);
-- Sala agora está em DISCUSSION.

-- ---------------------------------------------------------------------------
-- IMP-21 — cada ação só vale na sua fase
-- ---------------------------------------------------------------------------

select tests.act_as(((select ctx -> 'users' from c) ->> 0)::uuid);

select throws_ok(
  format('select cast_vote(%L, null)', (select id from r)),
  'IM002',
  null,
  'IMP-21: não se vota fora da fase de votação'
);

select throws_ok(
  format('select confirm_word_seen(%L)', (select id from r)),
  'IM002',
  null,
  'IMP-21: não se confirma o card fora de WORD_REVEAL'
);

select throws_ok(
  format('select play_again(%L)', (select id from r)),
  'IM002',
  null,
  'IMP-21: não se começa nova partida fora de GAME_OVER'
);

select throws_ok(
  format('select start_game(%L)', (select id from r)),
  'IM002',
  null,
  'IMP-21: não se inicia partida já em andamento'
);

select throws_ok(
  format('select submit_impostor_guess(%L, %L)', (select id from r), 'Pizza'),
  'IM002',
  null,
  'IMP-21: não se palpita fora da Última Chance'
);

select tests.clear_identity();

select is(
  (select status from rooms where id = (select id from r)),
  'DISCUSSION'::room_status,
  'IMP-21: nenhuma ação recusada alterou o estado da sala'
);

-- Abrir a votação duas vezes.
select tests.act_as(((select ctx -> 'users' from c) ->> 0)::uuid);
select open_voting((select id from r));
select throws_ok(
  format('select open_voting(%L)', (select id from r)),
  'IM002',
  null,
  'IMP-21: abrir a votação duas vezes é recusado'
);
select tests.clear_identity();

-- ---------------------------------------------------------------------------
-- IMP-21 — só o impostor palpita
-- ---------------------------------------------------------------------------

create temporary table clc as select tests.reach_last_chance('Pastel') as ctx;

select tests.act_as(((select ctx -> 'users' from clc) ->> 1)::uuid);
select throws_ok(
  format('select submit_impostor_guess(%L, %L)', (select ctx ->> 'room_id' from clc), 'Pastel'),
  'IM001',
  null,
  'IMP-21: um verdadeiro não pode dar o palpite da Última Chance'
);
select tests.clear_identity();

-- ---------------------------------------------------------------------------
-- Funções internas são inalcançáveis pelo cliente
--
-- Se `begin_round` ficasse exposta, qualquer jogador escolheria o próprio
-- impostor e a própria palavra. CREATE FUNCTION concede EXECUTE a PUBLIC por
-- padrão — estes 4 testes provam que os REVOKE da migration funcionaram.
-- ---------------------------------------------------------------------------

set local role authenticated;

select throws_ok(
  'select begin_round(''00000000-0000-0000-0000-000000000000''::uuid)',
  '42501',
  null,
  'IMP-21: cliente não executa begin_round (escolheria o impostor)'
);

select throws_ok(
  'select resolve_voting(''00000000-0000-0000-0000-000000000000''::uuid)',
  '42501',
  null,
  'IMP-21: cliente não executa resolve_voting (forçaria a apuração)'
);

select throws_ok(
  'select finish_game(''00000000-0000-0000-0000-000000000000''::uuid, ''IMPOSTOR_WIN''::game_outcome)',
  '42501',
  null,
  'IMP-21: cliente não executa finish_game (decretaria o vencedor)'
);

select throws_ok(
  'select current_player(''00000000-0000-0000-0000-000000000000''::uuid)',
  '42501',
  null,
  'IMP-21: cliente não executa current_player'
);

reset role;

select * from finish();
rollback;
