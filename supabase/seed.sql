-- Helpers de TESTE — aplicados só no banco local.
--
-- Estes helpers fabricam usuários em `auth.users` e forçam estado de jogo. Isso
-- não pode existir em produção, nem com os grants revogados: é superfície que o
-- jogo não precisa e que um acesso elevado poderia abusar.
--
-- Por isso vivem em `seed.sql` e NÃO em `migrations/`: o `db reset` local aplica
-- migrations + seed (então o pgTAP encontra os helpers), enquanto o `db push`
-- envia apenas as migrations para o remoto.
--
-- Jogo do Impostor — helpers de teste (schema `tests`)
--
-- POR QUE ISSO ESTÁ EM UMA MIGRATION E NÃO NO ARQUIVO DE TESTE:
-- `supabase test db` roda cada arquivo de supabase/tests/ em uma transação
-- própria, então helpers definidos em um arquivo não existem no seguinte.
-- Duplicar a simulação de JWT em 8 arquivos é pior do que um schema isolado.
--
-- Segurança: schema `tests` sem USAGE e funções sem EXECUTE para
-- anon/authenticated. Só um superusuário (o runner de teste) alcança. Estas
-- funções tocam auth.users e NUNCA podem ficar acessíveis ao cliente.

create schema if not exists tests;

-- Cria um usuário anônimo em auth.users, como faria signInAnonymously().
create or replace function tests.create_anon_user(p_label text)
returns uuid
language plpgsql
as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into auth.users (id, aud, role, email, is_anonymous, created_at, updated_at)
  values (v_id, 'authenticated', 'authenticated', p_label || '@teste.local', true, now(), now());
  return v_id;
end;
$$;

-- Assume a IDENTIDADE (auth.uid()) sem trocar de role.
--
-- É o helper usado nos testes de regra de jogo: as RPCs são SECURITY DEFINER e
-- leem auth.uid() de request.jwt.claims, então isso basta — e mantém o teste
-- como superusuário, livre para montar o próximo passo do cenário.
create or replace function tests.act_as(p_user_id uuid)
returns void
language plpgsql
as $$
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user_id::text, 'role', 'authenticated')::text,
    true
  );
end;
$$;

-- Assume identidade E role `authenticated`, do jeito que o PostgREST faz.
--
-- Necessário só nos testes de RLS (IMP-06), onde o que está sob teste é
-- justamente o que o role `authenticated` consegue ler. Para voltar, use
-- `reset role` — comando simples, sempre permitido.
create or replace function tests.authenticate_as(p_user_id uuid)
returns void
language plpgsql
as $$
begin
  perform tests.act_as(p_user_id);
  perform set_config('role', 'authenticated', true);
end;
$$;

create or replace function tests.clear_identity()
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims', '', true);
end;
$$;

-- Monta uma sala com N jogadores prontos no lobby.
-- Retorna { room_id, code, users[], players[] } na ordem de entrada — o índice 0
-- é sempre o host.
create or replace function tests.seed_room(p_player_count int)
returns jsonb
language plpgsql
as $$
declare
  v_users   uuid[] := '{}';
  v_players uuid[] := '{}';
  v_room_id uuid;
  v_code    text;
  v_uid     uuid;
  v_res     jsonb;
  i         int;
begin
  for i in 1 .. p_player_count loop
    v_uid := tests.create_anon_user('jogador' || i || '_' || replace(gen_random_uuid()::text, '-', ''));
    v_users := v_users || v_uid;

    perform tests.act_as(v_uid);

    if i = 1 then
      v_res := create_room('Jogador' || i);
      v_room_id := (v_res ->> 'room_id')::uuid;
      v_code := v_res ->> 'code';
    else
      v_res := join_room(v_code, 'Jogador' || i);
    end if;

    v_players := v_players || (v_res ->> 'player_id')::uuid;
  end loop;

  perform tests.clear_identity();

  return jsonb_build_object(
    'room_id', v_room_id,
    'code',    v_code,
    'users',   to_jsonb(v_users),
    'players', to_jsonb(v_players)
  );
end;
$$;

-- Leva uma sala do lobby até DISCUSSION com palavra e impostor fixos.
-- Sem isso, testar "o impostor foi eliminado" seria um sorteio.
create or replace function tests.start_and_reveal(
  p_ctx               jsonb,
  p_force_word_id     int,
  p_force_impostor_id uuid
)
returns void
language plpgsql
as $$
declare
  v_room_id uuid := (p_ctx ->> 'room_id')::uuid;
  v_user    text;
begin
  perform tests.act_as(((p_ctx -> 'users') ->> 0)::uuid);
  perform start_game(v_room_id, p_force_word_id, p_force_impostor_id);

  for v_user in select jsonb_array_elements_text(p_ctx -> 'users') loop
    perform tests.act_as(v_user::uuid);
    perform confirm_word_seen(v_room_id);
  end loop;

  perform tests.clear_identity();
end;
$$;

-- Abre a votação (como host) e registra os votos informados.
-- p_votes: array de índices de jogador; NULL no lugar do alvo = "Pular Votação".
-- Ex: '[{"voter":1,"target":0},{"voter":2,"target":null}]'
create or replace function tests.run_voting(p_ctx jsonb, p_votes jsonb)
returns void
language plpgsql
as $$
declare
  v_room_id uuid := (p_ctx ->> 'room_id')::uuid;
  v_vote    jsonb;
  v_target  uuid;
begin
  perform tests.act_as(((p_ctx -> 'users') ->> 0)::uuid);
  perform open_voting(v_room_id);

  for v_vote in select jsonb_array_elements(p_votes) loop
    perform tests.act_as(((p_ctx -> 'users') ->> (v_vote ->> 'voter')::int)::uuid);

    if v_vote ->> 'target' is null then
      v_target := null;
    else
      v_target := ((p_ctx -> 'players') ->> (v_vote ->> 'target')::int)::uuid;
    end if;

    perform cast_vote(v_room_id, v_target);
  end loop;

  perform tests.clear_identity();
end;
$$;

-- Atalho para o cenário mais usado: 4 jogadores, impostor no índice 3 (para o
-- host ser sempre um verdadeiro), mesa descobrindo o impostor por 3 votos a 1.
-- Deixa a sala em LAST_CHANCE.
create or replace function tests.reach_last_chance(p_word_text text)
returns jsonb
language plpgsql
as $$
declare
  v_ctx     jsonb := tests.seed_room(4);
  v_word_id int;
begin
  select id into v_word_id from words where text = p_word_text;
  if v_word_id is null then
    raise exception 'Palavra de teste % não existe no seed', p_word_text;
  end if;

  perform tests.start_and_reveal(v_ctx, v_word_id, ((v_ctx -> 'players') ->> 3)::uuid);
  perform tests.run_voting(
    v_ctx,
    '[{"voter":0,"target":3},{"voter":1,"target":3},{"voter":2,"target":3},{"voter":3,"target":0}]'::jsonb
  );

  return v_ctx;
end;
$$;

revoke all on schema tests from public;
revoke all on all functions in schema tests from public;
