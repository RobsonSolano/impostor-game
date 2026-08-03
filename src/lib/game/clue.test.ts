import { describe, expect, it } from 'vitest'
import { clueProblem, isValidClue, normalizeClue } from '@/lib/game/clue'

describe('isValidClue (IMP-32)', () => {
  it('aceita palavra simples', () => {
    expect(isValidClue('tromba')).toBe(true)
  })

  it('aceita hífen entre letras', () => {
    expect(isValidClue('guarda-chuva')).toBe(true)
    expect(isValidClue('bem-te-vi')).toBe(true)
  })

  it('aceita acento e maiúscula', () => {
    expect(isValidClue('Pão')).toBe(true)
    expect(isValidClue('ré')).toBe(true)
    expect(isValidClue('ÔNIBUS')).toBe(true)
  })

  it('apara espaço das pontas em vez de recusar', () => {
    expect(isValidClue('  areia  ')).toBe(true)
    expect(normalizeClue('  areia  ')).toBe('areia')
  })

  it('recusa mais de uma palavra', () => {
    expect(isValidClue('dois termos')).toBe(false)
  })

  it('recusa número e símbolo', () => {
    expect(isValidClue('x1')).toBe(false)
    expect(isValidClue('sol!')).toBe(false)
  })

  it('recusa hífen solto nas pontas', () => {
    expect(isValidClue('-abc')).toBe(false)
    expect(isValidClue('abc-')).toBe(false)
    expect(isValidClue('a--b')).toBe(false)
  })

  it('recusa comprimento fora de 2 a 20', () => {
    expect(isValidClue('a')).toBe(false)
    expect(isValidClue('')).toBe(false)
    expect(isValidClue('a'.repeat(21))).toBe(false)
    expect(isValidClue('a'.repeat(20))).toBe(true)
  })

  it('não valida se a palavra existe — decisão consciente de IMP-32', () => {
    // Um dicionário embutido recusaria "Pikachu" e "nerf" no meio de um turno de
    // 15 segundos, e é exatamente esse o vocabulário de quem vai jogar.
    expect(isValidClue('xpto')).toBe(true)
    expect(isValidClue('Pikachu')).toBe(true)
  })

  it('não recusa × nem ÷, que caem no meio da faixa de acentuadas', () => {
    expect(isValidClue('a×b')).toBe(false)
    expect(isValidClue('a÷b')).toBe(false)
  })
})

describe('clueProblem', () => {
  it('não reclama de palavra válida', () => {
    expect(clueProblem('tromba')).toBeNull()
  })

  it('aponta o problema específico, não uma mensagem genérica', () => {
    expect(clueProblem('')).toMatch(/escreva/i)
    expect(clueProblem('dois termos')).toMatch(/espaço/i)
    expect(clueProblem('a')).toMatch(/2 letras/i)
    expect(clueProblem('a'.repeat(21))).toMatch(/20 letras/i)
    expect(clueProblem('x1')).toMatch(/número/i)
    expect(clueProblem('-abc')).toMatch(/hífen/i)
  })
})
