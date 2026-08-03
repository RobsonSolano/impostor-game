-- Regras do banco de palavras
--
-- A lista vai crescer com o tempo, e é fácil alguém acrescentar uma frase ou um
-- termo que criança de 9 anos não conhece. Estes testes existem para a regra
-- valer para quem mexer na lista depois.
begin;
create extension if not exists pgtap;

select plan(11);

select is((select count(*)::int from words), 200, 'Seed tem 200 palavras');

select is(
  (select count(*)::int from (select category from words group by category having count(*) = 20) t),
  10,
  'As 10 categorias têm 20 palavras cada'
);

-- UMA palavra: o jogo é dar dicas SOBRE a palavra, e uma frase já é a dica.
select is(
  (select count(*)::int from words where text ~ '\s'),
  0,
  'Nenhuma palavra contém espaço — nada de "Entrevista de Emprego"'
);

select is(
  (select count(*)::int from words where char_length(text) not between 3 and 15),
  0,
  'Todas têm entre 3 e 15 caracteres'
);

select is(
  (select count(distinct text)::int from words),
  200,
  'Não há palavra repetida'
);

-- Os 3 distratores da Última Chance saem da MESMA categoria da palavra secreta.
select is(
  (select count(*)::int from (select category from words group by category having count(*) < 4) t),
  0,
  'Toda categoria tem pelo menos 4 palavras, senão a Última Chance fica óbvia'
);

-- Os checks precisam recusar de verdade, não só descrever a intenção.
select throws_ok(
  $$insert into words (text, category) values ('Entrevista de Emprego', 'EVENTOS')$$,
  '23514',
  null,
  'O banco recusa frase como palavra'
);

select throws_ok(
  $$insert into words (text, category) values ('Responsabilidade Civil Ampliada', 'EVENTOS')$$,
  '23514',
  null,
  'O banco recusa palavra longa demais'
);

-- ---------------------------------------------------------------------------
-- O filtro de vulgaridade não pode punir jogo honesto
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::int from words w
   join profanity_words p on normalize_word(p.word) = normalize_word(w.text)),
  0,
  'Nenhuma palavra secreta está na lista de palavrões — senão o jogo recusaria a dica certa'
);

-- Dicas óbvias de palavras que existem no baralho precisam passar.
select is(
  (select count(*)::int from profanity_words
   where normalize_word(word) in ('pinto', 'teta', 'coco', 'peito', 'matar', 'preto')),
  0,
  'Dicas legítimas (pinto/Galinha, teta/Vaca, coco/Praia) não são tratadas como palavrão'
);

-- E o filtro continua fazendo o trabalho dele.
select ok(
  is_profane('caralho') and is_profane('BUCETA') and is_profane('retardado'),
  'Vulgaridade e xingamento continuam bloqueados'
);

select * from finish();
rollback;
