-- Sorteio do impostor ponderado por tempo sem ser impostor (IMP-38)
--
-- PROBLEMA REAL relatado em mesa de 4: a mesma pessoa foi impostor 3 vezes
-- seguidas, depois outra uma vez, depois a primeira mais 3 vezes. Sorteio
-- uniforme faz isso com frequência incômoda — em mesa de 4 são 25% de repetir na
-- seguida e 6,4% de emendar três.
--
-- REGRA DESCARTADA: excluir do sorteio os dois últimos impostores. Distribui
-- perfeitamente, mas ENTREGA o jogo em mesa pequena, que é justamente o caso de
-- uso. Com 4 jogadores sobram 2 candidatos (a mesa ganha 50% de graça antes de
-- qualquer dica); com 3 jogadores sobra 1, e o impostor fica identificado pela
-- própria regra.
--
-- REGRA ADOTADA: peso = (rodadas desde que foi impostor)². Ninguém é excluído,
-- só fica improvável. Medido em simulação de 20 mil mesas de 4 jogadores:
--
--                          repete seguido   3 seguidas   candidatos p/ mesa
--   uniforme (antes)            25,1%          6,40%          4,00 de 4
--   excluir os 2 últimos         0,0%          0,00%          2,25 de 4  ← vaza
--   peso quadrático (este)       3,4%          0,07%          4,00 de 4
--
-- Efeito colateral bom: repetir vira o melhor disfarce do jogo, porque ninguém
-- suspeita de quem acabou de ser. Com exclusão isso é impossível e a suspeita se
-- concentra sozinha.

/**
 * Peso do jogador no sorteio do impostor.
 *
 * Quadrado da distância até a última vez que ele foi impostor nesta sala. Quem
 * nunca foi recebe o peso máximo. Nunca retorna zero: exclusão é justamente o que
 * esta regra evita.
 */
create or replace function impostor_weight(
  p_room_id      uuid,
  p_player_id    uuid,
  p_round_number int
)
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select power(
           greatest(
             p_round_number - coalesce(
               (select max(r.round_number)
                from rounds r
                where r.room_id = p_room_id and r.impostor_player_id = p_player_id),
               0
             ),
             1
           ),
           2
         )::int;
$$;

comment on function impostor_weight(uuid, uuid, int) is
  'Peso do jogador no sorteio do impostor: (rodadas desde a última vez)². Nunca '
  'zero — ninguém é excluído, para a mesa não conseguir deduzir quem NÃO pode ser.';

create or replace function begin_round(
  p_room_id           uuid,
  p_force_word_id     int  default null,
  p_force_impostor_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_word_id     int;
  v_category    word_category;
  v_impostor_id uuid;
  v_round_id    uuid;
  v_number      int;
  v_options     int[];
  v_word_text   text;
begin
  select coalesce(max(round_number), 0) + 1 into v_number
  from rounds where room_id = p_room_id;

  -- ORDEM IMPORTA: o impostor é sorteado ANTES da palavra.
  -- Uma sala sem impostor não tem jogo, então esta é a primeira coisa a existir
  -- e a primeira a falhar se algo estiver errado.
  if p_force_impostor_id is not null then
    v_impostor_id := p_force_impostor_id;
  else
    -- Sorteio ponderado (IMP-38). `random() ^ (1/peso)` e pegar o maior é
    -- amostragem proporcional ao peso (Efraimidis-Spirakis): peso maior empurra a
    -- chave para perto de 1. Todo jogador ativo continua no sorteio — quem acabou
    -- de ser impostor tem peso 1, não zero.
    select p.id into v_impostor_id
    from players p
    where p.room_id = p_room_id and p.is_alive
    order by power(random(), 1.0 / impostor_weight(p_room_id, p.id, v_number)) desc
    limit 1;
  end if;

  -- Guarda explícita. `rounds.impostor_player_id` é NOT NULL, então o insert já
  -- falharia — mas com mensagem de constraint, não de regra. Falhar aqui deixa
  -- claro o que aconteceu.
  if v_impostor_id is null then
    raise exception 'Não há jogador elegível para ser o impostor' using errcode = 'IM005';
  end if;

  if not exists (
    select 1 from players
    where id = v_impostor_id and room_id = p_room_id and is_alive
  ) then
    raise exception 'O impostor sorteado não é um jogador ativo desta sala'
      using errcode = 'IM004';
  end if;

  -- Palavra ainda não usada nesta sala. Se o baralho esgotar, libera tudo de novo.
  if p_force_word_id is not null then
    v_word_id := p_force_word_id;
  else
    select id into v_word_id
    from words
    where id not in (select word_id from rounds where room_id = p_room_id)
    order by random()
    limit 1;

    if v_word_id is null then
      select id into v_word_id from words order by random() limit 1;
    end if;
  end if;

  select category, text into v_category, v_word_text from words where id = v_word_id;
  if v_word_text is null then
    raise exception 'Palavra % não existe', v_word_id using errcode = 'IM004';
  end if;

  -- As 4 opções da Última Chance nascem com a rodada, mas NÃO vão para o card
  -- ainda: vê-las antes da hora entregaria a resposta.
  select array_agg(id) into v_options
  from (
    select w.id
    from words w
    where w.category = v_category and w.id <> v_word_id
    order by random()
    limit 3
  ) t;

  v_options := v_options || v_word_id;

  insert into rounds (room_id, round_number, word_id, impostor_player_id, last_chance_word_ids)
  values (p_room_id, v_number, v_word_id, v_impostor_id, v_options)
  returning id into v_round_id;

  insert into player_cards (round_id, room_id, player_id, is_impostor, word_text)
  select
    v_round_id,
    p_room_id,
    p.id,
    p.id = v_impostor_id,
    case when p.id = v_impostor_id then null else v_word_text end
  from players p
  where p.room_id = p_room_id and p.is_alive;

  update players set has_seen_card = false, has_voted = false where room_id = p_room_id;

  -- Limpa o resultado da partida anterior no mesmo UPDATE que sai de GAME_OVER,
  -- para não violar rooms_reveal_only_when_over_chk.
  update rooms set
    status               = 'WORD_REVEAL',
    active_round_id      = v_round_id,
    discussion_round     = 1,
    voting_cycle         = 0,
    votes_cast           = 0,
    -- Estado de turno da partida anterior não sobrevive à nova.
    clue_turn_index      = 0,
    turn_deadline        = null,
    guess_deadline       = null,
    outcome              = null,
    eliminated_player_id = null,
    revealed_word        = null,
    revealed_impostor_id = null,
    last_vote_tally      = null
  where id = p_room_id;

  return v_round_id;
end;
$$;

revoke all on function impostor_weight(uuid, uuid, int) from public;
revoke all on function begin_round(uuid, int, uuid) from public;
