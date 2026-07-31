# Jogo do Impostor

**Visão:** Web app mobile-first multiplayer de dedução social onde todos recebem a mesma palavra secreta, exceto um impostor que precisa blefar para não ser descoberto.

**Para:** Grupos de 3 a 12 pessoas fisicamente juntas (mesa de bar, sala de casa, sala de aula), cada um com seu celular.

**Resolve:** Jogos de dedução social exigem cartas físicas, um narrador dedicado ou confiança de que ninguém espiou. O app faz só o que o papel não faz bem: distribuição secreta, apuração de votos e desempate. A conversa e as rodadas de dicas acontecem inteiramente na vida real, sem o app pedir nada de ninguém.

## Objetivos

- Partida completa (criar sala → resultado) em menos de 5 minutos, sem tutorial.
- Do código da sala ao primeiro card revelado em menos de 30 segundos para um grupo de 5.
- No máximo 3 toques por jogador em uma partida inteira: revelar o card, votar, e (se for o caso) palpitar. O app fica fora do caminho da conversa.
- Zero vazamento da palavra secreta: nem para o impostor, nem para quem está sentado ao lado.
- Sincronia entre celulares abaixo de 1 segundo em cada transição de fase.

## Stack Tecnológica

**Core:**

- Framework: Next.js 16.2 (App Router, Turbopack)
- Linguagem: TypeScript 5 / React 19.2
- Banco de dados: PostgreSQL via Supabase

**Dependências-chave:**

- `@supabase/supabase-js` + `@supabase/ssr` — dados, Realtime e autenticação anônima
- `motion` (Framer Motion 12) — animações gamificadas
- Tailwind CSS 4 + shadcn/ui — estilização e componentes
- `vitest` + pgTAP (`supabase test db`) — testes de cliente e de regras do jogo

**Hospedagem:** Vercel (frontend) + Supabase gerenciado (banco e Realtime).

## Escopo

**v1 inclui:**

- Sala com código curto de 4 caracteres, entrada por nickname, host controlando o início.
- Máquina de estados completa: `LOBBY → WORD_REVEAL → DISCUSSION → VOTING → (DISCUSSION ↺ VOTING) → LAST_CHANCE → GAME_OVER`.
- 1 impostor por partida, sorteado aleatoriamente.
- Banco de 200 palavras em 10 categorias.
- Ciclo de votação repetível: empate ou "Pular Votação" vencedor devolve o jogo para mais uma rodada de discussão e reabre a votação.
- Twist "Última Chance do Impostor": 15 segundos para acertar a palavra entre 4 opções da mesma categoria e roubar a vitória.
- Modo Anti-Bisbilhoteiro (segurar 2s para revelar), carimbo de suspeito na votação, drumroll de 3s na revelação.
- Pontuação acumulada por jogador dentro da mesma sala e "Jogar Novamente com Nova Palavra".

**Explicitamente fora de escopo:**

- Contas persistentes, login social, perfil ou histórico entre sessões (só autenticação anônima).
- Chat de texto ou voz no app — as dicas são faladas presencialmente.
- Gerenciamento de ordem da mesa ou indicador de "sua vez de falar" — quem fala quando é decidido pelo grupo, ao vivo.
- Timer por dica ou pressão de tempo durante a discussão.
- Mais de um impostor, papéis extras ou palavra parecida para o impostor.
- Ranking global, matchmaking com desconhecidos ou salas públicas.
- Internacionalização — v1 é PT-BR apenas.
- App nativo ou instalação PWA offline.

## Restrições

- **Técnicas:** a palavra secreta e a identidade do impostor nunca podem trafegar para um cliente que não deveria vê-las. Isso descarta guardar o segredo em linha lida por todos via Realtime — RLS no Postgres é por linha, não por coluna.
- **Técnicas:** toda transição de fase precisa ser atômica no servidor. Vários celulares agem ao mesmo tempo (votos simultâneos, dois jogadores tocando "próximo"), então a autoridade fica em funções SQL `SECURITY DEFINER`, não no cliente.
- **Recursos:** projeto pessoal de estudos, um desenvolvedor, plano gratuito de Supabase e Vercel.
- **Produto:** mobile-first de verdade — a tela é usada em pé, com uma mão, em ambiente com barulho e luz ruim.
