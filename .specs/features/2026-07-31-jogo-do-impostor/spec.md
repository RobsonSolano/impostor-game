# Spec — Jogo do Impostor (v1 completo)

**Escopo:** Large
**Data:** 2026-07-31

## Contexto

Partida completa jogável em múltiplos celulares. O app faz distribuição secreta, apuração e desempate. **A conversa e as rodadas de dicas acontecem inteiramente na vida real** — o app não pede nada de ninguém entre revelar o card e votar.

Cenário de referência dado pelo dev: 4 pessoas na mesma casa (ele, esposa, 2 filhos). Ele cria a sala, os outros entram pelo código. 3 veem a palavra, 1 vê "VOCÊ É O IMPOSTOR". Conversam ao vivo. Alguém decide que é hora de votar. Votam. O app diz se o impostor venceu, se foi descoberto, ou se o jogo continua.

## Glossário

| Termo | Significado |
|---|---|
| **Impostor** | O único jogador que não recebe a palavra. Ganha se não for descoberto |
| **Verdadeiro** | Qualquer jogador que não é o impostor |
| **Host** | Quem criou a sala. Único que inicia a partida, abre a votação e joga de novo |
| **Card** | A visão individual e secreta de um jogador na rodada: a palavra, ou o aviso de impostor |
| **Ciclo de votação** | Uma abertura de votação. Empate ou "pular" vencedor encerra o ciclo sem eliminar ninguém e abre o próximo |
| **Rodada de discussão** | Intervalo entre o card e a votação. Contada só para exibição (`Rodada 1`, `Rodada 2`...) |
| **Maioria simples** | Mais votos que qualquer outra opção, sem empate no topo. Não exige metade + 1 |
| **Última Chance** | 5 segundos que o impostor descoberto tem para acertar a palavra entre 4 opções e roubar a vitória |

## Requisitos

### Sala e jogadores

**IMP-01 — Criar sala**
QUANDO um visitante informa um nickname e toca em criar sala
ENTÃO o sistema cria uma sala com código de 4 caracteres alfanuméricos únicos, registra o criador como host e o leva para o lobby.

- O código usa alfabeto sem caracteres ambíguos: `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (sem `I`, `O`, `0`, `1`).
- Colisão de código é resolvida com nova tentativa, transparente ao usuário.
- O visitante recebe uma sessão anônima antes da criação.

**IMP-02 — Entrar em sala**
QUANDO um visitante informa nickname e um código de sala existente em LOBBY
ENTÃO ele é adicionado à sala com uma cor de avatar e aparece no lobby de todos os outros jogadores em menos de 1 segundo.

- Código é normalizado (maiúsculas, sem espaços) antes da busca.
- Código inexistente → erro visível "Sala não encontrada".
- Sala com partida em andamento (status ≠ LOBBY) → erro "Essa partida já começou".
- Sala cheia (12 jogadores) → erro "Sala cheia".
- Nickname já usado na mesma sala → erro "Esse nome já está em uso na sala".
- O mesmo usuário que já está na sala volta ao seu próprio `player_id` em vez de duplicar.

**IMP-03 — Mínimo de jogadores**
QUANDO o host tenta iniciar a partida com menos de 3 jogadores
ENTÃO o sistema recusa e o botão de iniciar permanece desabilitado com a contagem que falta.

**IMP-04 — Só o host controla**
QUANDO um jogador que não é o host tenta iniciar a partida, abrir a votação ou jogar de novo
ENTÃO o sistema recusa a ação.

### Distribuição secreta

**IMP-05 — Sorteio de impostor e palavra**
QUANDO o host inicia a partida com 3 ou mais jogadores
ENTÃO o sistema sorteia exatamente 1 jogador ativo como impostor, sorteia 1 palavra entre as 200 disponíveis, cria o card individual de cada jogador e move a sala para WORD_REVEAL.

- **O impostor é sorteado ANTES da palavra.** Uma rodada sem impostor não é jogo, então essa é a primeira coisa a existir e a primeira a falhar se algo estiver errado.
- Nunca existe rodada com zero impostores nem com mais de um. Isso é invariante, não tendência: verificado em 30 sorteios consecutivos.
- O impostor sorteado é sempre um jogador ativo da própria sala.
- Todo jogador verdadeiro recebe exatamente a mesma palavra.
- O impostor recebe card com `is_impostor = true` e nenhuma palavra.

**IMP-06 — Segredo isolado por jogador**
QUANDO um jogador consulta os dados da partida por qualquer caminho disponível ao cliente (leitura de tabela ou Realtime)
ENTÃO ele obtém apenas o próprio card, e não consegue ler a palavra da rodada, a identidade do impostor, nem o card de outro jogador.

- Leitura direta de `rounds` falha para o cliente.
- Leitura direta de `votes` falha para o cliente.
- `player_cards` retorna somente linhas do próprio usuário.
- A palavra e o impostor só aparecem em `rooms` depois de GAME_OVER.

**IMP-07 — Anti-bisbilhoteiro (hold-to-reveal)**
QUANDO um jogador está na tela do card
ENTÃO o conteúdo só aparece enquanto ele mantém o dedo pressionado, com barra de progresso de 2 segundos até revelar, e volta a ficar oculto ao soltar.

**IMP-08 — Todos prontos abre a discussão**
QUANDO o último jogador confirma que viu o card
ENTÃO a sala move para DISCUSSION com `discussion_round = 1` para todos.

### Discussão e votação

**IMP-09 — Discussão sem interação**
QUANDO a sala está em DISCUSSION
ENTÃO o app não exige ação de nenhum jogador comum; exibe a rodada atual, quem está na mesa, e só o host vê o botão "Abrir votação".

**IMP-10 — Abrir votação**
QUANDO o host abre a votação
ENTÃO a sala move para VOTING, os votos do ciclo anterior são descartados da contagem e todos os jogadores vivos veem a lista de suspeitos.

**IMP-11 — Registrar voto**
QUANDO um jogador vivo escolhe um suspeito ou escolhe "Pular Votação"
ENTÃO seu voto é registrado uma única vez no ciclo atual, o contador de votos visível a todos incrementa, e ele não consegue mais alterar o voto naquele ciclo.

- Voto em si mesmo é recusado.
- Voto em jogador que não está na sala é recusado.
- Segundo voto no mesmo ciclo é recusado.
- Ninguém vê em quem os outros votaram antes da apuração.

**IMP-12 — Apuração automática**
QUANDO o último jogador vivo registra seu voto
ENTÃO o sistema apura imediatamente, sem ação de ninguém.

**IMP-13 — Empate ou "pular" vencedor devolve para discussão**
QUANDO a apuração termina com "Pular Votação" como opção mais votada, ou com empate no topo entre jogadores
ENTÃO ninguém é eliminado, `discussion_round` incrementa, e a sala volta para DISCUSSION aguardando o host abrir a votação novamente.

- Esse ciclo repete indefinidamente até alguém receber maioria simples.

**IMP-14 — Inocente eliminado: impostor vence**
QUANDO a apuração elimina por maioria simples um jogador que não é o impostor
ENTÃO a sala move para GAME_OVER com resultado `IMPOSTOR_WIN`, revelando quem era o impostor e qual era a palavra.

**IMP-15 — Impostor eliminado abre a Última Chance**
QUANDO a apuração elimina por maioria simples o impostor
ENTÃO a sala move para LAST_CHANCE com prazo de 5 segundos e 4 opções de palavra — a correta mais 3 da mesma categoria — visíveis somente ao impostor.

### Última Chance e resultado

**IMP-16 — Impostor acerta e rouba a vitória**
QUANDO o impostor escolhe a palavra correta dentro do prazo
ENTÃO a sala move para GAME_OVER com resultado `IMPOSTOR_STEAL`.

**IMP-17 — Impostor erra ou perde o prazo**
QUANDO o impostor escolhe uma palavra errada, ou o prazo de 5 segundos expira sem escolha
ENTÃO a sala move para GAME_OVER com resultado `TRUTHERS_WIN`.

- A expiração é finalizável por qualquer jogador da sala e é idempotente: a primeira chamada decide, as seguintes não alteram o resultado.
- Palpite enviado após o prazo é recusado.

**IMP-18 — Tela final**
QUANDO a sala está em GAME_OVER
ENTÃO todos veem quem era o impostor, qual era a palavra, o resultado da partida, a apuração dos votos do último ciclo e o placar acumulado da sala.

- Pontuação: verdadeiros vencem → +1 para cada verdadeiro. `IMPOSTOR_WIN` → +2 para o impostor. `IMPOSTOR_STEAL` → +3 para o impostor.

**IMP-19 — Novo jogo**
QUANDO o host toca em "Novo jogo"
ENTÃO uma nova rodada começa na mesma sala com nova palavra, novo sorteio de impostor, `discussion_round` de volta a 1, placar preservado, e todos vão para WORD_REVEAL.

- O botão aparece em **qualquer** desfecho: vitória dos verdadeiros, vitória do impostor ou roubo na Última Chance.
- Ninguém sai da sala nem perde pontos. Muda a palavra e quem é o impostor.
- O impostor é sorteado de novo a cada partida — não fica no mesmo jogador.
- A palavra da nova rodada não repete nenhuma palavra já usada na mesma sala, enquanto houver palavras disponíveis.

### Sincronia e resiliência

**IMP-20 — Sincronia de fase**
QUANDO o estado da sala muda por qualquer ação
ENTÃO todos os celulares conectados refletem a nova fase em menos de 1 segundo, sem recarregar a página.

**IMP-21 — Transições ilegais recusadas**
QUANDO uma ação é chamada em uma fase que não a permite (votar fora de VOTING, palpitar fora de LAST_CHANCE, iniciar partida fora de LOBBY)
ENTÃO o sistema recusa com erro identificável e o estado da sala não muda.

**IMP-22 — Ações simultâneas não corrompem o estado**
QUANDO dois jogadores agem no mesmo instante (dois votos, ou palpite chegando junto com a expiração do prazo)
ENTÃO o estado final é consistente: um único resultado é gravado e a pontuação é aplicada uma única vez.

### Saída da sala

**IMP-25 — Host encerra a sala para todos**
QUANDO o host toca em sair/encerrar, em qualquer fase
ENTÃO a sala passa para `CLOSED`, todos os jogadores são avisados em menos de 1 segundo e voltam para a tela inicial de criar/entrar.

- Confirmação em dois toques antes de encerrar — é destrutivo para as outras pessoas.
- Sala `CLOSED` é inerte: ninguém entra, nenhuma ação de jogo funciona nela.
- Encerrar duas vezes não é erro.
- Encerrar depois de uma partida concluída não apaga o resultado já revelado.
- Os jogadores continuam existindo no banco — é o que permite o Realtime autorizar o aviso a cada um. A remoção física é tarefa de limpeza posterior.

**IMP-26 — Jogador comum apenas sai**
QUANDO um jogador que não é o host toca em sair
ENTÃO ele deixa a sala e os demais continuam a partida.

- No LOBBY, ele é removido de vez — não fica ocupando vaga nem aparece apagado no roster.
- Em partida em andamento, ele é marcado como fora, e a apuração passa a esperar apenas os votos de quem ficou.

**IMP-27 — Impostor abandonando encerra a rodada**
QUANDO o impostor sai no meio de uma partida em andamento
ENTÃO a partida termina imediatamente com vitória dos verdadeiros.

- Sem essa regra a mesa continuaria caçando alguém ausente: qualquer voto acabaria eliminando um inocente e dando a vitória a um impostor que não está mais jogando.

## Diferenciais gamificados

**IMP-23 — Carimbo de suspeito**
QUANDO um jogador seleciona um suspeito na votação
ENTÃO um carimbo animado marca o card do suspeito antes da confirmação.

**IMP-24 — Drumroll**
QUANDO a apuração é concluída
ENTÃO uma contagem regressiva visível de 5 até 0 antecede a revelação do resultado.

- É só suspense: o resultado e o placar já estão gravados no banco antes desta tela aparecer.

### Banco de palavras

**IMP-28 — Uma palavra, fácil para criança de 9 anos**
QUANDO uma palavra é adicionada ao banco
ENTÃO ela precisa ser uma palavra única (sem espaço), com 3 a 15 caracteres, e concreta o bastante para uma criança de 9 anos dar dica sobre ela.

- Frase é recusada pelo banco, não só desencorajada: "Entrevista de Emprego" já é a própria dica e estoura o card.
- Quem não conhece a palavra não consegue dar dica nem desconfiar de ninguém, e acaba parecendo o impostor sem ser.
- 200 palavras, 20 por categoria. Nenhuma categoria abaixo de 4 palavras, senão os 3 distratores da Última Chance saem óbvios.

### Layout

**IMP-29 — Mobile-first, não mobile-only**
QUANDO o app é aberto em celular, tablet ou desktop
ENTÃO cada um recebe um layout pensado para si, sem esticar o do outro.

- **Celular:** coluna única de largura cheia, ação primária colada na base (zona do polegar), alvos de toque ≥ 48px, respeito à barra de gestos e ao notch.
- **Tablet retrato:** a mesma coluna, centralizada e delimitada por borda.
- **Desktop:** duas colunas — palco à esquerda com a ação logo abaixo do conteúdo, e contexto secundário (mesa, placar, código) em coluna lateral que acompanha a rolagem. Não existe zona do polegar no mouse, então botão preso na base fica longe do que se está lendo.
- Em nenhuma largura o corpo da página rola na horizontal.

## Não incluído

- Ordem da mesa, indicador de "sua vez de falar", timer de discussão.
- Host migration, reconexão com detecção de jogador fantasma, limpeza de salas antigas.
- Mais de um impostor, palavra parecida, categorias selecionáveis, baralho customizado.
- Chat, contas persistentes, ranking global, i18n.

## Rastreabilidade

Cada requisito acima tem teste nomeado com seu ID. Regras de jogo → pgTAP em `supabase/tests/`. Interação de cliente (IMP-07) → vitest.

| Requisito | Onde é testado |
|---|---|
| IMP-01, IMP-02 | `supabase/tests/01_room_lifecycle.test.sql` |
| IMP-03, IMP-04, IMP-05 | `supabase/tests/02_start_game.test.sql` |
| IMP-06 | `supabase/tests/03_secret_isolation.test.sql` |
| IMP-08, IMP-09, IMP-10 | `supabase/tests/04_discussion.test.sql` |
| IMP-11, IMP-12, IMP-13 | `supabase/tests/05_voting.test.sql` |
| IMP-14, IMP-15 | `supabase/tests/06_verdict.test.sql` |
| IMP-16, IMP-17, IMP-18, IMP-19 | `supabase/tests/07_last_chance.test.sql` |
| IMP-21, IMP-22 | `supabase/tests/08_guards.test.sql` |
| IMP-25, IMP-26 | `supabase/tests/09_leave_and_close.test.sql` |
| IMP-05 (invariante), IMP-19, IMP-27 | `supabase/tests/10_impostor_invariant.test.sql` |
| IMP-28 | `supabase/tests/11_words.test.sql` |
| IMP-29 | Verificação em navegador nas 3 larguras (390, 820, 1440) |
| IMP-07 | `src/components/shared/HoldToReveal.test.tsx` |
| IMP-20, IMP-23, IMP-24 | Verificação manual multi-dispositivo |
