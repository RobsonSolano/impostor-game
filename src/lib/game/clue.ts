/**
 * Validação da dica escrita (IMP-32).
 *
 * Espelha `is_valid_clue` no banco. O banco é a autoridade; isto existe para o
 * jogador saber na hora que "dois termos" não vai passar, sem gastar segundos do
 * turno num round-trip.
 *
 * O que NÃO está aqui de propósito:
 *
 * - **Lista de palavrões.** Ela vive só no banco. Trazer para o cliente
 *   duplicaria a lista (dois lugares para manter sincronizados) e exporia o
 *   conteúdo no bundle. O feedback vem do retorno de `submit_clue`, que é rápido
 *   o suficiente.
 * - **Dicionário de português.** Recusaria "Pikachu" e "nerf" no meio de um turno
 *   de 15 segundos. Ver IMP-32.
 */

export const CLUE_MIN_LENGTH = 2
export const CLUE_MAX_LENGTH = 20

/**
 * Um único termo: letras (com acento), hífen só ENTRE letras.
 *
 * `À-ÖØ-öø-ÿ` cobre as letras acentuadas do Latin-1 pulando `×` (U+00D7) e `÷`
 * (U+00F7), que caem no meio da faixa e não são letras.
 */
const CLUE_PATTERN = /^[A-Za-zÀ-ÖØ-öø-ÿ]+(-[A-Za-zÀ-ÖØ-öø-ÿ]+)*$/

/** Apara as pontas. O resto da string é problema da validação. */
export function normalizeClue(raw: string): string {
  return raw.trim()
}

export function isValidClue(raw: string): boolean {
  const clue = normalizeClue(raw)
  return (
    clue.length >= CLUE_MIN_LENGTH &&
    clue.length <= CLUE_MAX_LENGTH &&
    CLUE_PATTERN.test(clue)
  )
}

/**
 * Por que a dica foi recusada, para a tela dizer o que corrigir.
 * `null` = está válida.
 */
export function clueProblem(raw: string): string | null {
  const clue = normalizeClue(raw)

  if (clue.length === 0) return 'Escreva uma palavra.'
  if (/\s/.test(clue)) return 'Só uma palavra — sem espaços.'
  if (clue.length < CLUE_MIN_LENGTH) return 'Pelo menos 2 letras.'
  if (clue.length > CLUE_MAX_LENGTH) return `No máximo ${CLUE_MAX_LENGTH} letras.`
  if (/[0-9]/.test(clue)) return 'Sem números.'
  if (clue.startsWith('-') || clue.endsWith('-')) return 'O hífen vai entre letras.'
  if (!CLUE_PATTERN.test(clue)) return 'Use só letras (hífen é permitido).'

  return null
}
