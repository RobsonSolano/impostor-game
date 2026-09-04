-- ---------------------------------------------------------------------------
-- Salas públicas e listagem (IMP-40)
--
-- Até aqui só existia um caminho para entrar numa sala: alguém te passa o código
-- de 4 letras. Isso cobre a mesa de bar, mas fecha o jogo para quem quer jogar
-- agora e não tem com quem.
--
-- A decisão de segurança que sustenta esta migration: **a listagem NÃO pode
-- vir de uma policy nova em `rooms`**. A policy atual é `is_room_member(id)`, e
-- afrouxá-la para "público pode ler sala pública" vazaria TODAS as colunas de
-- `rooms` daquela sala — inclusive `revealed_word`, `revealed_impostor_id` e
-- `last_vote_tally`. RLS filtra linhas, não colunas (AGENTS.md, regra 2).
--
-- Então a listagem é uma função `SECURITY DEFINER` que devolve uma projeção
-- explícita de colunas seguras, e a policy de `rooms` continua intocada.
-- ---------------------------------------------------------------------------

alter table rooms add column is_public boolean not null default false;
alter table rooms add column title text;

-- Título é opcional: exigir um só para abrir a sala é atrito, e a lista sempre
-- tem o nome do host como identificação de reserva.
alter table rooms add constraint rooms_title_len_chk
  check (title is null or char_length(btrim(title)) between 3 and 30);

-- A listagem só olha sala pública em LOBBY. Índice parcial porque essa é
-- exatamente a fatia consultada, e ela é minúscula perto da tabela toda.
create index rooms_public_lobby_idx
  on rooms (created_at desc)
  where is_public and status = 'LOBBY';

-- ---------------------------------------------------------------------------
-- Palavrão em texto de várias palavras
--
-- `is_profane` compara UMA palavra normalizada com a lista — serve para a dica,
-- que é um termo só. Um título de sala tem várias, então precisa de quebra por
-- palavra. Sem isto, "sala do <palavrão>" passaria batido.
-- ---------------------------------------------------------------------------
create or replace function has_profanity(p_text text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from regexp_split_to_table(coalesce(p_text, ''), '\s+') as palavra
    where is_profane(palavra)
  );
$$;

revoke all on function has_profanity(text) from public;

-- ---------------------------------------------------------------------------
-- create_room ganha visibilidade e título
--
-- `drop` antes de recriar, e não `create or replace`: mudar a lista de
-- parâmetros cria uma função NOVA por sobrecarga em vez de substituir a antiga.
-- Ficariam as duas, e uma chamada de 1 argumento continuaria caindo na versão
-- velha — que ignora `is_public` e criaria toda sala como privada, em silêncio.
-- ---------------------------------------------------------------------------
drop function if exists create_room(text);

create or replace function create_room(
  p_name      text,
  p_is_public boolean default false,
  p_title     text    default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid       uuid := require_uid();
  v_name      text := btrim(coalesce(p_name, ''));
  v_title     text := nullif(btrim(coalesce(p_title, '')), '');
  v_room_id   uuid;
  v_player_id uuid;
  v_code      text;
  v_attempt   int  := 0;
begin
  if char_length(v_name) < 1 or char_length(v_name) > 20 then
    raise exception 'O nome precisa ter entre 1 e 20 caracteres' using errcode = 'IM004';
  end if;

  if v_title is not null and char_length(v_title) not between 3 and 30 then
    raise exception 'O nome da sala precisa ter entre 3 e 30 caracteres' using errcode = 'IM004';
  end if;

  /*
   * Título de sala pública é a única superfície deste jogo que estranhos leem
   * sem entrar em nada. Por isso aqui o palavrão LEVANTA exceção, diferente da
   * dica (que devolve `ok: false` para o banco poder persistir a falta): a sala
   * simplesmente não é criada e o host digita outro nome.
   *
   * Só vale para sala pública — em sala privada o título só é visto por quem já
   * foi convidado, e a mesa resolve entre si.
   */
  if p_is_public and v_title is not null and has_profanity(v_title) then
    raise exception 'Escolha outro nome para a sala' using errcode = 'IM004';
  end if;

  -- Colisão de código é rara (32^4 ≈ 1,05 milhão) mas possível. Retry silencioso.
  loop
    v_attempt := v_attempt + 1;
    v_code := gen_room_code();
    begin
      insert into rooms (code, is_public, title)
      values (v_code, coalesce(p_is_public, false), v_title)
      returning id into v_room_id;
      exit;
    exception when unique_violation then
      if v_attempt >= 20 then
        raise exception 'Não foi possível gerar um código de sala' using errcode = 'IM005';
      end if;
    end;
  end loop;

  insert into players (room_id, user_id, name, avatar_color)
  values (v_room_id, v_uid, v_name, pick_avatar_color(v_room_id))
  returning id into v_player_id;

  update rooms set host_player_id = v_player_id where id = v_room_id;

  return jsonb_build_object('room_id', v_room_id, 'player_id', v_player_id, 'code', v_code);
end;
$$;

revoke all on function create_room(text, boolean, text) from public;
grant execute on function create_room(text, boolean, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Listagem das salas abertas
--
-- Projeção EXPLÍCITA de colunas. Nada de `select r.*`: esta função roda como
-- dono e ignora RLS, então a lista de colunas aqui é a única barreira entre um
-- estranho e o segredo da partida. Se alguém acrescentar coluna a `rooms` no
-- futuro, ela não aparece aqui por acidente.
--
-- Só LOBBY: uma partida em andamento não é listada, e por consequência nem o
-- código dela vaza. Quem já está jogando não é incomodado por quem chega.
--
-- Não devolve `rooms.id`. O identificador público do jogo é o código de 4
-- letras, que é o que `join_room` consome — expor o uuid só daria superfície.
-- ---------------------------------------------------------------------------
create or replace function list_public_rooms(p_search text default null)
returns table (
  code       text,
  title      text,
  host_name  text,
  players    int,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_busca text := nullif(btrim(coalesce(p_search, '')), '');
begin
  -- Convenção do projeto: toda função de jogo começa exigindo identidade. Aqui
  -- é redundante com o grant, e é de propósito — um grant frouxo no futuro não
  -- deve abrir a listagem para anônimo.
  perform require_uid();

  return query
    select r.code,
           r.title,
           h.name as host_name,
           (select count(*)::int from players p where p.room_id = r.id) as players,
           r.created_at
    from rooms r
    left join players h on h.id = r.host_player_id
    where r.is_public
      and r.status = 'LOBBY'
      and (
        v_busca is null
        or r.title ilike '%' || v_busca || '%'
        or h.name ilike '%' || v_busca || '%'
        -- Busca pelo código também: quem recebeu o código de uma sala pública
        -- acha ela na lista sem precisar trocar de aba.
        or r.code = upper(v_busca)
      )
    order by r.created_at desc
    limit 50;
end;
$$;

revoke all on function list_public_rooms(text) from public;
grant execute on function list_public_rooms(text) to authenticated;

comment on function list_public_rooms(text) is
  'Salas públicas em LOBBY, com projeção explícita de colunas seguras. Roda como dono e ignora RLS — não acrescente colunas aqui sem confirmar que não são segredo de partida.';
