# Convenções

## Idioma

- **Código** (identificadores, tipos, nomes de arquivo): inglês.
- **UI, mensagens de erro visíveis, specs, commits**: PT-BR com acentuação correta.
- **Nomes de rota**: PT-BR (`/sala/[code]`) porque aparecem na URL que o jogador digita.

## SQL

- Tabelas e colunas em `snake_case`, plural para tabelas (`rooms`, `player_cards`).
- Enums em `SCREAMING_SNAKE_CASE` para os valores (`WORD_REVEAL`), nome do tipo em `snake_case` (`room_status`).
- Toda função de jogo é `SECURITY DEFINER` com `SET search_path = public, pg_temp` — sem exceção. Sem isso a função é um vetor de escalonamento de privilégio.
- Funções de jogo levam prefixo do domínio quando ambíguo; ações diretas ficam com verbo simples (`create_room`, `cast_vote`).
- Parâmetros de função com prefixo `p_` (`p_room_id`) para nunca colidirem com nomes de coluna dentro do corpo.
- Erros de regra de jogo usam `RAISE EXCEPTION ... USING errcode` com códigos próprios, para o cliente distinguir "não é sua vez" de falha real.

## TypeScript / React

- Componentes em `PascalCase`, um por arquivo, arquivo com o mesmo nome.
- Hooks em `camelCase` com prefixo `use`, em `src/hooks/`.
- `'use client'` só onde há estado, evento ou Realtime. As pages são shells de servidor.
- Tipos de banco vêm de `supabase gen types` em `src/lib/supabase/database.types.ts` — **nunca** escritos à mão. Aliases de conveniência ficam em `src/lib/types.ts`.
- Nada de `any`. Se o tipo gerado não bate, o schema é que está errado.
- Sem barrel files (`index.ts` reexportando) — import direto, para o Turbopack não puxar módulo demais.

## Tailwind 4

- Tokens de tema em `@theme` dentro de `src/app/globals.css`. Não existe `tailwind.config.js`.
- Classes utilitárias inline. `cn()` (clsx + tailwind-merge) para composição condicional.
- Mobile-first sempre: estilo base é o do celular, `sm:`/`md:` só corrigem para telas grandes.

## Estado do cliente

- Fonte de verdade é o banco. Estado local só para o que é puramente visual (progresso do hold-to-reveal, contagem do drumroll, seleção de voto antes de confirmar).
- Nenhuma regra de jogo duplicada no cliente. Se o cliente precisa saber se uma ação é válida, ele lê `status` — não recalcula.

## Commits

Conventional Commits em PT-BR no corpo, escopo em inglês:

| Escopo | Cobre |
|---|---|
| `db` | migrations, RLS, funções SQL, seed |
| `game` | RPCs de máquina de estados |
| `ui` | componentes e telas |
| `realtime` | hooks e subscriptions |
| `infra` | build, deploy, config, CI |
| `specs` | artefatos `.specs/` |
