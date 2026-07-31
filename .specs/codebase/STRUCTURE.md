# Estrutura de diretórios

```
.
├── .specs/                     # Fonte de verdade de planejamento
│   ├── project/                # PROJECT.md, ROADMAP.md, STATE.md
│   ├── codebase/               # Este conjunto de docs
│   └── features/               # YYYY-MM-DD-[feature]/{spec,design,tasks}.md
│
├── supabase/
│   ├── config.toml             # Config do banco local
│   ├── migrations/             # SQL versionado, aplicado em ordem
│   │   ├── ..._schema.sql      # Enums, tabelas, índices, publication
│   │   ├── ..._rls.sql         # Policies e grants
│   │   ├── ..._functions.sql   # RPCs da máquina de estados
│   │   └── ..._seed_words.sql  # 200 palavras em 10 categorias
│   └── tests/                  # pgTAP — regras do jogo
│
├── src/
│   ├── app/
│   │   ├── layout.tsx
│   │   ├── globals.css         # Tokens Tailwind 4 em @theme
│   │   ├── page.tsx            # Home: criar / entrar
│   │   └── sala/[code]/
│   │       └── page.tsx        # Shell de servidor (await params)
│   │
│   ├── components/
│   │   ├── ui/                 # shadcn/ui gerado — não editar à mão
│   │   ├── game/               # Uma tela por fase da máquina de estados
│   │   │   ├── GameRoom.tsx    # Switch por rooms.status
│   │   │   ├── LobbyPhase.tsx
│   │   │   ├── WordRevealPhase.tsx
│   │   │   ├── DiscussionPhase.tsx
│   │   │   ├── VotingPhase.tsx
│   │   │   ├── LastChancePhase.tsx
│   │   │   └── GameOverPhase.tsx
│   │   └── shared/             # HoldToReveal, PlayerAvatar, Drumroll...
│   │
│   ├── hooks/
│   │   ├── useRoomChannel.ts   # Subscriptions de rooms + players
│   │   └── useMyCard.ts        # Fetch do player_card por fase
│   │
│   └── lib/
│       ├── supabase/
│       │   ├── client.ts       # Browser client
│       │   ├── server.ts       # Server client (cookies)
│       │   └── database.types.ts  # GERADO — supabase gen types
│       ├── game/               # Helpers puros e testáveis
│       └── utils.ts            # cn()
│
├── AGENTS.md / CLAUDE.md       # Regras para agentes
├── next.config.ts
└── vitest.config.ts
```

## Onde colocar o quê

| Preciso de... | Vai em |
|---|---|
| Nova regra de jogo | `supabase/migrations/` (função SQL) + teste pgTAP. **Nunca** no cliente |
| Nova tela de fase | `src/components/game/` + case no switch de `GameRoom.tsx` |
| Animação reusável | `src/components/shared/` |
| Lógica pura testável (formatação, validação de código de sala) | `src/lib/game/` + teste vitest |
| Componente de UI genérico | `npx shadcn@latest add <nome>` → `src/components/ui/` |
