# Integrações externas

## Supabase

Única dependência externa do projeto. Cobre banco, tempo real e identidade.

| Recurso | Uso |
|---|---|
| PostgreSQL | Estado do jogo + banco de palavras |
| Realtime (`postgres_changes`) | Sincronia de fase entre celulares. Subscriptions em `rooms` (por `id`) e `players` (por `room_id`) |
| Auth — Anonymous sign-ins | Identidade sem cadastro. `signInAnonymously()` no primeiro acesso |
| RPC (PostgREST) | Toda ação de jogo — as funções SQL são a API |

### Variáveis de ambiente

| Variável | Onde | Nota |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | cliente + servidor | Pública |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | cliente + servidor | Pública. Segurança vem de RLS, não do sigilo desta chave |

Não usamos `SERVICE_ROLE_KEY` em lugar nenhum da aplicação. Se algum dia aparecer uma, é sinal de que uma regra de jogo escapou do banco.

### Setup manual obrigatório no dashboard

1. **Authentication → Sign In / Providers → Anonymous sign-ins: ON.** Sem isso `signInAnonymously()` retorna 422 e ninguém entra em sala.
2. Confirmar que as tabelas `rooms` e `players` estão na publication `supabase_realtime` (as migrations já fazem isso, mas vale conferir em Database → Publications).

### Aplicar o schema

```bash
npx supabase link --project-ref <ref>
npx supabase db push
```

Alternativa sem CLI: colar o conteúdo de `supabase/migrations/*.sql`, em ordem de nome, no SQL Editor.

### Gerar tipos após mudar o schema

```bash
npx supabase gen types typescript --local > src/lib/supabase/database.types.ts
```

## Vercel

Deploy do frontend. Sem integração de runtime além das duas env vars acima. CLI não instalada localmente — `npm i -g vercel` habilita `vercel env pull` e `vercel deploy`.

## Não integrado (e por quê)

- **Serviço de WebSocket dedicado** (Pusher/Ably): Supabase Realtime já resolve, e um segundo canal significaria duas fontes de verdade.
- **Analytics / Sentry**: projeto pessoal, sem necessidade no v1.
- **Provider de e-mail**: não há cadastro, não há e-mail.
