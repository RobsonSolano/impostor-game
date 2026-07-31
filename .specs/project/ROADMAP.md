# Roadmap — Jogo do Impostor

## Milestone 1 — Partida jogável (v1) — EM ANDAMENTO

Objetivo: um grupo real termina uma partida inteira em dois ou mais celulares, sem intervenção manual no banco.

| # | Feature | Status | Spec |
|---|---------|--------|------|
| 1 | Fundação: schema, RLS, seed de 200 palavras | 🚧 | `2026-07-31-jogo-do-impostor` |
| 2 | Máquina de estados como RPCs autoritativas | 🚧 | `2026-07-31-jogo-do-impostor` |
| 3 | Sala: criar, entrar, roster realtime | 🚧 | `2026-07-31-jogo-do-impostor` |
| 4 | Distribuição secreta + hold-to-reveal | 🚧 | `2026-07-31-jogo-do-impostor` |
| 5 | Fase de discussão + host abrindo a votação | 🚧 | `2026-07-31-jogo-do-impostor` |
| 6 | Votação, ciclo de rodada extra e apuração | 🚧 | `2026-07-31-jogo-do-impostor` |
| 7 | Última Chance do Impostor + resultado | 🚧 | `2026-07-31-jogo-do-impostor` |

## Milestone 2 — Polimento e retenção

| # | Feature | Nota |
|---|---------|------|
| 8 | Reconexão resiliente | Jogador que fecha o navegador no meio da partida volta no mesmo `player_id` (hoje depende da sessão anônima sobreviver) |
| 9 | Host migration | Se o host sai, passar o comando para o próximo jogador em vez de travar a sala |
| 10 | Timer opcional de discussão | Pressão de tempo configurável no lobby (ex: 3 min de conversa) que abre a votação sozinho. Hoje o host decide na mão — de propósito |
| 11 | Placar da sala entre partidas | Tela de ranking acumulado ao fim de cada partida, não só `players.score` cru |
| 12 | Limpeza de salas abandonadas | Cron diário removendo salas paradas há mais de 24h |

## Milestone 3 — Variações de jogo

| # | Feature | Nota |
|---|---------|------|
| 13 | 2 impostores em grupos de 7+ | Muda a regra de vitória e a apuração |
| 14 | Modo "palavra parecida" | Impostor recebe uma palavra próxima em vez de nada — blefe fica mais sutil |
| 15 | Categorias selecionáveis no lobby | Host escolhe de quais das 10 categorias sortear |
| 16 | Palavras customizadas por sala | Grupo cadastra o próprio baralho |

## Fora do roadmap (decisões registradas)

- Contas persistentes e login social — o jogo é presencial e efêmero por design.
- Chat no app — competiria com a conversa da mesa, que é o núcleo da diversão.
- Salas públicas com desconhecidos — dedução social depende de conhecer quem está mentindo.
