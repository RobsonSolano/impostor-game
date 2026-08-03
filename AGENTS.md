<!-- BEGIN:nextjs-agent-rules -->
# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` before writing any code. Heed deprecation notices.
<!-- END:nextjs-agent-rules -->

# Jogo do Impostor

Web app mobile-first multiplayer de dedução social. Todos recebem a mesma palavra secreta, exceto um impostor. O grupo conversa **na vida real** e usa o app só para receber o card secreto, votar e ver o resultado.

**Idioma do projeto: PT-BR.** Specs, UI, mensagens de erro visíveis e commits em português com acentuação correta. Identificadores de código em inglês.

## Regras invioláveis

1. **O banco é a autoridade do jogo.** Toda transição de fase é uma função SQL `SECURITY DEFINER` com lock na linha da sala. O cliente lê estado e chama RPC — nunca decide regra, nunca recalcula resultado.
2. **A palavra secreta e a identidade do impostor nunca entram em `rooms`.** RLS filtra linhas, não colunas: qualquer coluna de `rooms` é visível para todo jogador inscrito no Realtime daquela sala. O segredo vive em `rounds` (sem grants) e é entregue individualmente por `player_cards` (RLS de linha própria).
3. **`votes` não tem `SELECT` para o cliente.** Progresso vira contador em `rooms.votes_cast`; apuração vira `rooms.last_vote_tally` só depois de resolvida.
4. **Nenhuma `SERVICE_ROLE_KEY` na aplicação.** Se apareceu uma, é porque uma regra de jogo escapou do banco.
5. **Sem `any`.** Tipos de banco vêm de `supabase gen types`, nunca escritos à mão.
6. **O app dá ritmo à dica escrita, não à conversa.** Existe ordem sorteada e prazo para *escrever a palavra* (turnos de dica). Não existe "sua vez de falar": enquanto o contador do próximo corre, a mesa comenta à vontade, e é justamente essa janela que faz o mesmo fluxo servir presencial e remoto. Nada no app pede que alguém fale, nem cronometra a discussão.
7. **A palavra secreta não é bloqueada como dica.** Recusar confirmaria ao impostor que ele acertou. O aviso na tela é preventivo — ver IMP-33.

## Comandos

```bash
npm run dev           # Next dev (Turbopack)
npm test              # vitest run
npm run verify        # gate completo: tsc + eslint + vitest + build
npx supabase start    # banco local (Docker)
npx supabase test db  # regras do jogo (pgTAP)
npx supabase db reset # reaplica migrations + seed
```

## Referência .specs/

Documentação estruturada do projeto. Consultar antes de tomar decisões.

### Projeto
- `.specs/project/PROJECT.md` — Visão, goals, stack, scope
- `.specs/project/ROADMAP.md` — Features planejadas e milestones
- `.specs/project/STATE.md` — Decisões tomadas, blockers e lições

### Codebase
- `.specs/codebase/STACK.md` — Stack tecnológica e dependências
- `.specs/codebase/ARCHITECTURE.md` — Padrões arquiteturais e fluxo de dados
- `.specs/codebase/CONVENTIONS.md` — Convenções de código e naming
- `.specs/codebase/STRUCTURE.md` — Estrutura de diretórios
- `.specs/codebase/TESTING.md` — Infraestrutura e padrões de teste
- `.specs/codebase/INTEGRATIONS.md` — Integrações externas
- `.specs/codebase/CONCERNS.md` — Tech debt, riscos e áreas frágeis

### Features
- `.specs/features/YYYY-MM-DD-[feature]/spec.md` — Requisitos e critérios de aceite
- `.specs/features/YYYY-MM-DD-[feature]/design.md` — Arquitetura e componentes
- `.specs/features/YYYY-MM-DD-[feature]/tasks.md` — Tasks atômicas de implementação
