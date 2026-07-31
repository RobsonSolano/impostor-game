# STATE — Jogo do Impostor

Memória persistente do projeto. Decisões, blockers, lições e ideias diferidas.

## Decisões

### 2026-07-31 — Segredo do impostor vive em `player_cards`, não em `rooms`

RLS do Postgres filtra **linhas**, não colunas. Se `current_word` e `impostor_id` ficassem em `rooms`, qualquer jogador inscrito no Realtime dessa sala receberia o payload inteiro e leria o segredo no DevTools. Solução: `rounds` guarda o segredo e não tem nenhum grant para o cliente; `player_cards` guarda a visão individual (uma linha por jogador por rodada) com policy `player_id` pertencente ao `auth.uid()`. O impostor recebe `word_text = NULL`.

Consequência: o schema entregue difere do rascunho original do briefing, que tinha `rooms.current_word` e `rooms.impostor_id`.

### 2026-07-31 — Autoridade do jogo em funções SQL `SECURITY DEFINER`, não em Server Actions

Vários celulares agem ao mesmo tempo. Voto simultâneo, dois jogadores tocando "próximo" e o timer da última chance expirando junto com um palpite são corridas reais. Funções SQL com `SELECT ... FOR UPDATE` na linha da sala resolvem isso em uma transação, sem round-trip extra de serverless, e o `UPDATE` resultante já é o evento de Realtime que sincroniza a mesa.

Alternativa descartada: Route Handlers com service role key — mais latência, mais superfície de erro e ainda precisaria de lock no banco.

### 2026-07-31 — O app não gerencia ordem da mesa (correção de escopo do dev)

O briefing original dizia "o app gerencia a ordem da mesa (exibe de quem é a vez de falar)". O dev corrigiu: ninguém precisa fazer nada no app durante as dicas. O grupo conversa livremente na vida real e o app só reaparece quando é hora de votar.

Consequência no schema: sem `players.seat_order`, sem `rooms.turn_index`, sem RPC `advance_turn`. As fases `ROUND_1`/`ROUND_2` colapsam em uma única fase `DISCUSSION` com contador `discussion_round` apenas informativo. Elimina a corrida mais chata do projeto (dois jogadores tocando "próximo" simultaneamente) e ~1/3 da superfície de RPC.

### 2026-07-31 — Host abre a votação

Alguém precisa dizer ao app que a conversa terminou. Escolhido: só o host tem o botão "Abrir votação"; os outros veem o estado de espera. Motivo: consistente com o host já ser quem inicia a partida, e evita que um jogador (ou uma criança) corte a discussão dos outros. Trocar para "qualquer jogador pode abrir" é uma linha na policy da RPC se o uso real pedir.

### 2026-07-31 — `rooms.status` usa a máquina de estados fina

O briefing listava `status` como `(LOBBY, IN_GAME, VOTING, FINISHED)` mas descrevia fases de jogo distintas. `IN_GAME` não diz à UI se deve mostrar o card, a discussão ou o timer do palpite. Adotado o enum fino: `LOBBY, WORD_REVEAL, DISCUSSION, VOTING, LAST_CHANCE, GAME_OVER`.

### 2026-07-31 — Entrada na sala via RPC, não via `SELECT` por código

Para achar a sala pelo código sem RPC, a policy de `SELECT` em `rooms` teria que liberar todas as salas para qualquer usuário autenticado. Com `join_room(code, name)` como `SECURITY DEFINER`, a policy fica restrita a "sou jogador desta sala".

### 2026-07-31 — Sala encerrada é estado `CLOSED`, não `DELETE`

O host saindo encerra a sala para todos (IMP-25). A implementação óbvia — `DELETE FROM rooms` — se auto-sabota: os `players` caem por cascade na mesma transação, e sem eles a policy `is_room_member` falha, então o Realtime não consegue autorizar a entrega do evento aos outros celulares. Eles ficariam presos numa sala que não existe mais. Com `status = 'CLOSED'` o UPDATE chega a todos, e a remoção física fica para a limpeza periódica.

### 2026-07-31 — Três layouts, um DOM (mobile-first ≠ mobile-only)

Ordem no DOM = ordem de leitura no celular (header → palco → mesa → ação). Telas maiores remontam com `col-start`/`row-start` em grade, sem duplicar nós — duplicar significaria dois componentes com estado próprio, e o card secreto perderia o hold na troca de layout.

- **Celular:** coluna única, ação colada na base (zona do polegar).
- **Tablet (`md`):** coluna larga empilhada; a mesa vira linha com wrap, aproveitando a largura em mais jogadores por linha em vez de uma lateral solta.
- **Desktop (`lg`):** duas colunas, mesa na lateral, bloco centralizado na vertical.

### 2026-07-31 — Palavras: uma palavra, para criança de 9 anos

A lista original tinha 42 frases de 200 ("Entrevista de Emprego") e termos abstratos. Frase é ruim duas vezes: já é a própria dica e estoura o card. Regra agora é garantida por `check` em `words` (sem espaço, 3–15 caracteres), não só por convenção — a lista vai crescer.

## Blockers

### 🔴 Credenciais do Supabase pendentes

Dev está criando o projeto Supabase (confirmado em 2026-07-31). Migrations e seed ficam versionados em `supabase/migrations/`; validação roda contra o Supabase local (Docker). Ao provisionar o remoto, preencher `.env.local` e rodar `npx supabase db push`.

**Ação manual obrigatória no dashboard:** habilitar *Anonymous sign-ins* em Authentication → Sign In / Providers. Sem isso, `signInAnonymously()` retorna 422 e ninguém entra em sala.

## Lições

### `char(4)` quebra o Realtime — `rooms.code` tem que ser `text`

**Sintoma:** todo celular passava a mostrar 1 letra no lugar do código de 4 (`"F"` em vez de `"F2VQ"`).

**Root cause:** o decodificador WAL→JSON do Realtime trata `bpchar` como char de **1 caractere**. O payload vinha `"code": "F"` com `{"name":"code","type":"bpchar"}`.

**Por que passou despercebido:** a leitura REST vinha correta, então criar a sala parecia funcionar. O bug só aparecia no primeiro `UPDATE` da sala — que é o próprio `create_room` gravando `host_player_id` depois de inserir o jogador. Ou seja: sempre, mas 1 segundo depois de a tela carregar certa.

**Guarda:** `col_type_is('public','rooms','code','text')` em `01_room_lifecycle.test.sql`. `gen_room_code()` também devolve `text` — o conceito de `bpchar` não existe mais no código.

### Sessão anônima órfã não se resolve tentando de novo

**Sintoma:** erro de foreign key em `players_user_id_fkey` ao criar sala, e insistir não ajudava.

**Root cause:** `@supabase/ssr` guarda a sessão em **cookie**, não em localStorage. O JWT continua com assinatura válida e prazo aberto mesmo depois do usuário deixar de existir (banco recriado, usuários podados). `getSession()` só lê o cookie e aceita o token; `auth.uid()` devolve um id inexistente.

**Correção:** `ensureAnonSession()` confere com `getUser()` (que consulta o servidor) na primeira vez por carga de página, descarta a sessão inválida e cria outra. O app se auto-cura em vez de exigir que o jogador limpe cookies.

### Validar UI em dev server com HMR quebrado dá falso negativo

O WebSocket de HMR do Next falhava em loop no ambiente de validação e remontava a página, limpando inputs controlados no meio da interação — parecia bug de estado do React. Validação de UI passou a rodar contra `next build && next start`, que também é mais fiel ao que roda no celular.

## Ideias diferidas

- Cron de limpeza de salas abandonadas → Milestone 2.
- Host migration quando o host abandona → Milestone 2, hoje a sala trava.
- Modo "palavra parecida" para o impostor → Milestone 3.

## Preferences

- Idioma do projeto: PT-BR (specs, commits, UI).
- Tarefas leves (validação de state, handoff de sessão, updates de STATE.md) funcionam bem em modelos mais rápidos/baratos.
