'use client'

import { ensureAnonSession, getSupabaseBrowserClient } from '@/lib/supabase/client'
import type { ClueResult, GuessResult, JoinResult } from '@/lib/types'

/**
 * Ações do jogo.
 *
 * Camada fina de propósito: cada função aqui é uma chamada de RPC e nada mais.
 * Nenhuma valida regra, nenhuma decide resultado — isso é do Postgres. Se um dia
 * aparecer um `if` de regra de jogo neste arquivo, é sinal de que a autoridade
 * escapou do banco. Ver AGENTS.md, regra 1.
 */

/**
 * Desembrulha `{ data, error }` e converte erro em throw.
 *
 * `PromiseLike` e não `Promise`: o builder do PostgREST é thenable mas não é uma
 * Promise de verdade (não tem `catch`/`finally`).
 */
async function callRpc<T>(builder: PromiseLike<{ data: T; error: unknown }>): Promise<T> {
  const { data, error } = await builder
  if (error) throw error
  return data
}

export async function createRoom(name: string): Promise<JoinResult> {
  await ensureAnonSession()
  const supabase = getSupabaseBrowserClient()
  const data = await callRpc(supabase.rpc('create_room', { p_name: name }))
  return data as unknown as JoinResult
}

export async function joinRoom(code: string, name: string): Promise<JoinResult> {
  await ensureAnonSession()
  const supabase = getSupabaseBrowserClient()
  const data = await callRpc(supabase.rpc('join_room', { p_code: code, p_name: name }))
  return data as unknown as JoinResult
}

export async function startGame(roomId: string): Promise<void> {
  const supabase = getSupabaseBrowserClient()
  await callRpc(supabase.rpc('start_game', { p_room_id: roomId }))
}

export async function confirmWordSeen(roomId: string): Promise<void> {
  const supabase = getSupabaseBrowserClient()
  await callRpc(supabase.rpc('confirm_word_seen', { p_room_id: roomId }))
}

export async function openVoting(roomId: string): Promise<void> {
  const supabase = getSupabaseBrowserClient()
  await callRpc(supabase.rpc('open_voting', { p_room_id: roomId }))
}

/** `targetPlayerId` nulo = "Pular Votação". */
export async function castVote(roomId: string, targetPlayerId: string | null): Promise<void> {
  const supabase = getSupabaseBrowserClient()
  await callRpc(
    supabase.rpc('cast_vote', {
      p_room_id: roomId,
      p_target_player_id: targetPlayerId ?? undefined,
    }),
  )
}

/**
 * Envia a dica do turno. (IMP-32 a IMP-35)
 *
 * Não lança em caso de palavra vulgar: volta `{ ok: false, reason: 'PROFANITY' }`
 * com a contagem de faltas, porque o banco precisa PERSISTIR a falta — exceção
 * desfaria o incremento junto com a transação.
 */
export async function submitClue(roomId: string, word: string): Promise<ClueResult> {
  const supabase = getSupabaseBrowserClient()
  const data = await callRpc(supabase.rpc('submit_clue', { p_room_id: roomId, p_word: word }))
  return data as unknown as ClueResult
}

/** Fecha o turno cujo prazo venceu. Idempotente no banco. (IMP-36) */
export async function expireClueTurn(roomId: string): Promise<void> {
  const supabase = getSupabaseBrowserClient()
  await callRpc(supabase.rpc('expire_clue_turn', { p_room_id: roomId }))
}

/**
 * Larga a rodada de dicas depois do anúncio de votação indecisa. (IMP-39)
 *
 * Chamada por qualquer cliente cujo contador de 10s zerou. Idempotente no banco,
 * então todos chamando é inofensivo.
 */
export async function startClueRoundNow(roomId: string): Promise<void> {
  const supabase = getSupabaseBrowserClient()
  await callRpc(supabase.rpc('start_clue_round_now', { p_room_id: roomId }))
}

/** Nova rodada de dicas, mantendo as anteriores visíveis. Só o host. (IMP-37) */
export async function nextClueRound(roomId: string): Promise<void> {
  const supabase = getSupabaseBrowserClient()
  await callRpc(supabase.rpc('next_clue_round', { p_room_id: roomId }))
}

export async function submitGuess(roomId: string, word: string): Promise<GuessResult> {
  const supabase = getSupabaseBrowserClient()
  const data = await callRpc(
    supabase.rpc('submit_impostor_guess', { p_room_id: roomId, p_word_text: word }),
  )
  return data as unknown as GuessResult
}

/**
 * Finaliza a Última Chance quando o prazo vence.
 *
 * Chamada por qualquer cliente cujo timer local zerou — o Postgres não dispara
 * nada sozinho. Idempotente no banco, então várias chamadas simultâneas produzem
 * um único resultado. Ver CONCERNS.md #3.
 */
export async function expireLastChance(roomId: string): Promise<void> {
  const supabase = getSupabaseBrowserClient()
  await callRpc(supabase.rpc('expire_last_chance', { p_room_id: roomId }))
}

export async function playAgain(roomId: string): Promise<void> {
  const supabase = getSupabaseBrowserClient()
  await callRpc(supabase.rpc('play_again', { p_room_id: roomId }))
}

/**
 * Sai da sala.
 *
 * Se quem chama é o host, o banco converte isso em `close_room` e a sala termina
 * para todos — a decisão é lá, não aqui. Ver IMP-25.
 */
export async function leaveRoom(roomId: string): Promise<void> {
  const supabase = getSupabaseBrowserClient()
  await callRpc(supabase.rpc('leave_room', { p_room_id: roomId }))
}

/** Encerra a sala para todos. Só o host. */
export async function closeRoom(roomId: string): Promise<void> {
  const supabase = getSupabaseBrowserClient()
  await callRpc(supabase.rpc('close_room', { p_room_id: roomId }))
}
