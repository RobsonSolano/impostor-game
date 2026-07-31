'use client'

import { useState } from 'react'
import { motion } from 'motion/react'
import { Loader2, MessagesSquare, Vote } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { PhaseShell } from '@/components/shared/PhaseShell'
import { PlayerGrid } from '@/components/shared/PlayerGrid'
import { openVoting } from '@/lib/game/actions'
import { toDisplayError } from '@/lib/game/errors'
import type { PhaseProps } from '@/components/game/types'
import type { VoteTally } from '@/lib/types'

/**
 * Fase de discussão.
 *
 * Intencionalmente a tela mais vazia do app: durante as dicas ninguém precisa
 * fazer nada aqui. Não há ordem de fala, não há timer, não há "sua vez". O grupo
 * conversa ao vivo e o app só espera o host dizer que acabou.
 */
export function DiscussionPhase({ room, players, me, isHost }: PhaseProps) {
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const tally = room.last_vote_tally as VoteTally | null
  const isRerun = room.discussion_round > 1

  async function open() {
    setBusy(true)
    setError(null)
    try {
      await openVoting(room.id)
    } catch (err) {
      setError(toDisplayError(err))
    } finally {
      setBusy(false)
    }
  }

  return (
    <PhaseShell
      eyebrow={`Rodada ${room.discussion_round}`}
      title={isRerun ? 'Mais uma rodada de dicas' : 'Hora de conversar'}
      subtitle={
        isRerun
          ? 'A votação anterior não decidiu nada. Deem mais uma dica cada um e votem de novo.'
          : 'Cada um dá suas dicas em voz alta, na ordem que o grupo quiser. O app não interrompe.'
      }
      aside={
        <>
          <h2 className="mb-3 font-semibold">Na mesa</h2>
          <PlayerGrid
            players={players}
            hostPlayerId={room.host_player_id}
            myPlayerId={me.id}
            showScore={room.games_played > 0}
          />
        </>
      }
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
              onClick={() => void open()}
              className="glow-primary h-14 w-full text-base font-bold tracking-wide"
            >
              {busy ? (
                <Loader2 className="size-5 animate-spin" aria-hidden />
              ) : (
                <Vote className="size-5" aria-hidden />
              )}
              Abrir votação
            </Button>
          </div>
        ) : (
          <div className="bg-card text-muted-foreground flex h-14 w-full items-center justify-center gap-2 rounded-xl border text-sm font-medium">
            <Loader2 className="size-4 animate-spin" aria-hidden />
            O host abre a votação quando a mesa terminar
          </div>
        )
      }
    >
      <motion.div
        initial={{ opacity: 0, scale: 0.96 }}
        animate={{ opacity: 1, scale: 1 }}
        className="bg-card mb-6 flex flex-col items-center gap-3 rounded-3xl border p-8 text-center"
      >
        <MessagesSquare className="text-muted-foreground size-10" aria-hidden />
        <p className="text-lg font-semibold">Conversem à vontade</p>
        <p className="text-muted-foreground max-w-[28ch] text-sm text-pretty">
          Nada a tocar por aqui agora. Voltem ao app quando for votar.
        </p>
      </motion.div>

      {/* Só depois de um ciclo indeciso: explica POR QUE o jogo voltou. */}
      {isRerun && tally && (
        <div className="border-muted bg-muted/30 mb-6 rounded-2xl border p-4">
          <p className="text-sm font-semibold">Votação anterior</p>
          <p className="text-muted-foreground mt-1 text-sm text-pretty">
            {tally.skip >= tally.top
              ? `A maioria preferiu pular (${tally.skip} ${tally.skip === 1 ? 'voto' : 'votos'}). Ninguém foi eliminado.`
              : 'Houve empate no topo. Ninguém foi eliminado.'}
          </p>
        </div>
      )}

    </PhaseShell>
  )
}
