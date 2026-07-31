/**
 * Erros de regra vindos do banco.
 *
 * As funções SQL levantam SQLSTATE próprios (IM001..IM005) com mensagem já em
 * PT-BR. Um erro `IMxxx` é regra do jogo e pode ir direto para a tela; qualquer
 * outro código é falha de infraestrutura e merece mensagem genérica, porque
 * expor "duplicate key value violates unique constraint" ao jogador não ajuda
 * ninguém.
 */

export const GAME_ERROR_CODES = {
  FORBIDDEN: 'IM001',
  WRONG_PHASE: 'IM002',
  NOT_FOUND: 'IM003',
  INVALID_INPUT: 'IM004',
  CONFLICT: 'IM005',
} as const

export type GameErrorCode = (typeof GAME_ERROR_CODES)[keyof typeof GAME_ERROR_CODES]

function isGameRuleCode(code: string | undefined): code is GameErrorCode {
  return typeof code === 'string' && /^IM00[1-5]$/.test(code)
}

/** Erro em formato exibível, vindo de qualquer origem. */
export function toDisplayError(error: unknown): string {
  if (error && typeof error === 'object') {
    const candidate = error as { code?: string; message?: string }

    if (isGameRuleCode(candidate.code) && candidate.message) {
      return candidate.message
    }

    // Anonymous sign-ins desabilitado é o tropeço número 1 no primeiro setup.
    if (candidate.message?.includes('Anonymous sign-ins')) {
      return candidate.message
    }
  }

  if (error instanceof Error && error.message) {
    return error.message
  }

  return 'Algo deu errado. Tente de novo.'
}

/** O erro é uma regra de jogo (e não uma falha técnica)? */
export function isGameRuleError(error: unknown, code?: GameErrorCode): boolean {
  if (!error || typeof error !== 'object') return false
  const candidate = error as { code?: string }
  if (!isGameRuleCode(candidate.code)) return false
  return code ? candidate.code === code : true
}
