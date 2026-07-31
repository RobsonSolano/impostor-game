import { act, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { HoldToReveal } from '@/components/shared/HoldToReveal'

const SECRET = 'Hospital'

function renderCard(holdMs = 2000) {
  return render(
    <HoldToReveal holdMs={holdMs}>
      <span>{SECRET}</span>
    </HoldToReveal>,
  )
}

function hold(ms: number) {
  act(() => {
    vi.advanceTimersByTime(ms)
  })
}

describe('HoldToReveal (IMP-07)', () => {
  beforeEach(() => {
    vi.useFakeTimers()
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  it('não coloca o segredo no DOM antes de qualquer toque', () => {
    renderCard()
    // Ausente do DOM, não apenas escondido por CSS: escondido por CSS estaria
    // a um inspetor de distância.
    expect(screen.queryByText(SECRET)).not.toBeInTheDocument()
  })

  it('mantém o segredo oculto durante os primeiros 2 segundos de pressão', () => {
    renderCard(2000)
    fireEvent.pointerDown(screen.getByTestId('hold-to-reveal'))

    hold(1960)
    expect(screen.queryByText(SECRET)).not.toBeInTheDocument()
  })

  it('revela após 2 segundos completos de pressão', () => {
    renderCard(2000)
    fireEvent.pointerDown(screen.getByTestId('hold-to-reveal'))

    hold(2000)
    expect(screen.getByText(SECRET)).toBeInTheDocument()
  })

  it('esconde de volta ao soltar o dedo', () => {
    renderCard(2000)
    const card = screen.getByTestId('hold-to-reveal')

    fireEvent.pointerDown(card)
    hold(2000)
    expect(screen.getByText(SECRET)).toBeInTheDocument()

    fireEvent.pointerUp(card)
    expect(screen.queryByText(SECRET)).not.toBeInTheDocument()
  })

  it('esconde quando o dedo escorrega para fora do card', () => {
    renderCard(2000)
    const card = screen.getByTestId('hold-to-reveal')

    fireEvent.pointerDown(card)
    hold(2000)
    fireEvent.pointerLeave(card)

    expect(screen.queryByText(SECRET)).not.toBeInTheDocument()
  })

  it('esconde quando o toque é cancelado (ligação entrando, por exemplo)', () => {
    renderCard(2000)
    const card = screen.getByTestId('hold-to-reveal')

    fireEvent.pointerDown(card)
    hold(2000)
    fireEvent.pointerCancel(card)

    expect(screen.queryByText(SECRET)).not.toBeInTheDocument()
  })

  it('zera o progresso ao soltar, exigindo os 2 segundos completos de novo', () => {
    renderCard(2000)
    const card = screen.getByTestId('hold-to-reveal')

    // Quase revelou, mas soltou.
    fireEvent.pointerDown(card)
    hold(1800)
    fireEvent.pointerUp(card)

    // Segurar só o tempo que faltava não pode revelar.
    fireEvent.pointerDown(card)
    hold(400)
    expect(screen.queryByText(SECRET)).not.toBeInTheDocument()

    hold(1600)
    expect(screen.getByText(SECRET)).toBeInTheDocument()
  })

  it('não avança o progresso sem pressão nenhuma', () => {
    renderCard(2000)
    hold(5000)
    expect(screen.queryByText(SECRET)).not.toBeInTheDocument()
  })

  it('funciona por teclado, para quem não usa toque', () => {
    renderCard(2000)
    const card = screen.getByTestId('hold-to-reveal')

    fireEvent.keyDown(card, { key: ' ' })
    hold(2000)
    expect(screen.getByText(SECRET)).toBeInTheDocument()

    fireEvent.keyUp(card, { key: ' ' })
    expect(screen.queryByText(SECRET)).not.toBeInTheDocument()
  })

  it('esconde ao perder o foco', () => {
    renderCard(2000)
    const card = screen.getByTestId('hold-to-reveal')

    fireEvent.pointerDown(card)
    hold(2000)
    fireEvent.blur(card)

    expect(screen.queryByText(SECRET)).not.toBeInTheDocument()
  })
})
