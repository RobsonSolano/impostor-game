'use client'

import { useEffect, useState } from 'react'

/** Intervalo do backstop. Uma linha de `rooms` é minúscula; o custo é irrelevante. */
const POLL_MS = 8_000

/**
 * Sinal de "hora de ressincronizar", como rede de segurança contra evento de
 * Realtime perdido.
 *
 * ORIGEM: partida real travada (sala TQAK). O jogo começou, os três confirmaram o
 * card, o banco moveu a sala para DISCUSSION e sorteou a ordem — e nenhum celular
 * saiu da tela do card. Ninguém foi chamado para escrever, e o prazo ficou vencido
 * para sempre porque nenhum cliente estava na tela que dispara
 * `expire_clue_turn`. Dois dos jogadores estavam no lobby havia 15 minutos: tela
 * bloqueada, aba em segundo plano, WebSocket morto.
 *
 * O app dependia SÓ de Realtime depois da carga inicial, então um evento perdido
 * congelava a tela sem saída — a não ser recarregar a página, o que ninguém pensa
 * em fazer no meio de um jogo.
 *
 * Três gatilhos, do mais preciso ao mais genérico:
 *
 * 1. **Voltar a ficar visível** — celular desbloqueado, aba retomada. É o caso
 *    exato do travamento, e o mais barato: sincroniza no instante em que a pessoa
 *    olha a tela.
 * 2. **Rede de volta** (`online`) — wi-fi caiu e voltou.
 * 3. **Sondagem periódica** enquanto visível — o caso cruel do socket zumbi, que
 *    não reporta erro nenhum e simplesmente para de entregar. Sem isto, nenhum dos
 *    dois gatilhos acima chega a disparar.
 *
 * Só sonda com a aba visível: sondar em segundo plano gasta bateria para atualizar
 * uma tela que ninguém está olhando — e o gatilho 1 cobre a volta.
 *
 * Devolve um contador em vez de receber a função de recarga porque um Effect Event
 * não pode ser passado para outro hook. Quem chama reage à mudança do contador com
 * o próprio efeito.
 */
export function useKeepFresh(enabled: boolean): number {
  const [tick, setTick] = useState(0)

  useEffect(() => {
    if (!enabled) return

    const bump = () => {
      if (typeof document !== 'undefined' && document.visibilityState !== 'visible') return
      setTick((n) => n + 1)
    }

    document.addEventListener('visibilitychange', bump)
    window.addEventListener('online', bump)
    window.addEventListener('focus', bump)
    const id = setInterval(bump, POLL_MS)

    return () => {
      document.removeEventListener('visibilitychange', bump)
      window.removeEventListener('online', bump)
      window.removeEventListener('focus', bump)
      clearInterval(id)
    }
  }, [enabled])

  return tick
}
