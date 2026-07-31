'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { AnimatePresence, motion } from 'motion/react'
import { DoorOpen, Loader2 } from 'lucide-react'
import { APP_COLUMN } from '@/components/shared/app-column'
import { leaveRoom } from '@/lib/game/actions'
import { toDisplayError } from '@/lib/game/errors'
import { cn } from '@/lib/utils'

type RoomExitButtonProps = {
  roomId: string
  isHost: boolean
}

/**
 * Saída da sala, disponível em qualquer fase.
 *
 * Para o host, sair encerra a sala para todos (IMP-25) — daí a confirmação em
 * dois toques em vez de um diálogo: é destrutivo para outras pessoas, mas não
 * merece bloquear a tela num jogo de 5 minutos. O segundo toque é o "sim".
 *
 * Quem decide se isto encerra ou apenas sai é `leave_room` no banco, comparando
 * o chamador com `rooms.host_player_id`.
 */
export function RoomExitButton({ roomId, isHost }: RoomExitButtonProps) {
  const router = useRouter()
  const [confirming, setConfirming] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function act() {
    if (isHost && !confirming) {
      setConfirming(true)
      // Sem resposta em 4s, o gesto provavelmente foi acidental.
      setTimeout(() => setConfirming(false), 4000)
      return
    }

    setBusy(true)
    setError(null)
    try {
      await leaveRoom(roomId)
      // O host recebe o redirecionamento via status CLOSED no Realtime, mas quem
      // apenas sai precisa navegar por conta própria.
      router.replace('/')
    } catch (err) {
      setError(toDisplayError(err))
      setBusy(false)
      setConfirming(false)
    }
  }

  return (
    // Fixo na largura toda, mas com o conteúdo alinhado à coluna do app: no
    // desktop, ancorar em `right-0` jogaria o botão no canto da tela, longe da
    // coluna. `pointer-events-none` no invólucro para a faixa transparente não
    // capturar cliques do que está embaixo.
    <div className="pt-safe pointer-events-none fixed inset-x-0 top-0 z-40">
      <div
        className={cn(
          APP_COLUMN,
          'flex flex-col items-end gap-1 p-3',
          // Da grade para cima o botão acompanha a borda direita do LAYOUT, não a
          // da coluna estreita do celular — senão cai no meio da tela.
          'md:max-w-3xl md:px-6',
          'lg:max-w-5xl lg:px-8',
        )}
      >
        <button
          type="button"
          onClick={() => void act()}
          disabled={busy}
          aria-label={isHost ? 'Encerrar a sala para todos' : 'Sair da sala'}
          className={cn(
            'pointer-events-auto flex min-h-11 items-center gap-2 rounded-full border px-4 text-sm font-semibold backdrop-blur transition-colors',
            confirming
              ? 'border-destructive bg-destructive text-destructive-foreground'
              : 'bg-card/80 text-muted-foreground',
          )}
        >
          {busy ? (
            <Loader2 className="size-4 animate-spin" aria-hidden />
          ) : (
            <DoorOpen className="size-4" aria-hidden />
          )}
          <AnimatePresence mode="wait">
            <motion.span
              key={confirming ? 'confirmar' : 'sair'}
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.12 }}
            >
              {confirming ? 'Encerrar mesmo?' : isHost ? 'Encerrar' : 'Sair'}
            </motion.span>
          </AnimatePresence>
        </button>

        {error && (
          <p role="alert" className="text-destructive max-w-48 text-right text-xs font-medium">
            {error}
          </p>
        )}
      </div>
    </div>
  )
}
