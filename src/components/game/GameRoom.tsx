'use client'

import { useEffect } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { AnimatePresence, motion } from 'motion/react'
import { DoorOpen, Loader2, WifiOff } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { useAnonSession, useRoomIdFromCode } from '@/hooks/useGameAccess'
import { useMyCard } from '@/hooks/useMyCard'
import { useRoomChannel } from '@/hooks/useRoomChannel'
import { LobbyPhase } from '@/components/game/LobbyPhase'
import { WordRevealPhase } from '@/components/game/WordRevealPhase'
import { DiscussionPhase } from '@/components/game/DiscussionPhase'
import { VotingPhase } from '@/components/game/VotingPhase'
import { LastChancePhase } from '@/components/game/LastChancePhase'
import { GameOverPhase } from '@/components/game/GameOverPhase'
import { RoomExitButton } from '@/components/game/RoomExitButton'
import { APP_COLUMN } from '@/components/shared/app-column'

/** Tempo de leitura do aviso antes de mandar todos para a home. */
const CLOSED_REDIRECT_MS = 2200

/**
 * Orquestrador da sala.
 *
 * Uma única rota para a partida inteira: as fases são componentes trocados por
 * `rooms.status`, não navegações. Navegar entre fases derrubaria e recriaria o
 * canal de Realtime a cada transição — o jeito mais fácil de perder um evento e
 * deixar um celular preso na tela anterior.
 */
export function GameRoom({ code }: { code: string }) {
  const { userId, ready, error: sessionError } = useAnonSession()
  const {
    roomId,
    loading: resolvingRoom,
    isMember,
  } = useRoomIdFromCode(code, ready && Boolean(userId))
  const { room, players, loading, connected, error } = useRoomChannel(roomId)

  const me = players.find((player) => player.user_id === userId) ?? null
  const { card } = useMyCard(room?.active_round_id ?? null, me?.id ?? null)

  // O host encerrou: todos voltam para a tela inicial. (IMP-25)
  const isClosed = room?.status === 'CLOSED'

  if (sessionError) {
    return <Fallback title="Não foi possível entrar" detail={sessionError} />
  }

  if (isClosed) {
    return <RoomClosedScreen />
  }

  if (!ready || resolvingRoom || (loading && !room)) {
    return <Spinner />
  }

  if (!isMember || !roomId) {
    return (
      <Fallback
        title="Você não está nesta sala"
        detail={`Para entrar na sala ${code}, informe seu nome na tela inicial.`}
      />
    )
  }

  if (error || !room) {
    return <Fallback title="Sala indisponível" detail={error ?? 'Sala não encontrada.'} />
  }

  // `me` ausente com sala carregada acontece quando a sessão anônima trocou
  // (storage limpo, outro navegador): o jogador antigo continua na sala, mas
  // este usuário não é ele.
  if (!me) {
    return (
      <Fallback
        title="Sessão não reconhecida"
        detail={`Sua sessão não corresponde a nenhum jogador da sala ${code}. Entre de novo pela tela inicial.`}
      />
    )
  }

  const isHost = room.host_player_id === me.id
  const shared = { room, players, me, isHost }

  return (
    <>
      {!connected && <OfflineBanner />}
      <RoomExitButton roomId={room.id} isHost={isHost} />

      {/* `mode="wait"` para a tela nova só entrar depois da anterior sair —
          crossfade de duas fases sobrepostas confunde num jogo de dedução. */}
      <AnimatePresence mode="wait">
        <motion.div
          key={room.status}
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: -12 }}
          transition={{ duration: 0.2 }}
        >
          {room.status === 'LOBBY' && <LobbyPhase {...shared} />}
          {room.status === 'WORD_REVEAL' && <WordRevealPhase {...shared} card={card} />}
          {room.status === 'DISCUSSION' && <DiscussionPhase {...shared} />}
          {room.status === 'VOTING' && <VotingPhase {...shared} />}
          {room.status === 'LAST_CHANCE' && <LastChancePhase {...shared} card={card} />}
          {room.status === 'GAME_OVER' && <GameOverPhase {...shared} />}
        </motion.div>
      </AnimatePresence>
    </>
  )
}

function Spinner() {
  return (
    <div className={"flex min-h-dvh items-center justify-center"}>
      <Loader2 className="text-muted-foreground size-8 animate-spin" aria-label="Carregando" />
    </div>
  )
}

/**
 * Sala encerrada pelo host.
 *
 * Redireciona sozinho, mas com uma pausa: cair na home sem explicação pareceria
 * bug ou queda de conexão. O aviso é o que diferencia "o host encerrou" de
 * "o app quebrou".
 */
function RoomClosedScreen() {
  const router = useRouter()

  useEffect(() => {
    const id = setTimeout(() => router.replace('/'), CLOSED_REDIRECT_MS)
    return () => clearTimeout(id)
  }, [router])

  return (
    <div className={"mx-auto flex min-h-dvh max-w-md flex-col items-center justify-center gap-4 px-6 text-center"}>
      <motion.div
        initial={{ scale: 0.8, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        className="bg-card rounded-3xl border p-5"
      >
        <DoorOpen className="text-muted-foreground size-10" aria-hidden />
      </motion.div>
      <h1 className="text-xl font-bold">O host encerrou a sala</h1>
      <p className="text-muted-foreground text-pretty">Voltando para o início…</p>
      <Button asChild variant="ghost" className="mt-2 h-12">
        <Link href="/">Ir agora</Link>
      </Button>
    </div>
  )
}

function Fallback({ title, detail }: { title: string; detail: string }) {
  return (
    <div className={"mx-auto flex min-h-dvh max-w-md flex-col items-center justify-center gap-4 px-6 text-center"}>
      <h1 className="text-xl font-bold">{title}</h1>
      <p className="text-muted-foreground text-pretty">{detail}</p>
      <Button asChild size="lg" className="mt-2 h-12">
        <Link href="/">Voltar ao início</Link>
      </Button>
    </div>
  )
}

/**
 * Aviso de canal caído.
 *
 * Sem isso o jogador não teria como saber que a tela parou de atualizar — o
 * estado simplesmente congelaria na fase anterior, e ele acharia que o jogo
 * travou.
 */
function OfflineBanner() {
  return (
    <div className={`pt-safe bg-destructive/15 text-destructive fixed inset-x-0 top-0 z-50 flex items-center justify-center gap-2 px-4 py-2 text-sm font-medium backdrop-blur ${APP_COLUMN}`}>
      <WifiOff className="size-4" aria-hidden />
      Reconectando…
    </div>
  )
}
