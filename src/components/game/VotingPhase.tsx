'use client'

import { useState } from 'react'
import { AnimatePresence, motion } from 'motion/react'
import { Loader2, SkipForward } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { PhaseShell } from '@/components/shared/PhaseShell'
import { PlayerAvatar } from '@/components/shared/PlayerAvatar'
import { castVote } from '@/lib/game/actions'
import { toDisplayError } from '@/lib/game/errors'
import { cn } from '@/lib/utils'
import type { PhaseProps } from '@/components/game/types'

/** Sentinela para "Pular Votação", que no banco é `target_player_id = NULL`. */
const SKIP = 'SKIP'

export function VotingPhase({ room, players, me }: PhaseProps) {
  const [selected, setSelected] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const alive = players.filter((player) => player.is_alive)
  const suspects = alive.filter((player) => player.id !== me.id)
  const votedCount = room.votes_cast

  async function confirm() {
    if (!selected) return
    setBusy(true)
    setError(null)
    try {
      await castVote(room.id, selected === SKIP ? null : selected)
    } catch (err) {
      setError(toDisplayError(err))
      setBusy(false)
    }
  }

  // Já votei: nada mais a fazer neste ciclo. `has_voted` vem do banco, então
  // recarregar a página cai aqui em vez de oferecer votar de novo.
  if (me.has_voted) {
    return (
      <PhaseShell
        eyebrow={`Votação ${room.voting_cycle}`}
        title="Voto registrado"
        subtitle="Ninguém vê em quem você votou. A apuração começa quando o último votar."
        action={
          <div className="bg-card text-muted-foreground flex h-14 w-full items-center justify-center gap-2 rounded-xl border text-sm font-medium">
            <Loader2 className="size-4 animate-spin" aria-hidden />
            {votedCount} de {alive.length} já votaram
          </div>
        }
      >
        <div className="bg-card flex flex-col items-center gap-4 rounded-3xl border p-8 text-center">
          <div className="flex flex-wrap items-center justify-center gap-2">
            {alive.map((player) => (
              <motion.div
                key={player.id}
                animate={{ opacity: player.has_voted ? 1 : 0.25 }}
                transition={{ duration: 0.3 }}
              >
                <PlayerAvatar player={player} size="md" />
              </motion.div>
            ))}
          </div>
          <p className="text-muted-foreground max-w-[28ch] text-sm text-pretty">
            Os avatares acesos já votaram. Os apagados a mesa ainda espera.
          </p>
        </div>
      </PhaseShell>
    )
  }

  return (
    <PhaseShell
      eyebrow={`Votação ${room.voting_cycle}`}
      title="Quem é o impostor?"
      subtitle="Toque em um suspeito. Se a mesa não se decidiu, pule e joguem mais uma rodada."
      action={
        <div className="flex flex-col gap-2">
          {error && (
            <p role="alert" className="text-destructive text-sm font-medium">
              {error}
            </p>
          )}
          <Button
            size="lg"
            disabled={!selected || busy}
            onClick={() => void confirm()}
            className="glow-primary h-14 w-full text-base font-bold tracking-wide"
          >
            {busy && <Loader2 className="size-5 animate-spin" aria-hidden />}
            {selected === SKIP ? 'Confirmar: pular votação' : 'Confirmar voto'}
          </Button>
          <p className="text-muted-foreground text-center text-xs">
            {votedCount} de {alive.length} já votaram
          </p>
        </div>
      }
    >
      <ul className="mb-3 flex flex-col gap-2">
        {suspects.map((player) => {
          const isSelected = selected === player.id

          return (
            <li key={player.id}>
              <button
                type="button"
                aria-pressed={isSelected}
                onClick={() => setSelected(isSelected ? null : player.id)}
                className={cn(
                  'relative flex w-full items-center gap-3 overflow-hidden rounded-2xl border-2 p-4 text-left transition-colors',
                  isSelected
                    ? 'border-destructive bg-destructive/10'
                    : 'bg-card border-transparent',
                )}
              >
                <PlayerAvatar player={player} size="lg" />
                <span className="min-w-0 flex-1 truncate text-lg font-semibold">
                  {player.name}
                </span>

                {/* Carimbo de suspeito (IMP-23). */}
                <AnimatePresence>
                  {isSelected && (
                    <motion.span
                      initial={{ opacity: 0, scale: 2.4, rotate: -24 }}
                      animate={{ opacity: 1, scale: 1, rotate: -12 }}
                      exit={{ opacity: 0, scale: 1.4 }}
                      transition={{ type: 'spring', stiffness: 420, damping: 18 }}
                      className="border-destructive text-destructive pointer-events-none absolute right-3 rounded-md border-4 px-2 py-1 text-sm font-black tracking-widest uppercase"
                    >
                      Suspeito
                    </motion.span>
                  )}
                </AnimatePresence>
              </button>
            </li>
          )
        })}
      </ul>

      <button
        type="button"
        aria-pressed={selected === SKIP}
        onClick={() => setSelected(selected === SKIP ? null : SKIP)}
        className={cn(
          'flex w-full items-center justify-center gap-2 rounded-2xl border-2 border-dashed p-4 text-sm font-semibold transition-colors',
          selected === SKIP
            ? 'border-primary bg-primary/10 text-foreground'
            : 'text-muted-foreground border-border',
        )}
      >
        <SkipForward className="size-4" aria-hidden />
        Pular votação
      </button>
    </PhaseShell>
  )
}
