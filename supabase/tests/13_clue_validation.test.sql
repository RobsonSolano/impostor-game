-- IMP-32, IMP-33, IMP-34 — formato da dica, palavra secreta e palavras vulgares
begin;
create extension if not exists pgtap;

select plan(29);

-- ---------------------------------------------------------------------------
-- IMP-32 — formato: uma palavra só
-- ---------------------------------------------------------------------------

select ok(is_valid_clue('tromba'),       'IMP-32: aceita palavra simples');
select ok(is_valid_clue('guarda-chuva'), 'IMP-32: aceita hífen interno');
select ok(is_valid_clue('bem-te-vi'),    'IMP-32: aceita mais de um hífen interno');
select ok(is_valid_clue('Pão'),          'IMP-32: aceita acento e maiúscula');
select ok(is_valid_clue('ré'),           'IMP-32: aceita duas letras');
select ok(is_valid_clue('  areia  '),    'IMP-32: espaço nas pontas é aparado, não recusado');

select ok(not is_valid_clue('dois termos'), 'IMP-32: recusa duas palavras');
select ok(not is_valid_clue('x1'),          'IMP-32: recusa número');
select ok(not is_valid_clue('-abc'),        'IMP-32: recusa hífen no começo');
select ok(not is_valid_clue('abc-'),        'IMP-32: recusa hífen no fim');
select ok(not is_valid_clue('a'),           'IMP-32: recusa uma letra só');
select ok(not is_valid_clue(''),            'IMP-32: recusa vazio');
select ok(not is_valid_clue(null),          'IMP-32: recusa nulo');
select ok(not is_valid_clue('sol!'),        'IMP-32: recusa símbolo');
select ok(
  not is_valid_clue(repeat('a', 21)),
  'IMP-32: recusa acima de 20 caracteres'
);

-- Não valida existência: decisão consciente (IMP-32).
select ok(is_valid_clue('xpto'), 'IMP-32: não valida se a palavra existe — "xpto" passa');

-- ---------------------------------------------------------------------------
-- Cenário de sala para as regras que gravam estado
-- ---------------------------------------------------------------------------

create temporary table c as select tests.seed_room(4) as ctx;
create temporary table r as select (ctx ->> 'room_id')::uuid as id from c;
create temporary table w as select id from words where text = 'Hospital';

-- Impostor no índice 3, para as faltas do índice 1 não encerrarem a partida.
select tests.start_and_reveal(
  (select ctx from c),
  (select id from w),
  ((select ctx -> 'players' from c) ->> 3)::uuid
);

-- ---------------------------------------------------------------------------
-- IMP-33 — a palavra secreta NÃO é bloqueada
--
-- Bloquear confirmaria ao impostor que ele acertou. O aviso na tela é preventivo.
-- ---------------------------------------------------------------------------

select tests.act_as(tests.turn_user((select id from r)));
select is(
  (select submit_clue((select id from r), 'Hospital') ->> 'ok'),
  'true',
  'IMP-33: escrever a própria palavra secreta é aceito (recusar vazaria o segredo)'
);
select tests.clear_identity();

-- ---------------------------------------------------------------------------
-- IMP-34 — palavra vulgar: recusa, conta falta e não consome o turno
--
-- Sala própria, e o turno é empurrado até cair no jogador 1 — que por construção
-- não é o host (0) nem o impostor (3). Sem isso o teste fica FLAKY: a ordem é
-- sorteada, e se o host levasse as 3 faltas a sala encerraria em vez de o turno
-- avançar, quebrando a asserção seguinte de forma intermitente.
-- ---------------------------------------------------------------------------

create temporary table cp as select tests.seed_room(4) as ctx;
create temporary table rp as select (ctx ->> 'room_id')::uuid as id from cp;

select tests.start_and_reveal(
  (select ctx from cp),
  (select id from w),
  ((select ctx -> 'players' from cp) ->> 3)::uuid
);

do $$
declare
  v_room_id uuid := (select id from rp);
  v_target  uuid := ((select ctx -> 'players' from cp) ->> 1)::uuid;
  v_guard   int  := 0;
begin
  while tests.turn_player(v_room_id) is distinct from v_target loop
    v_guard := v_guard + 1;
    if v_guard > 10 then
      raise exception 'não chegou no jogador alvo da ordem';
    end if;
    perform tests.act_as(tests.turn_user(v_room_id));
    perform submit_clue(v_room_id, 'dica');
  end loop;
  perform tests.clear_identity();
end;
$$;

create temporary table t as select tests.turn_player((select id from rp)) as player_id;
create temporary table tp as select clue_turn_index as idx from rooms where id = (select id from rp);

select tests.act_as(tests.turn_user((select id from rp)));
create temporary table g1 as select submit_clue((select id from rp), 'merda') as res;
select tests.clear_identity();

select is(
  (select res ->> 'reason' from g1),
  'PROFANITY',
  'IMP-34: palavra vulgar é recusada'
);

select is(
  (select (res ->> 'strikes')::int from g1),
  1,
  'IMP-34: a tentativa conta como falta'
);

-- A falta precisa SOBREVIVER à chamada: se `submit_clue` levantasse exceção, o
-- incremento voltaria a zero junto com a transação.
select is(
  (select profanity_strikes from players where id = (select player_id from t)),
  1,
  'IMP-34: a falta fica persistida (exceção desfaria o incremento)'
);

select is(
  (select clue_turn_index from rooms where id = (select id from rp)),
  (select idx from tp),
  'IMP-34: a recusa NÃO consome o turno — ele pode tentar outra palavra'
);

-- Variação com acento e maiúscula cai na mesma checagem normalizada.
select tests.act_as(tests.turn_user((select id from rp)));
select is(
  (select submit_clue((select id from rp), 'MERDA') ->> 'strikes'),
  '2',
  'IMP-34: comparação normalizada pega variação de caixa'
);
select tests.clear_identity();

-- Terceira falta expulsa.
select tests.act_as(tests.turn_user((select id from rp)));
create temporary table g3 as select submit_clue((select id from rp), 'bosta') as res;
select tests.clear_identity();

select is(
  (select res ->> 'kicked' from g3),
  'true',
  'IMP-34: a terceira falta expulsa o jogador'
);

select is(
  (select is_alive from players where id = (select player_id from t)),
  false,
  'IMP-34: o expulso sai da partida'
);

select isnt(
  (select clue_turn_index from rooms where id = (select id from rp)),
  (select idx from tp),
  'IMP-34: o turno não fica preso no jogador expulso'
);

-- ---------------------------------------------------------------------------
-- IMP-34 — impostor expulso encerra a partida (mesma regra do abandono, IMP-27)
-- ---------------------------------------------------------------------------

create temporary table cb as select tests.seed_room(4) as ctx;
create temporary table rb as select (ctx ->> 'room_id')::uuid as id from cb;

select tests.start_and_reveal(
  (select ctx from cb),
  (select id from w),
  ((select ctx -> 'players' from cb) ->> 2)::uuid
);

-- Leva o impostor a 2 faltas direto, e a terceira pela função.
update players set profanity_strikes = 2
where id = ((select ctx -> 'players' from cb) ->> 2)::uuid;

-- Empurra o turno até ser a vez do impostor.
do $$
declare
  v_room_id uuid := (select id from rb);
  v_impostor uuid := ((select ctx -> 'players' from cb) ->> 2)::uuid;
  v_guard int := 0;
begin
  while tests.turn_player(v_room_id) is distinct from v_impostor loop
    v_guard := v_guard + 1;
    exit when v_guard > 10;
    perform tests.act_as(tests.turn_user(v_room_id));
    perform submit_clue(v_room_id, 'dica');
  end loop;
  perform tests.clear_identity();
end;
$$;

select tests.act_as(tests.turn_user((select id from rb)));
select is(
  (select submit_clue((select id from rb), 'porra') ->> 'kicked'),
  'true',
  'IMP-34: impostor também é expulso na terceira falta'
);
select tests.clear_identity();

select is(
  (select outcome from rooms where id = (select id from rb)),
  'TRUTHERS_WIN'::game_outcome,
  'IMP-34: impostor expulso entrega a vitória aos verdadeiros'
);

-- ---------------------------------------------------------------------------
-- IMP-34 — host expulso encerra a sala (mesma regra do host saindo, IMP-25)
-- ---------------------------------------------------------------------------

create temporary table cc as select tests.seed_room(4) as ctx;
create temporary table rc as select (ctx ->> 'room_id')::uuid as id from cc;

select tests.start_and_reveal(
  (select ctx from cc),
  (select id from w),
  ((select ctx -> 'players' from cc) ->> 3)::uuid
);

update players set profanity_strikes = 2
where id = ((select ctx -> 'players' from cc) ->> 0)::uuid;

do $$
declare
  v_room_id uuid := (select id from rc);
  v_host    uuid := ((select ctx -> 'players' from cc) ->> 0)::uuid;
  v_guard   int := 0;
begin
  while tests.turn_player(v_room_id) is distinct from v_host loop
    v_guard := v_guard + 1;
    exit when v_guard > 10;
    perform tests.act_as(tests.turn_user(v_room_id));
    perform submit_clue(v_room_id, 'dica');
  end loop;
  perform tests.clear_identity();
end;
$$;

select tests.act_as(tests.turn_user((select id from rc)));
select lives_ok(
  format('select submit_clue(%L, %L)', (select id from rc), 'caralho'),
  'IMP-34: host na terceira falta não gera erro'
);
select tests.clear_identity();

select is(
  (select status from rooms where id = (select id from rc)),
  'CLOSED'::room_status,
  'IMP-34: host expulso encerra a sala, igual a host saindo'
);

select * from finish();
rollback;
