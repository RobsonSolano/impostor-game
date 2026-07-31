-- Jogo do Impostor — RLS, grants e helpers de autorização
--
-- Modelo: o cliente só LÊ. Nenhuma tabela recebe INSERT/UPDATE/DELETE para
-- anon/authenticated — toda escrita passa por função SECURITY DEFINER.
--
-- ATENÇÃO: o Supabase configura ALTER DEFAULT PRIVILEGES concedendo tudo em
-- `public` para anon/authenticated. Portanto os REVOKE abaixo não são
-- decorativos: sem eles, `rounds` e `votes` ficariam legíveis e o jogo,
-- trapaceável.

-- ---------------------------------------------------------------------------
-- Helpers de autorização
--
-- SECURITY DEFINER de propósito: são usados DENTRO de policies e precisam
-- ignorar RLS para não causar recursão infinita (a policy de `players`
-- perguntando à própria `players` quem sou eu).
-- ---------------------------------------------------------------------------

create or replace function is_room_member(p_room_id uuid)
returns boolean
language sql
security definer
set search_path = public, pg_temp
stable
as $$
  select exists (
    select 1
    from players
    where players.room_id = p_room_id
      and players.user_id = (select auth.uid())
  );
$$;

comment on function is_room_member is
  'Sou jogador desta sala? SECURITY DEFINER para evitar recursão de RLS quando '
  'usado nas policies de rooms/players.';

create or replace function owns_player(p_player_id uuid)
returns boolean
language sql
security definer
set search_path = public, pg_temp
stable
as $$
  select exists (
    select 1
    from players
    where players.id = p_player_id
      and players.user_id = (select auth.uid())
  );
$$;

comment on function owns_player is 'Este player sou eu?';

grant execute on function is_room_member(uuid) to authenticated;
grant execute on function owns_player(uuid)   to authenticated;

-- ---------------------------------------------------------------------------
-- Fecha tudo primeiro
-- ---------------------------------------------------------------------------

alter table words        enable row level security;
alter table rooms        enable row level security;
alter table players      enable row level security;
alter table rounds       enable row level security;
alter table player_cards enable row level security;
alter table votes        enable row level security;

revoke all on words        from anon, authenticated;
revoke all on rooms        from anon, authenticated;
revoke all on players      from anon, authenticated;
revoke all on rounds       from anon, authenticated;
revoke all on player_cards from anon, authenticated;
revoke all on votes        from anon, authenticated;

-- ---------------------------------------------------------------------------
-- words — leitura pública para usuários autenticados
--
-- Conhecer as 200 palavras não revela qual foi sorteada. O cliente usa isso
-- para exibir a categoria no resultado sem um round-trip extra.
-- ---------------------------------------------------------------------------

grant select on words to authenticated;

create policy words_select_all
  on words for select
  to authenticated
  using (true);

-- ---------------------------------------------------------------------------
-- rooms — legível por quem está na sala
--
-- Esta é a linha que trafega no Realtime para todos os jogadores. Segura
-- porque nenhuma coluna guarda segredo ativo (ver rooms_reveal_only_when_over_chk).
-- ---------------------------------------------------------------------------

grant select on rooms to authenticated;

create policy rooms_select_member
  on rooms for select
  to authenticated
  using (is_room_member(id));

-- ---------------------------------------------------------------------------
-- players — roster visível para os companheiros de sala
-- ---------------------------------------------------------------------------

grant select on players to authenticated;

create policy players_select_same_room
  on players for select
  to authenticated
  using (is_room_member(room_id));

-- ---------------------------------------------------------------------------
-- player_cards — cada um lê SOMENTE a própria linha
--
-- É aqui que o segredo é entregue. A policy é o único ponto que separa
-- "sei minha palavra" de "sei quem é o impostor".
-- ---------------------------------------------------------------------------

grant select on player_cards to authenticated;

create policy player_cards_select_own
  on player_cards for select
  to authenticated
  using (owns_player(player_id));

-- ---------------------------------------------------------------------------
-- rounds e votes — DENY ALL
--
-- Sem grant e sem policy. RLS ligada com zero policies = ninguém passa.
-- Só as funções SECURITY DEFINER da máquina de estados alcançam.
-- ---------------------------------------------------------------------------

-- (nenhum grant, nenhuma policy — intencional)
