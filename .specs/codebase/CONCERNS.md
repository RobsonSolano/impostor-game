# Concerns — riscos, dívidas e áreas frágeis

Ordenado por risco real de estragar uma partida.

## 🔴 Alto

### 1. Vazamento do segredo é falha silenciosa

Se alguém mover `word_id` ou `impostor_player_id` para uma tabela com `SELECT` liberado, ou adicionar essas colunas a `rooms`, o jogo continua **funcionando perfeitamente** — só que qualquer jogador consegue ler o segredo no DevTools. Nenhum teste de UI pega isso.

**Mitigação:** teste pgTAP que assume a identidade de um jogador comum e afirma que `SELECT` em `rounds` e `votes` falha, e que `player_cards` só retorna a própria linha. Esse teste é o guarda-corpo do projeto inteiro — se ele for removido, o risco volta.

### 2. Host que abandona a sala trava a partida

Só o host inicia o jogo, abre a votação e joga de novo. Se o host fecha o navegador em `DISCUSSION`, ninguém consegue abrir a votação e a sala fica morta. Não há host migration no v1.

**Mitigação atual:** nenhuma. Workaround do usuário é criar outra sala. Host migration está no Milestone 2.

### 3. `LAST_CHANCE` depende de alguém chamar a expiração

O prazo de 15s é uma coluna `guess_deadline` no banco, mas Postgres não dispara nada sozinho. Quem finaliza é `expire_last_chance()`, chamada pelos clientes quando o timer local zera. Se **todos** os celulares travarem/desligarem nesse exato momento, a sala fica presa em `LAST_CHANCE`.

**Mitigação:** a função é idempotente e chamável por qualquer jogador da sala, então basta um cliente vivo. Aceitável no v1. Solução definitiva seria um cron.

## 🟡 Médio

### 4. Sessão anônima é a única identidade

Perder o cookie (aba anônima fechada, storage limpo, trocar de navegador) = perder o `player_id`. O jogador volta como pessoa nova e o antigo fica órfão na sala, ainda contando para o total de votos esperados — o que pode **travar a apuração**, já que ela espera todos os jogadores vivos votarem.

**Mitigação parcial:** `leave_room` marca o jogador como não-vivo, mas depende de o jogador sair de propósito. Falta detecção de jogador fantasma (heartbeat / `last_seen_at`).

### 5. Salas nunca são limpas

Nada remove salas abandonadas. Códigos de 4 caracteres em alfabeto reduzido dão ~1,3 milhão de combinações, então colisão não é problema por muito tempo, mas a tabela cresce para sempre.

**Mitigação:** cron diário no Milestone 2.

### 6. Sem teste automatizado multi-dispositivo

A sincronia de Realtime — o coração da experiência — só é verificada abrindo dois navegadores na mão. Uma regressão em subscription ou em RLS de Realtime passaria por toda a suite.

## 🟢 Baixo

### 7. Enum de status é migration dolorosa

`ALTER TYPE ... ADD VALUE` não roda dentro de transação em versões mais antigas do Postgres e não permite remover valores. Adicionar fases (ex: `SIMILAR_WORD` no Milestone 3) exige cuidado.

### 8. Palavras hardcoded no seed

As 200 palavras vivem em uma migration. Adicionar palavra = nova migration. Aceitável, mas o Milestone 3 (baralhos customizados) vai querer isso em runtime.

### 9. Uma rota só para o jogo inteiro

`GameRoom.tsx` faz switch em `status`. Simples e evita perder a conexão de Realtime a cada fase, mas o componente cresce com cada fase nova. Vigiar se passar de ~7 casos.
