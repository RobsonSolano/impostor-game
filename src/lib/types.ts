import type { Database } from '@/lib/supabase/database.types'

export type Room = Database['public']['Tables']['rooms']['Row']
export type Player = Database['public']['Tables']['players']['Row']
export type PlayerCard = Database['public']['Tables']['player_cards']['Row']
export type Word = Database['public']['Tables']['words']['Row']
export type RoundClue = Database['public']['Tables']['round_clues']['Row']

export type RoomStatus = Database['public']['Enums']['room_status']
export type GameOutcome = Database['public']['Enums']['game_outcome']
export type WordCategory = Database['public']['Enums']['word_category']

/** Retorno de `create_room` / `join_room`. */
export type JoinResult = {
  room_id: string
  player_id: string
  code: string
}

/**
 * Retorno de `submit_clue`.
 *
 * Palavra vulgar volta com `ok: false` em vez de exceção: exceção em plpgsql
 * desfaria a transação e o contador de faltas voltaria a zero. Ver IMP-34.
 */
export type ClueResult = {
  ok: boolean
  reason?: 'PROFANITY'
  strikes?: number
  kicked?: boolean
  word?: string
}

/** Retorno de `submit_impostor_guess`. */
export type GuessResult = {
  correct: boolean
  word: string
}

/** `rooms.last_vote_tally` — gravado pela apuração, nunca antes dela. */
export type VoteTally = {
  cycle: number
  skip: number
  top: number
  players: Record<string, number>
}

export const CATEGORY_LABELS: Record<WordCategory, string> = {
  LUGARES: 'Lugares & Ambientes',
  COMIDAS: 'Comidas & Bebidas',
  ANIMAIS: 'Animais',
  PROFISSOES: 'Profissões',
  OBJETOS: 'Objetos do Cotidiano',
  TECH: 'Tech & Geek',
  ESPORTES: 'Esportes & Lazer',
  CULTURA_POP: 'Cultura Pop',
  TRANSPORTES: 'Transportes & Viagem',
  EVENTOS: 'Eventos & Situações',
}

export const OUTCOME_LABELS: Record<GameOutcome, string> = {
  TRUTHERS_WIN: 'Os verdadeiros venceram!',
  IMPOSTOR_WIN: 'O impostor venceu!',
  IMPOSTOR_STEAL: 'O impostor roubou a vitória!',
}
