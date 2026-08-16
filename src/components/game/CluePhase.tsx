'use client'

import { useCallback, useRef, useState } from 'react'
import { AnimatePresence, motion } from 'motion/react'
import { Ban, Loader2, MessagesSquare, PencilLine, RotateCcw, Scale, Vote } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { PhaseShell } from '@/components/shared/PhaseShell'
import { PlayerGrid } from '@/components/shared/PlayerGrid'
import { PlayerAvatar } from '@/components/shared/PlayerAvatar'
import { Countdown } from '@/components/shared/Countdown'
import { ClueDialog } from '@/components/game/ClueDialog'
import { expireClueTurn, nextClueRound, openVoting, startClueRoundNow } from '@/lib/game/actions'
import { toDisplayError } from '@/lib/game/errors'
import { cn } from '@/lib/utils'
import type { PhaseProps } from '@/components/game/types'
import type { Player, RoundClue, VoteTally } from '@/lib/types'

/**
 * Espelha `clue_turn_seconds` no banco. Quem manda no prazo é `turn_deadline`;
 * isto só desenha a contagem.
 */
const TURN_MS = 30_000

/** Espelha `interval '10 seconds'` do anúncio de votação indecisa. (IMP-39) */
const INTERLUDE_MS = 10_000

type CluePhaseProps = PhaseProps & {
  clues: RoundClue[]
}

/**
 * Fase de dicas escritas. (IMP-30 a IMP-37)
 *
 * A fase tem ritmo, mas não gerencia a conversa: enquanto o contador do próximo
 * corre, a mesa comenta à vontade. É isso que faz o mesmo fluxo servir presencial
 * e remoto.
 */
export function CluePhase({ room, players, me, isHost, clues }: CluePhaseProps) {
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  /**
   * Turno em que o jogador fechou o popup para consultar a mesa.
   *
   * Guarda QUAL turno foi dispensado, não um booleano: um booleano continuaria
   * verdadeiro no turno seguinte, e o popup deixaria de abrir sozinho na próxima
   * vez da pessoa. Derivar por comparação evita ter que limpar dentro de efeito.
   */
  const [dismissedTurn, setDismissedTurn] = useState<string | null>(null)
  const expireRequested = useRef<string | null>(null)
  const startRequested = useRef<string | null>(null)

  const byId = new Map(players.map((player) => [player.id, player]))
  const roundClues = clues.filter((clue) => clue.discussion_round === room.discussion_round)
  const previous = clues.filter((clue) => clue.discussion_round < room.discussion_round)

  const myClue = roundClues.find((clue) => clue.player_id === me.id)
  const currentClue = roundClues.find((clue) => clue.turn_index === room.clue_turn_index)
  const currentPlayer = currentClue ? byId.get(currentClue.player_id) : undefined

  /**
   * Anúncio da votação indecisa segurando a largada. (IMP-39)
   *
   * Precisa ser checado ANTES de `turnsDone`: nos dois casos `turn_deadline` é
   * nulo, e sem esta distinção a pausa seria lida como "todos já deram a dica".
   */
  const aguardandoLargada = room.clue_round_starts_at !== null

  // O banco zera `turn_deadline` quando não há mais turno a cumprir.
  const turnsDone = !aguardandoLargada && room.turn_deadline === null
  const isMyTurn = !turnsDone && myClue?.turn_index === room.clue_turn_index
  const tally = room.last_vote_tally as VoteTally | null

  const turnKey = `${room.discussion_round}:${room.clue_turn_index}`
  const dismissed = dismissedTurn === turnKey

  /**
   * O Postgres não dispara nada sozinho: quem fecha o turno vencido é um cliente
   * cujo contador zerou. A função é idempotente, então todos chamando é
   * inofensivo — o ref só evita repetir a chamada deste aparelho para o MESMO
   * prazo (um turno novo tem prazo novo e pode ser expirado de novo).
   */
  const handleExpire = useCallback(() => {
    const deadline = room.turn_deadline
    if (!deadline || expireRequested.current === deadline) return
    expireRequested.current = deadline
    void expireClueTurn(room.id).catch(() => {
      // Outro cliente chegou primeiro. O Realtime traz o turno seguinte.
    })
  }, [room.id, room.turn_deadline])

  /**
   * Larga a rodada quando os 10s do anúncio acabam. Mesmo padrão do turno
   * vencido: o Postgres não dispara nada sozinho, e a função é idempotente.
   */
  const handleStart = useCallback(() => {
    const at = room.clue_round_starts_at
    if (!at || startRequested.current === at) return
    startRequested.current = at
    void startClueRoundNow(room.id).catch(() => {
      // Outro cliente largou primeiro. O Realtime traz a ordem nova.
    })
  }, [room.id, room.clue_round_starts_at])

  async function run(action: () => Promise<void>) {
    setBusy(true)
    setError(null)
    try {
      await action()
    } catch (err) {
      setError(toDisplayError(err))
    } finally {
      setBusy(false)
    }
  }

  // Expulso por faltas (IMP-34) ou fora da partida: sem turno, mas continua vendo.
  if (!me.is_alive) {
    return (
      <PhaseShell
        eyebrow={`Rodada ${room.discussion_round}`}
        title="Você está fora desta partida"
        subtitle="Continua acompanhando as dicas, mas sem turno para escrever."
        aside={<Mesa room={room} players={players} me={me} />}
      >
        <div className="bg-card border-destructive/30 card-wash-danger flex flex-col items-center gap-3 rounded-3xl border p-8 text-center">
          <Ban className="text-destructive size-10" aria-hidden />
          <p className="text-muted-foreground max-w-[30ch] text-sm text-pretty">
            Palavras vulgares foram usadas três vezes nesta sala com o seu nome.
          </p>
        </div>

        <ClueBoard
          roundClues={roundClues}
          previous={previous}
          byId={byId}
          currentTurnIndex={room.clue_turn_index}
          turnsDone={turnsDone}
        />
      </PhaseShell>
    )
  }

  // Anúncio da votação indecisa: a mesa lê o resultado e a rodada larga junto.
  if (aguardandoLargada) {
    return (
      <PhaseShell
        eyebrow={`Rodada ${room.discussion_round}`}
        title={tally && tally.skip >= tally.top ? 'A mesa preferiu pular' : 'Deu empate na votação'}
        subtitle="Ninguém foi suspeitado o suficiente para sair. A rodada de dicas recomeça em instantes."
        aside={<Mesa room={room} players={players} me={me} />}
      >
        <div className="border-warn/40 bg-warn/10 flex flex-col items-center gap-5 rounded-3xl border p-8 text-center">
          <Scale className="text-warn size-10" aria-hidden />

          <VotingOutcome tally={tally} players={players} round={room.discussion_round} bare />

          <Countdown
            key={room.clue_round_starts_at ?? 'sem-largada'}
            deadline={room.clue_round_starts_at}
            totalMs={INTERLUDE_MS}
            onExpire={handleStart}
            tone="primary"
          />

          <p className="text-muted-foreground text-sm">Nova rodada de dicas começando…</p>
        </div>
      </PhaseShell>
    )
  }

  return (
    <>
      {isMyTurn && (
        // `key` no turno: input, erro e faltas são estado local e precisam nascer
        // limpos a cada vez.
        <ClueDialog
          key={turnKey}
          roomId={room.id}
          deadline={room.turn_deadline}
          totalMs={TURN_MS}
          onExpire={handleExpire}
          onDismiss={() => setDismissedTurn(turnKey)}
          open={!dismissed}
        />
      )}

      <PhaseShell
        eyebrow={`Rodada ${room.discussion_round}`}
        title={
          turnsDone
            ? 'Todos deram a dica'
            : isMyTurn
              ? 'Sua vez de dar a dica'
              : `Vez de ${currentPlayer?.name ?? '…'}`
        }
        subtitle={
          turnsDone
            ? isHost
              ? 'Você decide: mais uma rodada de dicas, ou já para a votação.'
              : 'O host decide se vem outra rodada de dicas ou a votação.'
            : room.discussion_round > 1 && tally
              ? 'A votação anterior não decidiu nada. Mais uma rodada de dicas e votem de novo.'
              : 'Enquanto o contador corre, comentem as dicas à vontade — o app não interrompe.'
        }
        aside={<Mesa room={room} players={players} me={me} />}
        action={
          turnsDone ? (
            isHost ? (
              <div className="flex flex-col gap-2">
                {error && (
                  <p role="alert" className="text-destructive text-sm font-medium">
                    {error}
                  </p>
                )}
                <Button
                  size="lg"
                  disabled={busy}
                  onClick={() => void run(() => openVoting(room.id))}
                  className="glow-primary h-14 w-full text-base font-bold tracking-wide"
                >
                  {busy ? (
                    <Loader2 className="size-5 animate-spin" aria-hidden />
                  ) : (
                    <Vote className="size-5" aria-hidden />
                  )}
                  Abrir votação
                </Button>
                <Button
                  variant="secondary"
                  disabled={busy}
                  onClick={() => void run(() => nextClueRound(room.id))}
                  className="h-12 w-full font-semibold"
                >
                  <RotateCcw className="size-4" aria-hidden />
                  Nova rodada de dicas
                </Button>
              </div>
            ) : (
              <div className="bg-card text-muted-foreground flex h-14 w-full items-center justify-center gap-2 rounded-xl border text-sm font-medium">
                <Loader2 className="size-4 animate-spin" aria-hidden />
                Aguardando a decisão do host
              </div>
            )
          ) : isMyTurn ? (
            <Button
              size="lg"
              onClick={() => setDismissedTurn(null)}
              className="glow-primary h-14 w-full text-base font-bold tracking-wide"
            >
              <PencilLine className="size-5" aria-hidden />
              Escrever minha palavra
            </Button>
          ) : (
            <div className="bg-card flex w-full flex-col items-center gap-3 rounded-2xl border p-4">
              {currentPlayer && (
                <div className="flex items-center gap-2">
                  <PlayerAvatar player={currentPlayer} size="sm" />
                  <span className="text-sm font-semibold">{currentPlayer.name}</span>
                  <span className="text-muted-foreground text-sm">está escrevendo…</span>
                </div>
              )}
              <Countdown
                key={room.turn_deadline ?? 'sem-prazo'}
                deadline={room.turn_deadline}
                totalMs={TURN_MS}
                onExpire={handleExpire}
              />
            </div>
          )
        }
      >
        {/*
          POR QUE a mesa voltou às dicas — no TOPO, antes do quadro.
          Já existia, mas no fim do conteúdo: no celular ficava fora da tela, e
          uma família jogando concluiu que o app tinha quebrado ao votar duas
          vezes sem nada acontecer. A regra estava certa (empate não elimina); o
          que faltou foi dizer isso.
        */}
        <VotingOutcome tally={tally} players={players} round={room.discussion_round} />

        <ClueBoard
          roundClues={roundClues}
          previous={previous}
          byId={byId}
          currentTurnIndex={room.clue_turn_index}
          turnsDone={turnsDone}
        />
      </PhaseShell>
    </>
  )
}

/**
 * Resultado da votação que não decidiu nada. (IMP-13)
 *
 * Mostra NOMES e contagem, não só "houve empate": a mesa precisa ver que 2 a 2
 * aconteceu de verdade, senão parece que o voto se perdeu. Os votos já estão
 * apurados neste ponto, então exibi-los não vaza nada.
 */
function VotingOutcome({
  tally,
  players,
  round,
  bare = false,
}: {
  tally: VoteTally | null
  players: Player[]
  round: number
  /** Dentro do anúncio em tela cheia a moldura já existe: só o conteúdo. */
  bare?: boolean
}) {
  if (round <= 1 || !tally) return null

  const pulou = tally.skip >= tally.top
  const empatados = players
    .filter((p) => tally.top > 0 && (tally.players[p.id] ?? 0) === tally.top)
    .map((p) => `${p.name} ${tally.players[p.id]}`)

  if (bare) {
    return (
      <div>
        <p className="text-xl font-bold text-pretty">
          {pulou
            ? `${tally.skip} ${tally.skip === 1 ? 'voto' : 'votos'} para pular.`
            : empatados.join('  ·  ')}
        </p>
        <p className="text-muted-foreground mt-2 text-sm text-pretty">
          Deem mais uma dica cada um e votem de novo.
        </p>
      </div>
    )
  }

  return (
    <motion.div
      initial={{ opacity: 0, y: -6 }}
      animate={{ opacity: 1, y: 0 }}
      className="border-warn/40 bg-warn/10 mb-5 rounded-2xl border p-4"
    >
      <p className="text-warn flex items-center gap-2 text-sm font-bold">
        <Scale className="size-4 shrink-0" aria-hidden />
        {pulou ? 'A mesa preferiu pular' : 'Deu empate na votação'}
      </p>

      <p className="mt-2 text-sm font-semibold text-pretty">
        {pulou
          ? `${tally.skip} ${tally.skip === 1 ? 'voto' : 'votos'} para pular.`
          : empatados.join('  ·  ')}
      </p>

      <p className="text-muted-foreground mt-1 text-sm text-pretty">
        Ninguém foi eliminado. Deem mais uma dica cada um e votem de novo.
      </p>
    </motion.div>
  )
}

function Mesa({
  room,
  players,
  me,
}: Pick<CluePhaseProps, 'room' | 'players' | 'me'>) {
  return (
    <>
      <h2 className="mb-3 font-semibold">Na mesa</h2>
      <PlayerGrid
        players={players}
        hostPlayerId={room.host_player_id}
        myPlayerId={me.id}
        showScore={room.games_played > 0}
      />
    </>
  )
}

type ClueBoardProps = {
  roundClues: RoundClue[]
  previous: RoundClue[]
  byId: Map<string, Player>
  currentTurnIndex: number
  turnsDone: boolean
}

/** Ordem sorteada e dicas dadas, com as rodadas anteriores acumuladas. */
function ClueBoard({
  roundClues,
  previous,
  byId,
  currentTurnIndex,
  turnsDone,
}: ClueBoardProps) {
  const previousRounds = [...new Set(previous.map((c) => c.discussion_round))].sort()

  return (
    <div className="flex flex-col gap-5">
      {roundClues.length === 0 ? (
        <div className="bg-card text-muted-foreground flex items-center justify-center gap-2 rounded-3xl border p-8 text-sm">
          <MessagesSquare className="size-4" aria-hidden />
          Sorteando a ordem…
        </div>
      ) : (
        <ul className="flex flex-col gap-2">
          <AnimatePresence initial={false}>
            {roundClues.map((clue) => {
              const player = byId.get(clue.player_id)
              const isNow = !turnsDone && clue.turn_index === currentTurnIndex
              const answered = clue.word !== null

              return (
                <motion.li
                  key={clue.player_id}
                  layout
                  className={cn(
                    'bg-card flex items-center gap-3 rounded-2xl border p-3',
                    isNow && 'border-primary/60 glow-primary',
                    !answered && !isNow && !clue.timed_out && 'opacity-50',
                  )}
                >
                  <span className="tabular text-muted-foreground w-5 text-sm font-bold">
                    {clue.turn_index + 1}
                  </span>

                  {player && <PlayerAvatar player={player} size="sm" />}

                  <span className="min-w-0 flex-1 truncate text-sm font-medium">
                    {player?.name ?? 'Jogador'}
                  </span>

                  {answered ? (
                    <motion.span
                      initial={{ opacity: 0, scale: 0.8 }}
                      animate={{ opacity: 1, scale: 1 }}
                      className="text-primary max-w-[45%] truncate text-base font-bold"
                    >
                      {clue.word}
                    </motion.span>
                  ) : clue.timed_out ? (
                    <span className="text-muted-foreground text-xs">sem palavra</span>
                  ) : isNow ? (
                    <span className="text-primary text-xs font-semibold">escrevendo…</span>
                  ) : (
                    <span className="text-muted-foreground text-xs">aguardando</span>
                  )}
                </motion.li>
              )
            })}
          </AnimatePresence>
        </ul>
      )}

      {/* Rodadas anteriores continuam visíveis: é sobre o acumulado que a mesa
          desconfia. (IMP-37) */}
      {previousRounds.map((roundNumber) => (
        <div key={roundNumber}>
          <h3 className="text-muted-foreground mb-2 text-xs font-semibold tracking-[0.18em] uppercase">
            Rodada {roundNumber}
          </h3>
          <ul className="flex flex-wrap gap-2">
            {previous
              .filter((clue) => clue.discussion_round === roundNumber)
              .map((clue) => (
                <li
                  key={`${roundNumber}:${clue.player_id}`}
                  className="bg-card/60 text-muted-foreground flex items-center gap-2 rounded-xl border px-3 py-1.5 text-sm"
                >
                  <span className="text-xs opacity-70">
                    {byId.get(clue.player_id)?.name ?? '—'}
                  </span>
                  <span className="text-foreground font-semibold">
                    {clue.word ?? '—'}
                  </span>
                </li>
              ))}
          </ul>
        </div>
      ))}
    </div>
  )
}
