import { act, renderHook } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { useKeepFresh } from '@/hooks/useKeepFresh'

/** `visibilityState` é somente-leitura; o teste precisa forçá-la. */
function setVisibility(state: 'visible' | 'hidden') {
  Object.defineProperty(document, 'visibilityState', {
    configurable: true,
    get: () => state,
  })
  document.dispatchEvent(new Event('visibilitychange'))
}

describe('useKeepFresh — rede de segurança contra evento de Realtime perdido', () => {
  beforeEach(() => {
    vi.useFakeTimers()
    setVisibility('visible')
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  it('não sinaliza nada antes de qualquer gatilho', () => {
    const { result } = renderHook(() => useKeepFresh(true))
    expect(result.current).toBe(0)
  })

  it('sinaliza quando a aba volta a ficar visível — o caso do celular desbloqueado', () => {
    const { result } = renderHook(() => useKeepFresh(true))

    act(() => setVisibility('hidden'))
    const escondido = result.current

    act(() => setVisibility('visible'))
    expect(result.current).toBeGreaterThan(escondido)
  })

  it('não sinaliza enquanto a aba está escondida', () => {
    const { result } = renderHook(() => useKeepFresh(true))

    act(() => setVisibility('hidden'))
    const antes = result.current

    // Sondar em segundo plano só gastaria bateria: ninguém está olhando.
    act(() => {
      vi.advanceTimersByTime(60_000)
    })
    expect(result.current).toBe(antes)
  })

  it('sonda periodicamente com a aba visível — pega o socket zumbi, que não reporta erro', () => {
    const { result } = renderHook(() => useKeepFresh(true))

    act(() => {
      vi.advanceTimersByTime(8_000)
    })
    expect(result.current).toBe(1)

    act(() => {
      vi.advanceTimersByTime(8_000)
    })
    expect(result.current).toBe(2)
  })

  it('sinaliza quando a rede volta', () => {
    const { result } = renderHook(() => useKeepFresh(true))
    const antes = result.current

    act(() => {
      window.dispatchEvent(new Event('online'))
    })
    expect(result.current).toBeGreaterThan(antes)
  })

  it('fica quieto quando desabilitado — sem sala, não há o que sincronizar', () => {
    const { result } = renderHook(() => useKeepFresh(false))

    act(() => {
      vi.advanceTimersByTime(60_000)
      window.dispatchEvent(new Event('online'))
      setVisibility('visible')
    })
    expect(result.current).toBe(0)
  })

  it('para de sondar depois do unmount', () => {
    const { result, unmount } = renderHook(() => useKeepFresh(true))

    act(() => {
      vi.advanceTimersByTime(8_000)
    })
    const antes = result.current

    unmount()

    act(() => {
      vi.advanceTimersByTime(60_000)
    })
    expect(result.current).toBe(antes)
  })
})
