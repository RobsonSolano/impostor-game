'use client'

import { createBrowserClient } from '@supabase/ssr'
import type { Database } from '@/lib/supabase/database.types'

/**
 * Cliente de browser, singleton.
 *
 * Singleton importa: cada `createBrowserClient` instancia um GoTrue próprio, e
 * dois deles competindo pelo mesmo storage de sessão produzem logout aleatório
 * no meio da partida.
 */
let cached: ReturnType<typeof createBrowserClient<Database>> | null = null

export function getSupabaseBrowserClient() {
  if (!cached) {
    cached = createBrowserClient<Database>(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    )
  }
  return cached
}

/** A sessão guardada já foi conferida contra o servidor nesta carga de página? */
let sessionValidated = false

async function createAnonSession() {
  const supabase = getSupabaseBrowserClient()
  const { data, error } = await supabase.auth.signInAnonymously()
  if (error) {
    throw new Error(
      'Não foi possível criar uma sessão anônima. Confirme que "Anonymous sign-ins" ' +
        `está habilitado no painel do Supabase. (${error.message})`,
    )
  }
  sessionValidated = true
  return data.session
}

/**
 * Garante uma identidade antes de qualquer RPC.
 *
 * Toda função de jogo começa com `require_uid()`, então sem sessão nada funciona.
 * `signInAnonymously()` exige *Anonymous sign-ins* habilitado no painel do
 * Supabase — sem isso a chamada volta 422 e ninguém entra em sala.
 *
 * A sessão guardada é conferida com `getUser()`, que consulta o servidor, e não
 * apenas com `getSession()`, que só lê o cookie. Um JWT pode ter assinatura
 * válida e prazo em aberto apontando para um usuário que não existe mais (banco
 * recriado, usuários podados). `getSession()` aceita esse token, e o jogador
 * recebe um erro de foreign key em `players_user_id_fkey` que NUNCA se resolve
 * tentando de novo — porque a sessão ruim continua no cookie. Aqui a sessão
 * inválida é descartada e uma nova nasce na hora.
 *
 * O custo é uma chamada extra por carga de página: depois da primeira conferência
 * o resultado fica em cache.
 */
export async function ensureAnonSession() {
  const supabase = getSupabaseBrowserClient()

  const { data } = await supabase.auth.getSession()
  if (!data.session) return createAnonSession()

  if (sessionValidated) return data.session

  const { error } = await supabase.auth.getUser()
  if (!error) {
    sessionValidated = true
    return data.session
  }

  await supabase.auth.signOut()
  return createAnonSession()
}
