'use client'

import { useEffect, useState } from 'react'
import { ensureAnonSession, getSupabaseBrowserClient } from '@/lib/supabase/client'
import { toDisplayError } from '@/lib/game/errors'

/**
 * Garante a sessão anônima e devolve o `auth.uid()`.
 *
 * É pré-requisito de tudo: as RPCs começam com `require_uid()`.
 */
export function useAnonSession() {
  const [userId, setUserId] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [ready, setReady] = useState(false)

  useEffect(() => {
    let active = true

    void (async () => {
      try {
        const session = await ensureAnonSession()
        if (!active) return
        setUserId(session?.user.id ?? null)
      } catch (err) {
        if (!active) return
        setError(toDisplayError(err))
      } finally {
        if (active) setReady(true)
      }
    })()

    return () => {
      active = false
    }
  }, [])

  return { userId, ready, error }
}

/**
 * Resolve o código digitado na URL para o id da sala.
 *
 * A policy de `rooms` é "sou jogador desta sala", então esta busca por código só
 * retorna algo para quem já entrou via `join_room`. Zero resultado com sessão
 * válida significa "você não está nesta sala" — não "sala inexistente" — e é
 * exatamente a distinção que a tela precisa fazer.
 */
export function useRoomIdFromCode(code: string, enabled: boolean) {
  const [roomId, setRoomId] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [isMember, setIsMember] = useState(true)

  useEffect(() => {
    if (!enabled) return

    let active = true
    // Sem `setLoading(true)` aqui: o estado inicial já é `true` e `enabled` só
    // transita false→true uma vez (quando a sessão anônima fica pronta).
    // Reafirmar o valor no corpo do efeito só causaria render em cascata.

    void (async () => {
      const supabase = getSupabaseBrowserClient()
      const { data } = await supabase
        .from('rooms')
        .select('id')
        .eq('code', code.toUpperCase())
        .maybeSingle()

      if (!active) return
      setRoomId(data?.id ?? null)
      setIsMember(Boolean(data))
      setLoading(false)
    })()

    return () => {
      active = false
    }
  }, [code, enabled])

  return { roomId, loading, isMember }
}
