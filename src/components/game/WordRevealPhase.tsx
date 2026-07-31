'use client'

import { useState } from 'react'
import { Loader2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { PhaseShell } from '@/components/shared/PhaseShell'
import { PlayerGrid } from '@/components/shared/PlayerGrid'
import { HoldToReveal } from '@/components/shared/HoldToReveal'
import { confirmWordSeen } from '@/lib/game/actions'
import { toDisplayError } from '@/lib/game/errors'
import type { PhaseProps } from '@/components/game/types'
import type { PlayerCard } from '@/lib/types'

type WordRevealPhaseProps = PhaseProps & {
  card: PlayerCard | null
}

export function WordRevealPhase({ room, players, me, card }: WordRevealPhaseProps) {
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const seenIds = new Set(players.filter((p) => p.has_seen_card).map((p) => p.id))
  const pending = players.filter((p) => p.is_alive && !p.has_seen_card).length

  async function confirm() {
    setBusy(true)
    setError(null)
    try {
      await confirmWordSeen(room.id)
    } catch (err) {
      setError(toDisplayError(err))
    } finally {
      setBusy(false)
    }
  }

  return (
    <PhaseShell
      eyebrow={`Partida ${room.games_played + 1}`}
      title="Sua palavra secreta"
      subtitle="Segure o card por 2 segundos. Ao soltar, ele esconde na hora."
      aside={
        <>
          <div className="mb-3 flex items-baseline justify-between">
            <h2 className="font-semibold">Quem já viu</h2>
            <span className="text-muted-foreground tabular text-sm">
              {seenIds.size} de {players.filter((p) => p.is_alive).length}
            </span>
          </div>

          <PlayerGrid
            players={players}
            hostPlayerId={room.host_player_id}
            myPlayerId={me.id}
            readyIds={seenIds}
            readyLabel="viu"
          />
        </>
      }
      action={
        me.has_seen_card ? (
          <div className="bg-card text-muted-foreground flex h-14 w-full items-center justify-center gap-2 rounded-xl border text-sm font-medium">
            <Loader2 className="size-4 animate-spin" aria-hidden />
            {pending > 0
              ? `Faltam ${pending} ${pending === 1 ? 'jogador' : 'jogadores'} ver o card`
              : 'Começando…'}
          </div>
        ) : (
          <div className="flex flex-col gap-2">
            {error && (
              <p role="alert" className="text-destructive text-sm font-medium">
                {error}
              </p>
            )}
            <Button
              size="lg"
              disabled={busy || !card}
              onClick={() => void confirm()}
              className="glow-primary h-14 w-full text-base font-bold tracking-wide"
            >
              {busy && <Loader2 className="size-5 animate-spin" aria-hidden />}
              Já vi minha palavra
            </Button>
          </div>
        )
      }
    >
      {/* Sem crescer em tela grande: o card mostra UMA palavra, e esticá-lo por
          proporção de viewport virava um retângulo enorme com uma palavra no meio. */}
      <HoldToReveal className="mb-6 md:mb-0">
        {card?.is_impostor ? (
          <>
            <span className="text-destructive text-3xl font-bold tracking-tight text-balance">
              VOCÊ É O IMPOSTOR 👀
            </span>
            <span className="text-muted-foreground max-w-[26ch] text-sm text-pretty">
              Você não sabe a palavra. Blefe, escute as dicas dos outros e não se
              entregue.
            </span>
          </>
        ) : (
          <>
            <span className="text-primary text-4xl font-bold tracking-tight text-balance">
              {card?.word_text}
            </span>
            <span className="text-muted-foreground max-w-[26ch] text-sm text-pretty">
              Um dos jogadores não recebeu esta palavra. Dê dicas sem entregar de
              graça.
            </span>
          </>
        )}
      </HoldToReveal>
    </PhaseShell>
  )
}
