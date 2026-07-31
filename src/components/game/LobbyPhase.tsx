'use client'

import { useState } from 'react'
import { motion } from 'motion/react'
import { Check, Loader2, Share2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { PhaseShell } from '@/components/shared/PhaseShell'
import { PlayerGrid } from '@/components/shared/PlayerGrid'
import { startGame } from '@/lib/game/actions'
import { toDisplayError } from '@/lib/game/errors'
import type { PhaseProps } from '@/components/game/types'

const MIN_PLAYERS = 3

export function LobbyPhase({ room, players, me, isHost }: PhaseProps) {
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [shared, setShared] = useState(false)

  const missing = Math.max(0, MIN_PLAYERS - players.length)

  async function share() {
    const url = typeof window !== 'undefined' ? window.location.href : ''
    const text = `Entra na minha sala do Jogo do Impostor. Código: ${room.code}`

    // `navigator.share` abre a folha nativa do celular (WhatsApp direto). O
    // clipboard é o plano B para desktop e navegadores sem suporte.
    try {
      if (navigator.share) {
        await navigator.share({ title: 'Jogo do Impostor', text, url })
        return
      }
      await navigator.clipboard.writeText(`${text}\n${url}`)
      setShared(true)
      setTimeout(() => setShared(false), 2000)
    } catch {
      // Usuário cancelou a folha de compartilhamento. Não é erro.
    }
  }

  async function start() {
    setBusy(true)
    setError(null)
    try {
      await startGame(room.id)
    } catch (err) {
      setError(toDisplayError(err))
    } finally {
      setBusy(false)
    }
  }

  return (
    <PhaseShell
      eyebrow="Lobby"
      title="Sala aberta"
      subtitle="Compartilhe o código. A partida começa quando o host quiser."
      aside={
        <>
          <div className="mb-3 flex items-baseline justify-between">
            <h2 className="font-semibold">Na mesa</h2>
            <span className="text-muted-foreground tabular text-sm">
              {players.length} {players.length === 1 ? 'jogador' : 'jogadores'}
            </span>
          </div>

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
              disabled={missing > 0 || busy}
              onClick={() => void start()}
              className="glow-primary h-14 w-full text-base font-bold tracking-wide"
            >
              {busy && <Loader2 className="size-5 animate-spin" aria-hidden />}
              {missing > 0
                ? `Faltam ${missing} ${missing === 1 ? 'jogador' : 'jogadores'}`
                : 'Iniciar partida'}
            </Button>
          </div>
        ) : (
          <div className="bg-card text-muted-foreground flex h-14 w-full items-center justify-center gap-2 rounded-xl border text-sm font-medium">
            <Loader2 className="size-4 animate-spin" aria-hidden />
            Aguardando o host iniciar
          </div>
        )
      }
    >
      {/* Código gigante: é lido em voz alta e digitado por outra pessoa. */}
      <motion.button
        type="button"
        onClick={() => void share()}
        whileTap={{ scale: 0.97 }}
        className="bg-card card-wash border-primary/25 glow-primary mb-6 flex w-full flex-col items-center gap-2 rounded-3xl border p-6"
      >
        <span className="text-muted-foreground text-xs font-semibold tracking-[0.18em] uppercase">
          Código da sala
        </span>
        <span className="tabular text-primary text-5xl font-bold tracking-[0.2em]">
          {room.code}
        </span>
        <span className="text-muted-foreground mt-1 flex items-center gap-1.5 text-sm">
          {shared ? (
            <>
              <Check className="size-4" aria-hidden />
              Copiado
            </>
          ) : (
            <>
              <Share2 className="size-4" aria-hidden />
              Toque para compartilhar
            </>
          )}
        </span>
      </motion.button>
    </PhaseShell>
  )
}
