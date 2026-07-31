# Testes

## Onde o teste tem valor neste projeto

As regras do jogo vivem em **SQL**, não em TypeScript. Um teste de componente que mocka o Supabase provaria que o mock funciona, não que o jogo funciona. Então o peso dos testes está em pgTAP.

| Camada | Ferramenta | O que cobre |
|---|---|---|
| Regras do jogo | pgTAP (`supabase test db`) | Máquina de estados, apuração de votos, isolamento do segredo, RLS |
| Lógica pura de cliente | vitest | Validação/normalização de código de sala, formatação, cálculo de deadline |
| Componentes | vitest + Testing Library | Só onde há interação não trivial (hold-to-reveal) |

Não há teste E2E automatizado no v1 — o jogo é multi-dispositivo e o custo de orquestrar isso não se paga ainda. Validação multi-cliente é manual (dois navegadores).

## Comandos

```bash
# Banco local (necessário para pgTAP) — precisa de Docker
npx supabase start

# Regras do jogo
npx supabase test db

# Reaplicar migrations do zero e reexecutar seed
npx supabase db reset

# Testes de cliente
npm test              # vitest run
npm run test:watch    # vitest

# Suite completa (gate de pré-commit)
npm run verify        # tsc --noEmit && eslint && vitest run && supabase test db && next build
```

## Padrões de teste pgTAP

- Cada arquivo em `supabase/tests/` roda dentro de uma transação e faz `ROLLBACK` no fim (`BEGIN` / `SELECT plan(n)` / asserções / `SELECT * FROM finish()` / `ROLLBACK`).
- Usuários de teste são criados direto em `auth.users`; a identidade é simulada com `SET LOCAL role authenticated` + `SET LOCAL request.jwt.claims`.
- **Nomear o teste com o ID do requisito.** Ex: `IMP-08: empate na votação devolve para DISCUSSION`. Isso é o que liga spec → teste → commit.
- Determinismo: as funções sorteiam palavra e impostor. Nos testes, fixar o resultado passando os parâmetros de override (`p_force_word_id`, `p_force_impostor_id`) que existem **apenas** para teste e são ignorados quando nulos.

## Anti-padrões proibidos

- Testar que uma função foi chamada em vez de testar o efeito no banco.
- Mockar o cliente Supabase para "testar" regra de jogo.
- Teste que passa sem o banco rodando — se não tocou o Postgres, não testou a regra.
