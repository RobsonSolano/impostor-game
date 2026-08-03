'use client'

import { useCallback, useRef, useState } from 'react'
import { motion } from 'motion/react'
import { Hourglass, Loader2 } from 'lucide-react'
import { PhaseShell } from '@/components/shared/PhaseShell'
import { PlayerAvatar } from '@/components/shared/PlayerAvatar'
import { Countdown } from '@/components/shared/Countdown'
import { expireLastChance, submitGuess } from '@/lib/game/actions'
import { toDisplayError } from '@/lib/game/errors'
import type { PhaseProps } from '@/components/game/types'
import type { PlayerCard } from '@/lib/types'

/**
 * Espelha `interval '5 seconds'` em `resolve_voting`. Quem manda no prazo é o
 * banco (`rooms.guess_deadline`); isto só desenha a contagem.
 */
const TOTAL_MS = 5_000

type LastChancePhaseProps = PhaseProps & {
  card: PlayerCard | null
}

/** Última Chance do Impostor (IMP-15 a IMP-17). */
export function LastChancePhase({ room, players, me, card }: LastChancePhaseProps) {
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const expireRequested = useRef(false)

  const amImpostor = card?.is_impostor ?? false
  const options = card?.last_chance_options ?? []
  const eliminated = players.find((player) => player.id === room.eliminated_player_id)

  /**
   * Postgres não dispara nada sozinho: quem finaliza é um cliente cujo timer
   * zerou. A função é idempotente no banco, então todos chamando é inofensivo —
   * o ref só evita repetir a chamada deste aparelho. Ver CONCERNS.md #3.
   */
  const handleExpire = useCallback(() => {
    if (expireRequested.current) return
    expireRequested.current = true
    void expireLastChance(room.id).catch(() => {
      // Outro cliente chegou primeiro. O Realtime traz o resultado.
    })
  }, [room.id])

  async function guess(word: string) {
    if (busy) return
    setBusy(true)
    setError(null)
    try {
      await submitGuess(room.id, word)
    } catch (err) {
      setError(toDisplayError(err))
      setBusy(false)
    }
  }

  // `key` no prazo: prazo novo precisa de instância nova do contador.
  const countdown = (
    <Countdown
      key={room.guess_deadline ?? 'sem-prazo'}
      deadline={room.guess_deadline}
      totalMs={TOTAL_MS}
      onExpire={handleExpire}
      tone="violet"
    />
  )

  if (!amImpostor) {
    return (
      <PhaseShell
        eyebrow="Última Chance"
        title={`${eliminated?.name ?? 'O suspeito'} era o impostor!`}
        // Sem "ele/ela": o app não sabe o gênero de ninguém na mesa.
        subtitle="São 5 segundos para adivinhar a palavra e roubar a vitória de vocês."
        action={
          <div className="bg-card text-muted-foreground flex h-14 w-full items-center justify-center gap-2 rounded-xl border text-sm font-medium">
            <Hourglass className="text-violet size-4 animate-pulse" aria-hidden />
            Aguardando o palpite
          </div>
        }
      >
        <div className="bg-card card-wash-violet border-violet/30 flex flex-col items-center gap-6 rounded-3xl border p-8 text-center">
          {eliminated && <PlayerAvatar player={eliminated} size="lg" />}
          {countdown}
          <p className="text-muted-foreground max-w-[28ch] text-sm text-pretty">
            Se acertar, a vitória é do impostor. Se errar ou o tempo acabar, vocês
            ganham.
          </p>
        </div>
      </PhaseShell>
    )
  }

  return (
    <PhaseShell
      eyebrow="Última Chance"
      title="Você foi descoberto!"
      subtitle="Acerte a palavra e a vitória é sua. Uma tentativa, 5 segundos."
      action={
        error ? (
          <p role="alert" className="text-destructive text-center text-sm font-medium">
            {error}
          </p>
        ) : (
          <p className="text-muted-foreground text-center text-xs">
            {me.name}, escolha rápido — sem confirmação.
          </p>
        )
      }
    >
      <div className="bg-card card-wash-violet border-violet/30 glow-violet mb-5 rounded-3xl border p-6">{countdown}</div>

      {options.length === 0 ? (
        <div className="text-muted-foreground flex items-center justify-center gap-2 py-8 text-sm">
          <Loader2 className="size-4 animate-spin" aria-hidden />
          Carregando as opções…
        </div>
      ) : (
        <ul className="flex flex-col gap-2">
          {options.map((word) => (
            <li key={word}>
              <motion.button
                type="button"
                whileTap={{ scale: 0.97 }}
                disabled={busy}
                onClick={() => void guess(word)}
                className="bg-card flex min-h-16 w-full items-center justify-center rounded-2xl border-2 border-transparent p-4 text-lg font-semibold active:border-violet disabled:opacity-50"
              >
                {word}
              </motion.button>
            </li>
          ))}
        </ul>
      )}
    </PhaseShell>
  )
}
