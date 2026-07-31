import { describe, expect, it } from 'vitest'
import {
  ROOM_CODE_ALPHABET,
  isValidNickname,
  isValidRoomCode,
  normalizeNickname,
  normalizeRoomCode,
} from '@/lib/game/room-code'

describe('normalizeRoomCode', () => {
  it('coloca em maiúsculas', () => {
    expect(normalizeRoomCode('x9k2')).toBe('X9K2')
  })

  it('remove espaços e separadores que a pessoa digita sem perceber', () => {
    expect(normalizeRoomCode(' x9-k2 ')).toBe('X9K2')
  })

  it('descarta os caracteres ambíguos que o alfabeto não usa', () => {
    // I, O, 0 e 1 não existem no alfabeto: quem digitar cai fora.
    expect(normalizeRoomCode('IO01')).toBe('')
    expect(normalizeRoomCode('AIBO')).toBe('AB')
  })

  it('corta em 4 caracteres', () => {
    expect(normalizeRoomCode('ABCDEFGH')).toBe('ABCD')
  })

  it('aceita todo caractere do alfabeto do banco', () => {
    for (const char of ROOM_CODE_ALPHABET) {
      expect(normalizeRoomCode(char)).toBe(char)
    }
  })
})

describe('isValidRoomCode', () => {
  it('exige os 4 caracteres completos', () => {
    expect(isValidRoomCode('X9K')).toBe(false)
    expect(isValidRoomCode('X9K2')).toBe(true)
  })

  it('recusa código que só tinha caracteres ambíguos', () => {
    expect(isValidRoomCode('IO01')).toBe(false)
  })

  it('aceita entrada suja que normaliza para 4 caracteres', () => {
    expect(isValidRoomCode(' x9-k2 ')).toBe(true)
  })
})

describe('normalizeNickname', () => {
  it('remove espaços das pontas', () => {
    expect(normalizeNickname('  Robson  ')).toBe('Robson')
  })

  it('colapsa espaços internos', () => {
    expect(normalizeNickname('Ana   Maria')).toBe('Ana Maria')
  })

  it('corta em 20 caracteres, como players_name_len_chk', () => {
    expect(normalizeNickname('A'.repeat(30))).toHaveLength(20)
  })
})

describe('isValidNickname', () => {
  it('recusa nome vazio ou só de espaços', () => {
    expect(isValidNickname('')).toBe(false)
    expect(isValidNickname('   ')).toBe(false)
  })

  it('aceita nome comum', () => {
    expect(isValidNickname('Robson')).toBe(true)
  })

  it('aceita nome longo porque o corte acontece na normalização', () => {
    expect(isValidNickname('A'.repeat(50))).toBe(true)
    expect(normalizeNickname('A'.repeat(50))).toHaveLength(20)
  })
})
