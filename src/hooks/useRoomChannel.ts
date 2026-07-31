'use client'

import { useEffect, useEffectEvent, useRef, useState } from 'react'
import { getSupabaseBrowserClient } from '@/lib/supabase/client'
import type { Player, Room } from '@/lib/types'

type ChannelState = {
  room: Room | null
  players: Player[]
  /** Carregamento inicial em andamento. */
  loading: boolean
  /** Canal de Realtime ativo. Falso = a tela pode estar desatualizada. */
  connected: boolean
  error: string | null
}

const INITIAL: ChannelState = {
  room: null,
  players: [],
  loading: true,
  connected: false,
  error: null,
}

function sortByJoin(players: Player[]) {
  return [...players].sort((a, b) => a.joined_at.localeCompare(b.joined_at))
}

/**
 * Assina o estado público da sala.
 *
 * Duas subscriptions, um canal: `rooms` (a fase) e `players` (o roster). É tudo
 * que o cliente precisa observar — `player_cards` é buscado por fase em
 * `useMyCard`, e `votes`/`rounds` são inalcançáveis por design.
 *
 * Detalhe que evita bug de sincronia: depois de SUBSCRIBED o estado é buscado de
 * novo. Entre o fetch inicial e o canal ficar pronto existe uma janela em que um
 * UPDATE se perde — sem o refetch, um jogador ficaria preso na fase anterior.
 */
export function useRoomChannel(roomId: string | null) {
  const [state, setState] = useState<ChannelState>(INITIAL)

  // Evita setState depois do unmount quando o fetch termina tarde.
  const mounted = useRef(true)

  /**
   * `useEffectEvent` e não `useCallback`: chamar direto uma função que faz
   * setState no corpo do efeito dispara render em cascata (e o lint reclama, com
   * razão). Effect Event é o escape hatch desenhado para este caso — busca
   * pontual disparada por um efeito.
   */
  const loadRoom = useEffectEvent(async () => {
    if (!roomId) return
    const supabase = getSupabaseBrowserClient()

    const [roomResult, playersResult] = await Promise.all([
      supabase.from('rooms').select('*').eq('id', roomId).maybeSingle(),
      supabase.from('players').select('*').eq('room_id', roomId).order('joined_at'),
    ])

    if (!mounted.current) return

    if (roomResult.error || playersResult.error) {
      setState((prev) => ({ ...prev, loading: false, error: 'Não foi possível carregar a sala.' }))
      return
    }

    setState((prev) => ({
      ...prev,
      room: roomResult.data,
      players: playersResult.data ?? [],
      loading: false,
      error: roomResult.data ? null : 'Sala não encontrada.',
    }))
  })

  useEffect(() => {
    mounted.current = true
    if (!roomId) return

    const supabase = getSupabaseBrowserClient()

    // Carga inicial em microtask, não no corpo do efeito: assim o primeiro
    // setState acontece depois do flush de render, sem cascata. O canal também
    // recarrega em SUBSCRIBED, mas esta chamada é o que garante que a sala apareça
    // mesmo se o WebSocket estiver bloqueado (wi-fi corporativo, extensão).
    void Promise.resolve().then(() => loadRoom())

    const channel = supabase
      .channel(`room:${roomId}`)
      .on(
        'postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'rooms', filter: `id=eq.${roomId}` },
        (payload) => {
          if (!mounted.current) return
          setState((prev) => ({ ...prev, room: payload.new as Room }))
        },
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'players', filter: `room_id=eq.${roomId}` },
        (payload) => {
          if (!mounted.current) return
          setState((prev) => {
            if (payload.eventType === 'DELETE') {
              const gone = payload.old as Partial<Player>
              return { ...prev, players: prev.players.filter((p) => p.id !== gone.id) }
            }

            const incoming = payload.new as Player
            const others = prev.players.filter((p) => p.id !== incoming.id)
            return { ...prev, players: sortByJoin([...others, incoming]) }
          })
        },
      )
      .subscribe((status) => {
        if (!mounted.current) return
        const isConnected = status === 'SUBSCRIBED'
        setState((prev) => ({ ...prev, connected: isConnected }))
        // Fecha a janela entre o fetch inicial e o canal ficar pronto.
        if (isConnected) void loadRoom()
      })

    return () => {
      mounted.current = false
      void supabase.removeChannel(channel)
    }
  }, [roomId])

  return state
}
