# Spec — Turnos de dicas escritas

**Escopo:** Medium
**Data:** 2026-08-03
**Depende de:** `2026-07-31-jogo-do-impostor`

## Contexto

Hoje a fase DISCUSSION não pede nada de ninguém: o grupo conversa ao vivo e o host abre a votação quando quiser. Isso só funciona com todos na mesma mesa.

Esta feature dá ritmo à fase: o sistema sorteia a ordem, e cada jogador escreve **uma palavra** relacionada à palavra secreta, com prazo. A dica fica visível para todos.

**O mesmo fluxo serve presencial e remoto** — foi o que dispensou um seletor de modo. Na mesa, a janela até o próximo turno é justamente o tempo de conversar sobre a dica que acabou de aparecer. No remoto (ou numa call de Discord), a mesma janela é só o tempo de digitar.

Isso **reescreve a regra 6 do `AGENTS.md`**: o app passa a dar ritmo à dica escrita. O que continua valendo é que ele não gerencia a *conversa* — ninguém precisa pedir a palavra, e não existe timer de discussão.

## Requisitos

**IMP-30 — Ordem de fala sorteada**
QUANDO a fase de dicas começa
ENTÃO o sistema sorteia uma ordem entre os jogadores ativos e a exibe para todos, com a posição de cada um.

- A ordem é pública: faz parte do jogo saber quem fala depois de quem.
- Cada rodada de dicas sorteia uma ordem nova.
- Um jogador aparece exatamente uma vez na ordem.

**IMP-31 — Turno de dica com prazo**
QUANDO chega o turno de um jogador
ENTÃO só ele vê o campo de escrever, com contagem regressiva visível, e os outros veem de quem é a vez.

- O primeiro jogador da ordem tem **15 segundos**: não tem dica anterior para ler.
- Os seguintes têm **20 segundos**, que na mesa é também o tempo de a mesa comentar a dica anterior.
- Quem manda no prazo é `rooms.turn_deadline`, no banco. O contador na tela só desenha.

**IMP-32 — Uma palavra, e só uma**
QUANDO o jogador tenta enviar a dica
ENTÃO o sistema aceita apenas um único termo: letras (com acento), hífen interno permitido, 2 a 20 caracteres.

- Aceita: `tromba`, `guarda-chuva`, `Pão`, `ré`, `bem-te-vi`.
- Recusa: espaço, número, símbolo, hífen solto nas pontas, 1 caractere.
- A validação vale no cliente (feedback imediato) **e** no banco (autoridade).
- Não valida se a palavra existe. `xpto` passa — decisão consciente: um dicionário embutido recusaria "Pikachu" e "nerf" no meio de um turno de 15 segundos, e criança de 9 anos usa exatamente esse vocabulário.

**IMP-33 — Palavra secreta NÃO é bloqueada**
QUANDO um jogador escreve exatamente a palavra secreta como dica
ENTÃO o sistema aceita, e apenas exibe o aviso preventivo antes do envio.

- Bloquear seria um vazamento: o impostor não sabe a palavra, então uma recusa do tipo "essa é a palavra secreta" **confirmaria para ele que acertou**. O aviso é preventivo, a responsabilidade é do jogador.
- Este requisito existe para impedir que alguém "melhore" isso no futuro sem perceber o vazamento.

**IMP-34 — Palavrão é recusado, terceira vez expulsa**
QUANDO o jogador tenta enviar uma palavra vulgar
ENTÃO o envio é recusado em vermelho com "Proibido utilizar palavras vulgares. Se continuar, será expulso da sala.", e a tentativa conta como falta.

- A verificação é no **banco**: cliente é conveniência, autoridade é do servidor.
- Comparação normalizada (minúsculas, sem acento) para pegar variações.
- Faltas acumulam por jogador ao longo da sala, não por rodada.
- Na **terceira** falta o jogador é expulso da sala.
- Falta recusada não consome o turno: o prazo continua correndo e ele pode enviar outra palavra.
- Se o expulso for o impostor da rodada em andamento, a partida encerra com vitória dos verdadeiros — mesma regra do abandono (IMP-27).

**IMP-35 — Dica revelada a todos**
QUANDO o jogador envia a dica em "Pronto"
ENTÃO a palavra aparece para todos os jogadores em menos de 1 segundo, e o turno passa para o próximo da ordem.

- As dicas da rodada ficam visíveis e acumuladas: é sobre elas que a mesa desconfia.

**IMP-36 — Prazo estourado passa o turno**
QUANDO o prazo do turno vence sem envio
ENTÃO o turno passa para o próximo jogador e a posição fica registrada como sem palavra.

- Não é falta e não pontua contra ninguém: pode ser simplesmente conexão ruim.
- Finalizável por qualquer cliente cujo contador zerou, e idempotente — o Postgres não dispara nada sozinho.

**IMP-37 — Fim dos turnos: o host decide**
QUANDO o último jogador da ordem conclui seu turno
ENTÃO o host vê duas opções: "Abrir votação" e "Nova rodada"; os outros veem que a decisão é dele.

- "Nova rodada" incrementa `discussion_round`, sorteia ordem nova e recomeça os turnos, mantendo as dicas anteriores visíveis.
- "Abrir votação" segue para VOTING como hoje.
- O host **não** consegue abrir a votação antes de todos terem passado pelo turno: até então a ação é recusada.

## Não incluído

- Dicionário de português para validar existência da palavra (avaliado e recusado em IMP-32).
- Corretor ortográfico ou sugestão de palavra.
- Denúncia de dica pela mesa ("essa entregou a palavra").
- Tempo configurável por sala.

## Rastreabilidade

| Requisito | Onde é verificado |
|---|---|
| IMP-30, IMP-31, IMP-35, IMP-36, IMP-37 | `supabase/tests/12_clue_turns.test.sql` |
| IMP-32, IMP-33, IMP-34 | `supabase/tests/13_clue_validation.test.sql` |
| IMP-32 (cliente) | `src/lib/game/clue.test.ts` |
| IMP-31 (contador), IMP-34 (aviso) | Verificação em navegador |
