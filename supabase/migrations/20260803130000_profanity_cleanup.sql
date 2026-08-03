-- Tira da lista de palavrões o que é palavra comum ou dica legítima
--
-- A lista original punia jogo honesto:
--
-- - `macaco` é uma das 200 palavras SECRETAS (categoria ANIMAIS). O jogo podia
--   sortear "Macaco" e recusar quem falasse dele.
-- - `pinto` é a dica óbvia para Galinha, `teta` para Vaca, `coco` para Praia,
--   `peito` para Galinha — todas palavras secretas que existem no baralho.
-- - `matar` e `morrer` não são palavrões: são a dica natural para Cobra e Hospital.
-- - `preto` é sobretudo uma cor, e dica plausível para Gato e Pinguim.
--
-- Como três faltas expulsam, isso significava criança sendo removida da sala por
-- dar a dica certa. O filtro existe para conter agressão e vulgaridade, não para
-- vetar vocabulário infantil.
--
-- O que CONTINUA bloqueado: vulgaridade sexual explícita, insultos, xingamentos
-- capacitistas, slurs, apologia (nazismo) e violência sexual.

delete from profanity_words
where normalize_word(word) in (
  -- Colide com palavra secreta do jogo.
  'macaco',
  -- Dica legítima para palavra secreta existente.
  'pinto', 'teta', 'peito', 'coco', 'seio', 'mamilo',
  -- Verbos comuns, não palavrões.
  'matar', 'morrer',
  -- Sobretudo cor.
  'preto',
  -- Ambíguos demais para punir: também são verbos do dia a dia.
  'rola', 'pica',
  -- Escatologia infantil: rende risada, não agressão, e não vale expulsar por isso.
  'bunda', 'peido', 'xixi', 'cocô'
);

-- ---------------------------------------------------------------------------
-- Invariante: palavrão nunca pode ser palavra secreta
-- ---------------------------------------------------------------------------
--
-- Trigger em vez de constraint porque a regra cruza duas tabelas. Vale nas duas
-- direções: nem entra palavrão que já é palavra do jogo, nem entra palavra do
-- jogo que está na lista de palavrões.

create or replace function assert_word_not_profane()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if exists (
    select 1
    from words w
    join profanity_words p on normalize_word(p.word) = normalize_word(w.text)
  ) then
    raise exception
      'Palavra secreta e lista de palavrões se sobrepõem: o jogo recusaria a dica '
      'correta e daria falta a quem jogou certo'
      using errcode = 'IM004';
  end if;
  return null;
end;
$$;

create constraint trigger words_not_profane_trg
  after insert or update on words
  deferrable initially deferred
  for each row execute function assert_word_not_profane();

create constraint trigger profanity_not_word_trg
  after insert or update on profanity_words
  deferrable initially deferred
  for each row execute function assert_word_not_profane();

revoke all on function assert_word_not_profane() from public;
