'use client'

import { useEffect, useState } from 'react'
import { AnimatePresence, motion } from 'motion/react'
import { Loader2, PartyPopper, RotateCcw, Skull } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { PhaseShell } from '@/components/shared/PhaseShell'
import { PlayerAvatar } from '@/components/shared/PlayerAvatar'
import { playAgain } from '@/lib/game/actions'
import { toDisplayError } from '@/lib/game/errors'
import { cn } from '@/lib/utils'
import { OUTCOME_LABELS, type VoteTally } from '@/lib/types'
import type { PhaseProps } from '@/components/game/types'

const DRUMROLL_SECONDS = 5

export function GameOverPhase({ room, players, me, isHost }: PhaseProps) {
  const [secondsLeft, setSecondsLeft] = useState(DRUMROLL_SECONDS)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const revealed = secondsLeft <= 0

  /**
   * Drumroll (IMP-24), com contagem visível 5 → 0.
   *
   * Roda uma vez por partida: o componente é montado do zero quando
   * `rooms.status` entra em GAME_OVER. Cadeia de setTimeout em vez de
   * setInterval — o setState fica no callback (não no corpo do efeito) e a
   * contagem se encerra sozinha ao chegar em zero.
   *
   * Puro suspense: nada aqui decide resultado. O placar já está gravado no banco
   * antes desta tela aparecer.
   */
  useEffect(() => {
    if (secondsLeft <= 0) return
    const id = setTimeout(() => setSecondsLeft((prev) => prev - 1), 1000)
    return () => clearTimeout(id)
  }, [secondsLeft])

  const impostor = players.find((player) => player.id === room.revealed_impostor_id)
  const eliminated = players.find((player) => player.id === room.eliminated_player_id)
  const tally = room.last_vote_tally as VoteTally | null
  const impostorWon = room.outcome === 'IMPOSTOR_WIN' || room.outcome === 'IMPOSTOR_STEAL'
  const iAmImpostor = impostor?.id === me.id
  const iWon = iAmImpostor === impostorWon

  const scoreboard = [...players].sort((a, b) => b.score - a.score || a.name.localeCompare(b.name))

  async function again() {
    setBusy(true)
    setError(null)
    try {
      await playAgain(room.id)
    } catch (err) {
      setError(toDisplayError(err))
      setBusy(false)
    }
  }

  if (!revealed) {
    return (
      <div className="flex min-h-dvh flex-col items-center justify-center gap-8 px-6 text-center">
        <motion.div
          animate={{ scale: [1, 1.18, 1], rotate: [0, -6, 6, 0] }}
          transition={{ duration: 0.6, repeat: Infinity, ease: 'easeInOut' }}
          className="bg-card card-wash-violet glow-violet border-violet/30 rounded-3xl border p-6"
        >
          <Skull className="text-violet size-14" aria-hidden />
        </motion.div>

        <div className="flex flex-col gap-2">
          <p className="text-2xl font-bold tracking-tight">Apurando os votos…</p>
          <p className="text-muted-foreground text-sm">
            {eliminated ? `A mesa escolheu ${eliminated.name}.` : 'Contando.'}
          </p>
        </div>

        {/* Contagem 5 → 0. `key` no número faz cada segundo entrar com um pulso
            próprio em vez de o texto trocar sem aviso. */}
        <motion.span
          key={secondsLeft}
          initial={{ scale: 1.6, opacity: 0.3 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ duration: 0.3 }}
          className="tabular text-violet text-7xl font-black"
          aria-live="polite"
          aria-label={`Resultado em ${secondsLeft} segundos`}
        >
          {secondsLeft}
        </motion.span>

        <div className="bg-muted h-2 w-48 overflow-hidden rounded-full" aria-hidden>
          <motion.div
            className="bg-violet h-full origin-left"
            initial={false}
            animate={{ scaleX: secondsLeft / DRUMROLL_SECONDS }}
            transition={{ duration: 0.9, ease: 'linear' }}
          />
        </div>
      </div>
    )
  }

  return (
    <PhaseShell
      eyebrow={`Partida ${room.games_played}`}
      title={room.outcome ? OUTCOME_LABELS[room.outcome] : 'Fim de jogo'}
      subtitle={iWon ? 'Você marcou pontos nesta rodada.' : 'Não foi dessa vez.'}
      aside={
        <>
          {tally && (
            <div className="mb-5">
              <h2 className="mb-2 font-semibold">Votação final</h2>
              <ul className="flex flex-col gap-1.5">
                {players
                  .filter((player) => (tally.players[player.id] ?? 0) > 0)
                  .sort((a, b) => (tally.players[b.id] ?? 0) - (tally.players[a.id] ?? 0))
                  .map((player) => {
                    const votes = tally.players[player.id] ?? 0
                    return (
                      <li
                        key={player.id}
                        className="bg-card flex items-center gap-3 rounded-xl border px-3 py-2"
                      >
                        <PlayerAvatar player={player} size="sm" />
                        <span className="min-w-0 flex-1 truncate text-sm font-medium">
                          {player.name}
                        </span>
                        <span className="tabular text-muted-foreground text-sm">
                          {votes} {votes === 1 ? 'voto' : 'votos'}
                        </span>
                      </li>
                    )
                  })}
                {tally.skip > 0 && (
                  <li className="text-muted-foreground bg-card/50 flex items-center gap-3 rounded-xl border border-dashed px-3 py-2 text-sm">
                    <span className="flex-1">Pular votação</span>
                    <span className="tabular">
                      {tally.skip} {tally.skip === 1 ? 'voto' : 'votos'}
                    </span>
                  </li>
                )}
              </ul>
            </div>
          )}

          <h2 className="mb-2 font-semibold">Placar da sala</h2>
          <ul className="flex flex-col gap-1.5">
            {scoreboard.map((player, index) => (
              <li
                key={player.id}
                className="bg-card flex items-center gap-3 rounded-xl border px-3 py-2"
              >
                <span className="tabular text-muted-foreground w-5 text-sm font-bold">
                  {index + 1}
                </span>
                <PlayerAvatar player={player} size="sm" />
                <span className="min-w-0 flex-1 truncate text-sm font-medium">
                  {player.name}
                  {player.id === me.id && (
                    <span className="text-muted-foreground ml-1.5 font-normal">(você)</span>
                  )}
                </span>
                <span className="tabular text-sm font-bold">{player.score}</span>
              </li>
            ))}
          </ul>
        </>
      }
      // O botão de novo jogo aparece em QUALQUER desfecho — vitória dos
      // verdadeiros, do impostor ou roubo na Última Chance. Ninguém sai da sala:
      // muda a palavra e o impostor é sorteado de novo. (IMP-19)
      action={
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
              onClick={() => void again()}
              className="glow-primary h-14 w-full text-base font-bold tracking-wide"
            >
              {busy ? (
                <Loader2 className="size-5 animate-spin" aria-hidden />
              ) : (
                <RotateCcw className="size-5" aria-hidden />
              )}
              Novo jogo
            </Button>
            <p className="text-muted-foreground text-center text-xs">
              Mesma sala e mesmo placar. Nova palavra e novo sorteio de impostor.
            </p>
          </div>
        ) : (
          <div className="bg-card text-muted-foreground flex h-14 w-full items-center justify-center gap-2 rounded-xl border text-sm font-medium">
            <Loader2 className="size-4 animate-spin" aria-hidden />
            O host pode começar um novo jogo
          </div>
        )
      }
    >
      <AnimatePresence>
        <motion.div
          initial={{ opacity: 0, scale: 0.92 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ type: 'spring', stiffness: 240, damping: 20 }}
          className={cn(
            'bg-card mb-5 flex flex-col items-center gap-4 rounded-3xl border p-6 text-center',
            // A cor do card já conta o resultado antes de qualquer texto ser lido.
            impostorWon
              ? 'card-wash-danger border-destructive/30 glow-danger'
              : 'card-wash border-primary/30 glow-primary',
          )}
        >
          <div className="flex items-center gap-2">
            {impostorWon ? (
              <Skull className="text-destructive size-6" aria-hidden />
            ) : (
              <PartyPopper className="text-primary size-6" aria-hidden />
            )}
            <span className="text-muted-foreground text-xs font-semibold tracking-[0.18em] uppercase">
              O impostor era
            </span>
          </div>

          {impostor && (
            <div className="flex flex-col items-center gap-2">
              <PlayerAvatar player={impostor} size="lg" />
              <span className="text-2xl font-bold">{impostor.name}</span>
            </div>
          )}

          <div className="border-border w-full border-t pt-4">
            <p className="text-muted-foreground text-xs font-semibold tracking-[0.18em] uppercase">
              A palavra era
            </p>
            <p className="text-primary mt-1 text-3xl font-bold text-balance">
              {room.revealed_word}
            </p>
          </div>

          {room.outcome === 'IMPOSTOR_STEAL' && (
            <p className="text-destructive max-w-[30ch] text-sm font-medium text-pretty">
              O impostor foi descoberto, mas acertou a palavra na Última Chance e
              roubou a vitória.
            </p>
          )}
        </motion.div>
      </AnimatePresence>
    </PhaseShell>
  )
}
