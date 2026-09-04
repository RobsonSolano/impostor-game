# STATE — Jogo do Impostor

Memória persistente do projeto. Decisões, blockers, lições e ideias diferidas.

## Decisões

### 2026-07-31 — Segredo do impostor vive em `player_cards`, não em `rooms`

RLS do Postgres filtra **linhas**, não colunas. Se `current_word` e `impostor_id` ficassem em `rooms`, qualquer jogador inscrito no Realtime dessa sala receberia o payload inteiro e leria o segredo no DevTools. Solução: `rounds` guarda o segredo e não tem nenhum grant para o cliente; `player_cards` guarda a visão individual (uma linha por jogador por rodada) com policy `player_id` pertencente ao `auth.uid()`. O impostor recebe `word_text = NULL`.

Consequência: o schema entregue difere do rascunho original do briefing, que tinha `rooms.current_word` e `rooms.impostor_id`.

### 2026-07-31 — Autoridade do jogo em funções SQL `SECURITY DEFINER`, não em Server Actions

Vários celulares agem ao mesmo tempo. Voto simultâneo, dois jogadores tocando "próximo" e o timer da última chance expirando junto com um palpite são corridas reais. Funções SQL com `SELECT ... FOR UPDATE` na linha da sala resolvem isso em uma transação, sem round-trip extra de serverless, e o `UPDATE` resultante já é o evento de Realtime que sincroniza a mesa.

Alternativa descartada: Route Handlers com service role key — mais latência, mais superfície de erro e ainda precisaria de lock no banco.

### 2026-07-31 — O app não gerencia ordem da mesa (correção de escopo do dev) — ⚠️ SUPERADA em 2026-08-03

O briefing original dizia "o app gerencia a ordem da mesa (exibe de quem é a vez de falar)". O dev corrigiu: ninguém precisa fazer nada no app durante as dicas. O grupo conversa livremente na vida real e o app só reaparece quando é hora de votar.

Consequência no schema: sem `players.seat_order`, sem `rooms.turn_index`, sem RPC `advance_turn`. As fases `ROUND_1`/`ROUND_2` colapsam em uma única fase `DISCUSSION` com contador `discussion_round` apenas informativo. Elimina a corrida mais chata do projeto (dois jogadores tocando "próximo" simultaneamente) e ~1/3 da superfície de RPC.

**Superada pelos turnos de dicas (2026-08-03):** o app passou a sortear ordem e a ter prazo por turno, e `rooms.clue_turn_index` existe. O que sobreviveu da decisão é o essencial: nada no app pede que alguém *fale*. Ver a decisão de 2026-08-03.

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

### 2026-08-03 — Turnos de dicas: um fluxo só, presencial e remoto

A regra 6 dizia que o app não gerencia ordem da mesa. Passou a gerenciar a ordem da **dica escrita** — e a pergunta era se isso exigia dois modos (presencial x remoto). Não exigiu: a janela até o próximo turno é o tempo de conversa na mesa e o tempo de digitar no remoto, então o mesmo fluxo serve os dois. Economizou uma coluna em `rooms`, dois caminhos na máquina de estados e o dobro de casos de teste.

O status continua se chamando `DISCUSSION`: o papel da fase é o mesmo (entre revelar o card e votar) e a conversa continua acontecendo, agora nos intervalos. Renomear o enum só geraria churn.

### 2026-08-03 — Palavrão retorna, não levanta exceção

`submit_clue` devolve `{ ok: false, reason: 'PROFANITY', strikes }` em vez de `raise`. Exceção em plpgsql desfaz a transação inteira — o incremento do contador de faltas voltaria a zero junto, e a terceira falta nunca chegaria. Erros que não gravam nada (fase errada, não é sua vez, formato inválido) continuam levantando exceção.

### 2026-08-04 — Rodízio do impostor: peso, não exclusão

Jogo real com a família expôs o problema: sorteio uniforme deu 3 partidas seguidas com o mesmo impostor, duas vezes. O dev propôs excluir os dois últimos impostores do sorteio.

Simulei as duas antes de escolher. Exclusão distribui perfeitamente **e entrega o jogo**: em mesa de 4 sobram 2 candidatos, em mesa de 3 sobra 1. Como o caso de uso é exatamente mesa pequena, a regra se auto-sabota.

Adotado peso = (rodadas desde a última vez)², sem excluir ninguém: 3,4% de repetição contra 25%, e a mesa continua com todos os jogadores como suspeitos possíveis. Bônus de design: repetir vira disfarce, porque ninguém suspeita de quem acabou de ser.

Lição geral: quando a regra "mais justa" reduz o conjunto de suspeitos, ela está pagando justiça com informação — e num jogo de dedução, informação é o preço mais caro que existe.

## Blockers

Nenhum aberto.

### ✅ 2026-09-04 — Banco reprovisionado (o projeto anterior deixou de existir)

O projeto Supabase de teste (`wpmkvthjthwgbfandeif`) **deixou de existir** — o host passou a devolver `NXDOMAIN`, provável pausa/remoção por inatividade no plano gratuito. Sintoma no cliente: `signInAnonymously()` falha com erro de rede (`UnknownHostException`), que na tela parece queda de conexão e não banco inexistente.

Projeto novo: **`bbtsqjxcmlymwxcqvrmo`** (nome "Impostor", região us-west-2).

Feito em 2026-09-04:

- `supabase link` + `supabase db push` — as 6 migrations aplicadas do zero, incluindo a semeadura das palavras (que é migration, então vai junto).
- `supabase config push` — é isto que habilita *Anonymous sign-ins* sem passar pelo dashboard, porque o flag está versionado em `config.toml` (`enable_anonymous_sign_ins = true`). Confirmado com um `POST /auth/v1/signup` real: volta JWT com `role: authenticated` e `amr: [{method: "anonymous"}]`.
- `.env.local` e as variáveis da Vercel (`NEXT_PUBLIC_SUPABASE_URL` e `NEXT_PUBLIC_SUPABASE_ANON_KEY`, nos três ambientes) apontando para o projeto novo.
- `seed.sql` **não** subiu, e isso é o comportamento correto: ele fabrica usuários em `auth.users` para teste local e não pode existir em produção. O `db push` só envia `migrations/`.

Verificado contra o banco novo, por RPC real (três sessões anônimas): `create_room` → `join_room` ×2 → `start_game` funcionam; durante a partida `rooms.revealed_word` e `rooms.revealed_impostor_id` continuam `null` (o segredo não está lá — ver a primeira decisão deste documento); e cada jogador lê **uma** linha em `player_cards`, a própria. `rounds` e `votes` seguem sem grant para o cliente.

**Lição:** projeto Supabase gratuito parado é apagado. Um `dig` no host do `.env` é o primeiro diagnóstico quando o login anônimo começa a falhar por "rede".

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

### Realtime sozinho congela o jogo — evento perdido não tem volta

**Sintoma:** partida travada (sala `TQAK`, 06/08). Os três confirmaram o card, ninguém foi chamado para escrever a palavra, e a mesa teve que encerrar a sala e abrir outra.

**O banco estava perfeito.** Sala em DISCUSSION, ordem sorteada (Papai/Heitorzinho/Théozinho nos índices 0/1/2), prazo gravado. O que denunciou foi `timed_out = false` em todos com `clue_turn_index` parado em 0: o prazo venceu e **ninguém chamou `expire_clue_turn`** — o que só acontece se nenhum cliente estava na tela de turnos.

**Root cause:** os celulares não receberam o evento de Realtime da transição WORD_REVEAL → DISCUSSION e ficaram presos na tela do card. Papai entrou 21:43, Heitorzinho 21:45, e a partida só começou 21:59 — quinze minutos de tela bloqueada e aba em segundo plano, tempo de sobra para o WebSocket morrer.

**Por que era grave:** o app dependia SÓ de Realtime depois da carga inicial. Evento perdido = tela congelada sem saída, porque ninguém pensa em recarregar a página no meio de um jogo. E o pior caso é silencioso: socket zumbi não reporta erro, então nem o aviso de "Reconectando" aparecia necessariamente.

**Correção:** `useKeepFresh` — ressincroniza quando a aba volta a ficar visível (o caso exato), quando a rede volta, e por sondagem de 8s enquanto visível (o socket zumbi). Só sonda com a aba visível, para não gastar bateria atualizando tela que ninguém olha.

**Verificação:** com o WebSocket derrubado no Playwright, o navegador ainda acompanha o lobby enchendo e alcança os turnos de dica.

**Lição geral:** Realtime é otimização de latência, não fonte de verdade. Toda tela que depende de push precisa de um caminho de recuperação — a pergunta certa é "e se este evento não chegar?", não "o evento vai chegar?".

### Regra certa + silêncio = parece bug

**Relato:** "você quebrou o jogo — abrimos votação, votamos, confirmamos e voltou pra nova rodada".

**O banco estava certo** (sala `XMQQ`): ciclo 1 deu mamãe 2 × Heitorzinho 2, ciclo 2 deu exatamente o mesmo. Empate no topo não elimina ninguém — é a regra IMP-13, e ela existe por um bom motivo: eliminar no cara-ou-coroa arruinaria um jogo de dedução.

**O defeito era de comunicação.** O aviso "Houve empate" ficava no FIM do conteúdo, depois do quadro de dicas — fora da tela no celular. O título só dizia "Rodada 4". Do ponto de vista da mesa: votaram, confirmaram, e a tela voltou ao começo sem explicação.

**Correção:** o resultado sobe para o topo, com os NOMES e a contagem ("mamãe 2 · Heitorzinho 2"), e o subtítulo também explica para quem não rola a tela.

**Lição geral:** num app multi-jogador, uma regra correta que não se explica é indistinguível de um bug — e o usuário não tem como saber a diferença. Toda transição que devolve o jogador ao estado anterior precisa dizer POR QUÊ, no lugar onde ele já está olhando.

## Ideias diferidas

- Cron de limpeza de salas abandonadas → Milestone 2.
- Host migration quando o host abandona → Milestone 2, hoje a sala trava.
- Modo "palavra parecida" para o impostor → Milestone 3.

## Preferences

- Idioma do projeto: PT-BR (specs, commits, UI).
- Tarefas leves (validação de state, handoff de sessão, updates de STATE.md) funcionam bem em modelos mais rápidos/baratos.
