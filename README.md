# Jogo do Impostor

Jogo de dedução social para jogar **presencialmente**, usando o celular só para o que precisa ser secreto.

Todos na mesa recebem a mesma palavra. Menos um. O impostor não sabe qual é, e tem que blefar a partir das dicas que os outros dão. A conversa acontece na vida real — o app entrega o card secreto, recolhe os votos e conta o resultado.

🎮 **[rsimpostorgame.vercel.app](https://rsimpostorgame.vercel.app)**

## Como funciona uma partida

1. Alguém cria a sala e passa o código de 4 letras para a mesa.
2. Cada um vê seu card secreto — **segurando o dedo na tela por 2 segundos**. Solta, esconde.
3. Conversem ao vivo, na ordem que quiserem. O app não interrompe, não cronometra e não diz de quem é a vez.
4. Quando a mesa quiser, o host abre a votação. Empate ou "pular" vencendo? Mais uma rodada de dicas.
5. Eliminaram um inocente? O impostor ganha. Acertaram o impostor? Ele ainda tem **5 segundos** para adivinhar a palavra entre 4 opções e roubar a vitória.

De 3 a 12 jogadores. Pontuação: verdadeiros +1 cada, impostor descoberto 0, impostor não descoberto +2, roubo na Última Chance +3.

## A regra que sustenta o jogo

**O banco é a autoridade.** Toda transição de fase é uma função SQL `SECURITY DEFINER` com lock na linha da sala. O cliente lê estado e chama RPC — nunca decide regra, nunca recalcula resultado.

Disso decorre o cuidado mais importante do código: **a palavra secreta e a identidade do impostor nunca entram em `rooms`**. RLS filtra linhas, não colunas — qualquer coluna de `rooms` é visível para todo jogador inscrito no Realtime daquela sala. O segredo vive em `rounds` (sem grants para o cliente) e é entregue individualmente por `player_cards`, com RLS de linha própria.

Um vazamento aqui seria falha **silenciosa**: o jogo continuaria funcionando, só que trapaceável. É por isso que `supabase/tests/03_secret_isolation.test.sql` troca de verdade para o role `authenticated` e verifica o que o cliente consegue ler.

Detalhes em [`AGENTS.md`](AGENTS.md) e [`.specs/`](.specs/).

## Stack

Next.js 16 (App Router) · React 19 · Tailwind 4 · shadcn/ui · Motion · Supabase (Postgres + RLS + Realtime + auth anônima) · Vitest · pgTAP

## Rodando local

Requer Docker (para o Supabase local) e Node 22+.

```bash
npm install
npx supabase start                    # sobe Postgres, Auth, Realtime e Studio
cp .env.example .env.local            # e preencha com a saída do supabase start
npm run dev
```

O `supabase start` imprime `API_URL` e `ANON_KEY` — são esses valores que vão para `NEXT_PUBLIC_SUPABASE_URL` e `NEXT_PUBLIC_SUPABASE_ANON_KEY`.

## Comandos

```bash
npm run dev           # Next dev (Turbopack)
npm test              # Vitest: lógica pura e componentes
npm run verify        # gate completo: tsc + eslint + vitest + build
npx supabase test db  # pgTAP: as regras do jogo (143 asserções)
npx supabase db reset # reaplica migrations + seed
npm run db:types      # regenera os tipos TypeScript do schema
```

As **regras do jogo são testadas em pgTAP**, não em Vitest — elas vivem no banco, então os testes vivem no banco. O Vitest cobre lógica pura (normalização de código de sala) e componente (o hold-to-reveal).

## Deploy

Push em `main` publica automaticamente na Vercel. O banco é separado:

```bash
npx supabase link --project-ref <ref>
npx supabase db push      # envia só as migrations
npx supabase config push  # envia a config de auth
```

`supabase/seed.sql` contém helpers de teste que fabricam usuários — por isso fica fora de `migrations/`: o `db reset` local aplica, o `db push` não envia.

## Duas armadilhas que já custaram tempo

**Login anônimo precisa estar habilitado.** A identidade do jogador é uma sessão anônima e toda RPC começa com `require_uid()`. Com o provider desativado, `signInAnonymously()` volta 422 e ninguém entra em sala. Está versionado em `config.toml` (`enable_anonymous_sign_ins`), então `config push` resolve.

**`rooms.code` tem que ser `text`, nunca `char(4)`.** O decodificador WAL→JSON do Realtime trata `bpchar` como char de 1 caractere e entrega `"code": "F"` no lugar de `"F2VQ"`. A leitura REST vem correta, então criar a sala *parece* funcionar — o código só quebra no primeiro `UPDATE` da sala, que é o próprio `create_room` gravando o host. Existe teste guardando o tipo.
