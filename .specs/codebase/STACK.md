# Stack

## Runtime

| Item | Versão | Nota |
|---|---|---|
| Node.js | 20.20.2 | Local. Vercel usa Node 24 LTS por padrão |
| npm | 10.8.2 | Lockfile v3 |
| Docker | 29.1.3 | Só para Supabase local / pgTAP |

## Aplicação

| Pacote | Versão | Papel |
|---|---|---|
| `next` | 16.2.12 | App Router, Turbopack por padrão |
| `react` / `react-dom` | 19.2.4 | App Router usa canary interno do React |
| `typescript` | ^5 | `strict` ligado |
| `tailwindcss` | ^4 | Config em CSS (`@theme`), sem `tailwind.config.js` |
| `@supabase/supabase-js` | ^2.111 | Cliente de dados + Realtime |
| `@supabase/ssr` | ^0.12 | Sessão via cookies em Server Components |
| `motion` | ^12.43 | Framer Motion (pacote renomeado; importar de `motion/react`) |
| `clsx` + `tailwind-merge` | — | Helper `cn()` do shadcn |
| `class-variance-authority` | — | Variantes dos componentes shadcn |
| `lucide-react` | — | Ícones |

## Testes

| Pacote | Papel |
|---|---|
| `vitest` ^4 | Testes de unidade da lógica de cliente |
| `@testing-library/react` + `jsdom` | Testes de componente |
| pgTAP via `supabase test db` | Testes das regras do jogo (que vivem em SQL) |
| `supabase` (CLI, devDep) | Migrations, tipos gerados, banco local |

## Infra

- **Frontend:** Vercel.
- **Banco + Realtime + Auth:** Supabase gerenciado. Autenticação **anônima** (exige habilitar *Anonymous sign-ins* no dashboard).
- **CLI Vercel:** não instalada localmente. `npm i -g vercel` habilita `vercel env pull` e `vercel deploy`.

## Particularidades do Next 16 que afetam este código

Lidas em `node_modules/next/dist/docs/01-app/02-guides/upgrading/version-16.md`:

- `params` e `searchParams` são **sempre** assíncronos. `await params` em toda page dinâmica.
- `middleware.ts` foi renomeado para `proxy.ts` (não usamos nenhum dos dois).
- `next lint` foi removido — lint é `eslint` direto, e `next build` não linta mais.
- Turbopack é o bundler padrão em dev e build.
- React 19.2 traz `useEffectEvent` e `<Activity>`, úteis para lógica de Realtime e para manter telas de fase montadas.
