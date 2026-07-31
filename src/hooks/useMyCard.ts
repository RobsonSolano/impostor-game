'use client'

import { useEffect, useState } from 'react'
import { getSupabaseBrowserClient } from '@/lib/supabase/client'
import type { PlayerCard } from '@/lib/types'

type CardState = {
  /** Rodada a que o card carregado pertence. */
  roundId: string | null
  card: PlayerCard | null
}

/**
 * Busca o card secreto do jogador atual.
 *
 * Sem Realtime de propósito: o gatilho é a mudança de `rooms.active_round_id`,
 * que já chega pela subscription de `rooms`. Uma terceira subscription só
 * adicionaria superfície de RLS-em-Realtime sem ganho nenhum.
 *
 * O card é guardado junto com o id da rodada e descartado por COMPARAÇÃO, não por
 * limpeza. A cada "Jogar Novamente" nasce uma rodada nova, e mostrar a palavra da
 * partida anterior por um frame seria pior que não mostrar nada.
 */
export function useMyCard(roundId: string | null, playerId: string | null) {
  const [state, setState] = useState<CardState>({ roundId: null, card: null })

  useEffect(() => {
    if (!roundId || !playerId) return

    let active = true

    void (async () => {
      const supabase = getSupabaseBrowserClient()
      const { data } = await supabase
        .from('player_cards')
        .select('*')
        .eq('round_id', roundId)
        .eq('player_id', playerId)
        .maybeSingle()

      if (!active) return
      setState({ roundId, card: data ?? null })
    })()

    return () => {
      active = false
    }
  }, [roundId, playerId])

  const isCurrent = state.roundId === roundId

  return {
    card: isCurrent ? state.card : null,
    loading: Boolean(roundId && playerId) && !isCurrent,
  }
}
