/**
 * Código de sala.
 *
 * O alfabeto exclui I, O, 0 e 1 porque o código é lido em voz alta na mesa e
 * digitado à mão em teclado de celular. Espelha `rooms_code_alphabet_chk` e
 * `gen_room_code()` no banco — se um mudar, o outro tem que mudar junto.
 */
export const ROOM_CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
export const ROOM_CODE_LENGTH = 4

/**
 * Normaliza o que o jogador digitou: maiúsculas, sem espaços nem separadores,
 * e sem os caracteres que o alfabeto não usa.
 *
 * Não valida — só limpa. Serve para o `onChange` do input, onde rejeitar
 * enquanto a pessoa digita seria hostil.
 */
export function normalizeRoomCode(raw: string): string {
  return raw
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, '')
    .split('')
    .filter((char) => ROOM_CODE_ALPHABET.includes(char))
    .join('')
    .slice(0, ROOM_CODE_LENGTH)
}

/** Um código completo e válido? Usado para habilitar o botão de entrar. */
export function isValidRoomCode(raw: string): boolean {
  const normalized = normalizeRoomCode(raw)
  return normalized.length === ROOM_CODE_LENGTH
}

/** Nome de jogador: limites iguais aos de `players_name_len_chk`. */
export const NICKNAME_MAX_LENGTH = 20

export function normalizeNickname(raw: string): string {
  return raw.replace(/\s+/g, ' ').trim().slice(0, NICKNAME_MAX_LENGTH)
}

export function isValidNickname(raw: string): boolean {
  const normalized = normalizeNickname(raw)
  return normalized.length >= 1 && normalized.length <= NICKNAME_MAX_LENGTH
}
