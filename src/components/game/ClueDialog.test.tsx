import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { ClueDialog } from '@/components/game/ClueDialog'

// A action é a única dependência externa do popup. O resto (validação de formato,
// contador) é código nosso e roda de verdade no teste.
const submitClue = vi.hoisted(() => vi.fn())
vi.mock('@/lib/game/actions', () => ({ submitClue }))

function renderDialog() {
  return render(
    <ClueDialog
      roomId="sala-1"
      deadline={new Date(Date.now() + 20_000).toISOString()}
      totalMs={20_000}
      onExpire={() => {}}
      onDismiss={() => {}}
      open
    />,
  )
}

const input = () => screen.getByPlaceholderText('ex.: tromba')
const pronto = () => screen.getByRole('button', { name: /pronto/i })

afterEach(() => {
  submitClue.mockReset()
})

describe('ClueDialog — o que o jogador lê (IMP-31 a IMP-34)', () => {
  it('mostra o aviso de não entregar a palavra secreta', () => {
    renderDialog()
    expect(screen.getByText(/não entregar a palavra secreta/i)).toBeInTheDocument()
  })

  it('não deixa enviar com o campo vazio', () => {
    renderDialog()
    expect(pronto()).toBeDisabled()
  })

  it('bloqueia e explica quando são duas palavras', () => {
    renderDialog()
    fireEvent.change(input(), { target: { value: 'dois termos' } })

    expect(pronto()).toBeDisabled()
    expect(screen.getByText(/sem espaços/i)).toBeInTheDocument()
    expect(submitClue).not.toHaveBeenCalled()
  })

  it('aponta o problema específico de cada entrada inválida', () => {
    renderDialog()

    fireEvent.change(input(), { target: { value: 'x1' } })
    expect(screen.getByText(/sem números/i)).toBeInTheDocument()

    fireEvent.change(input(), { target: { value: '-abc' } })
    expect(screen.getByText(/hífen/i)).toBeInTheDocument()

    fireEvent.change(input(), { target: { value: 'a' } })
    expect(screen.getByText(/2 letras/i)).toBeInTheDocument()
  })

  it('libera o envio com uma palavra válida, inclusive com hífen', async () => {
    submitClue.mockResolvedValue({ ok: true, word: 'guarda-chuva' })
    renderDialog()

    fireEvent.change(input(), { target: { value: 'guarda-chuva' } })
    expect(pronto()).toBeEnabled()

    fireEvent.click(pronto())
    await waitFor(() => expect(submitClue).toHaveBeenCalledWith('sala-1', 'guarda-chuva'))
  })

  it('apara espaço das pontas antes de enviar', async () => {
    submitClue.mockResolvedValue({ ok: true, word: 'areia' })
    renderDialog()

    fireEvent.change(input(), { target: { value: '  areia  ' } })
    fireEvent.click(pronto())

    await waitFor(() => expect(submitClue).toHaveBeenCalledWith('sala-1', 'areia'))
  })

  it('mostra a proibição em vermelho quando o banco recusa palavra vulgar', async () => {
    submitClue.mockResolvedValue({ ok: false, reason: 'PROFANITY', strikes: 1, kicked: false })
    renderDialog()

    fireEvent.change(input(), { target: { value: 'palavrao' } })
    fireEvent.click(pronto())

    const alerta = await screen.findByRole('alert')
    expect(alerta).toHaveTextContent(/proibido utilizar palavras vulgares/i)
    expect(alerta).toHaveTextContent(/será expulso da sala/i)
  })

  it('avisa que a próxima falta expulsa, na segunda ocorrência', async () => {
    submitClue.mockResolvedValue({ ok: false, reason: 'PROFANITY', strikes: 2, kicked: false })
    renderDialog()

    fireEvent.change(input(), { target: { value: 'palavrao' } })
    fireEvent.click(pronto())

    expect(await screen.findByText(/na próxima você é expulso/i)).toBeInTheDocument()
  })

  it('limpa o campo depois da recusa, sem fechar o popup — o turno continua', async () => {
    submitClue.mockResolvedValue({ ok: false, reason: 'PROFANITY', strikes: 1, kicked: false })
    renderDialog()

    fireEvent.change(input(), { target: { value: 'palavrao' } })
    fireEvent.click(pronto())

    await screen.findByRole('alert')
    expect(input()).toHaveValue('')
    expect(input()).toBeInTheDocument()
  })

  it('oferece consultar a mesa sem desistir do turno', () => {
    const onDismiss = vi.fn()
    render(
      <ClueDialog
        roomId="sala-1"
        deadline={new Date(Date.now() + 20_000).toISOString()}
        totalMs={20_000}
        onExpire={() => {}}
        onDismiss={onDismiss}
        open
      />,
    )

    fireEvent.click(screen.getByRole('button', { name: /ver as dicas da mesa/i }))
    expect(onDismiss).toHaveBeenCalled()
  })
})
