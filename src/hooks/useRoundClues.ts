'use client'

import { useEffect, useEffectEvent, useRef, useState } from 'react'
import { getSupabaseBrowserClient } from '@/lib/supabase/client'
import { useKeepFresh } from '@/hooks/useKeepFresh'
import type { RoundClue } from '@/lib/types'

type CluesState = {
  /** Rodada a que as dicas carregadas pertencem. */
  roundId: string | null
  clues: RoundClue[]
}

const EMPTY: RoundClue[] = []

function sameClue(a: Partial<RoundClue>, b: Partial<RoundClue>) {
  return a.player_id === b.player_id && a.discussion_round === b.discussion_round
}

function sortByTurn(clues: RoundClue[]) {
  return [...clues].sort(
    (a, b) => a.discussion_round - b.discussion_round || a.turn_index - b.turn_index,
  )
}

/**
 * Assina a ordem de fala e as dicas da rodada. (IMP-30, IMP-35)
 *
 * Traz TODAS as rodadas de dica da partida, não só a atual: quando o host começa
 * uma rodada nova, as dicas anteriores continuam visíveis — é sobre o acumulado
 * que a mesa desconfia (IMP-37).
 *
 * Diferente de `player_cards`, aqui vale Realtime: a dica de um jogador tem que
 * aparecer no celular dos outros no instante em que ele toca "Pronto".
 *
 * As dicas são guardadas junto do id da rodada e descartadas por COMPARAÇÃO, não
 * por limpeza dentro do efeito. Limpar ali dispara render em cascata, e mostrar as
 * dicas da partida anterior por um frame seria pior que não mostrar nada.
 */
export function useRoundClues(roundId: string | null) {
  const [state, setState] = useState<CluesState>({ roundId: null, clues: [] })

  // Mesma rede de segurança da sala: se o evento da ordem sorteada se perde,
  // ninguém descobre de quem é a vez. Ver useKeepFresh.
  const freshness = useKeepFresh(Boolean(roundId))
  const mounted = useRef(true)

  const loadClues = useEffectEvent(async () => {
    if (!roundId) return
    const supabase = getSupabaseBrowserClient()

    const { data } = await supabase
      .from('round_clues')
      .select('*')
      .eq('round_id', roundId)
      .order('discussion_round')
      .order('turn_index')

    if (!mounted.current) return
    setState({ roundId, clues: data ?? [] })
  })

  /** Aplica um evento de Realtime, ignorando o que não é da rodada carregada. */
  const applyChange = useEffectEvent(
    (eventType: 'INSERT' | 'UPDATE' | 'DELETE', row: Partial<RoundClue>) => {
      if (!mounted.current) return

      setState((prev) => {
        if (prev.roundId !== roundId) return prev

        if (eventType === 'DELETE') {
          return { roundId, clues: prev.clues.filter((c) => !sameClue(c, row)) }
        }

        const incoming = row as RoundClue
        const others = prev.clues.filter((c) => !sameClue(c, incoming))
        return { roundId, clues: sortByTurn([...others, incoming]) }
      })
    },
  )

  useEffect(() => {
    mounted.current = true
    if (!roundId) return

    const supabase = getSupabaseBrowserClient()

    // Microtask: o primeiro setState não acontece no corpo do efeito.
    void Promise.resolve().then(() => loadClues())

    const channel = supabase
      .channel(`clues:${roundId}`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'round_clues',
          filter: `round_id=eq.${roundId}`,
        },
        (payload) => {
          applyChange(
            payload.eventType,
            (payload.eventType === 'DELETE' ? payload.old : payload.new) as Partial<RoundClue>,
          )
        },
      )
      .subscribe((status) => {
        // Fecha a janela entre o fetch inicial e o canal ficar pronto: sem isto,
        // uma dica enviada nesse intervalo não apareceria até a mudança seguinte.
        if (status === 'SUBSCRIBED') void loadClues()
      })

    return () => {
      mounted.current = false
      void supabase.removeChannel(channel)
    }
  }, [roundId])

  useEffect(() => {
    if (!roundId || freshness === 0) return
    void Promise.resolve().then(() => loadClues())
  }, [roundId, freshness])

  return state.roundId === roundId ? state.clues : EMPTY
}
