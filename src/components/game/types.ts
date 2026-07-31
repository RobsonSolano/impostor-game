import type { Player, Room } from '@/lib/types'

/** Contrato comum de toda tela de fase. */
export type PhaseProps = {
  room: Room
  players: Player[]
  /** O jogador desta sessão. Garantido não-nulo pelo `GameRoom`. */
  me: Player
  isHost: boolean
}
