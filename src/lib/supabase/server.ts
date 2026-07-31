import { cookies } from 'next/headers'
import { createServerClient } from '@supabase/ssr'
import type { Database } from '@/lib/supabase/database.types'

/**
 * Cliente de servidor para Server Components.
 *
 * Usado só para leitura de shell (existe a sala com este código?). Nenhuma regra
 * de jogo passa por aqui — a autoridade é o Postgres. Ver AGENTS.md, regra 1.
 */
export async function getSupabaseServerClient() {
  // Next 16: cookies() é assíncrono.
  const cookieStore = await cookies()

  return createServerClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll()
        },
        setAll(cookiesToSet) {
          try {
            for (const { name, value, options } of cookiesToSet) {
              cookieStore.set(name, value, options)
            }
          } catch {
            // Server Components não podem escrever cookies. A renovação de sessão
            // acontece no cliente, então ignorar aqui é o comportamento correto.
          }
        },
      },
    },
  )
}
