import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { CluePhase } from '@/components/game/CluePhase'
import type { Player, Room, RoundClue } from '@/lib/types'

/**
 * O empate precisa ser LEGÍVEL. (IMP-13)
 *
 * Origem: sala XMQQ. A mesa votou duas vezes, deu 2 a 2 nas duas, e a regra
 * devolveu para as dicas — comportamento correto. Só que o aviso ficava no fim do
 * conteúdo, fora da tela no celular, e a família concluiu que o app tinha
 * quebrado. Estes testes prendem a explicação na tela.
 */

const room = (over: Partial<Room> = {}): Room =>
  ({
    id: 'sala',
    code: 'XMQQ',
    status: 'DISCUSSION',
    host_player_id: 'p1',
    discussion_round: 2,
    voting_cycle: 1,
    votes_cast: 0,
    games_played: 0,
    clue_turn_index: 0,
    turn_deadline: new Date(Date.now() + 20_000).toISOString(),
    guess_deadline: null,
    active_round_id: 'r1',
    eliminated_player_id: null,
    revealed_word: null,
    revealed_impostor_id: null,
    outcome: null,
    last_vote_tally: null,
    created_at: '',
    updated_at: '',
    ...over,
  }) as Room

const player = (id: string, name: string): Player =>
  ({
    id,
    name,
    room_id: 'sala',
    user_id: `u-${id}`,
    avatar_color: '#39ff14',
    is_alive: true,
    score: 0,
    has_seen_card: true,
    has_voted: false,
    profanity_strikes: 0,
    joined_at: '2026-01-01',
  }) as Player

const players = [player('p1', 'Papai'), player('p2', 'mamãe'), player('p3', 'Heitorzinho')]

const clues: RoundClue[] = players.map((p, i) => ({
  round_id: 'r1',
  discussion_round: 2,
  player_id: p.id,
  turn_index: i,
  word: null,
  timed_out: false,
  submitted_at: null,
}))

function renderFase(tally: unknown, discussionRound = 2) {
  return render(
    <CluePhase
      room={room({ last_vote_tally: tally as never, discussion_round: discussionRound })}
      players={players}
      me={players[0]}
      isHost
      clues={clues.map((c) => ({ ...c, discussion_round: discussionRound }))}
    />,
  )
}

describe('CluePhase — explicar por que a mesa voltou às dicas', () => {
  it('anuncia o empate com os nomes e a contagem', () => {
    // Foi exatamente o placar da sala XMQQ: mamãe 2, Heitorzinho 2.
    renderFase({ cycle: 1, skip: 0, top: 2, players: { p2: 2, p3: 2 } })

    expect(screen.getByText(/deu empate na votação/i)).toBeInTheDocument()
    expect(screen.getByText(/mamãe 2/)).toBeInTheDocument()
    expect(screen.getByText(/Heitorzinho 2/)).toBeInTheDocument()
    expect(screen.getByText(/ninguém foi eliminado/i)).toBeInTheDocument()
  })

  it('anuncia quando a mesa preferiu pular', () => {
    renderFase({ cycle: 1, skip: 3, top: 1, players: { p2: 1 } })

    expect(screen.getByText(/preferiu pular/i)).toBeInTheDocument()
    expect(screen.getByText(/3 votos para pular/i)).toBeInTheDocument()
  })

  it('explica também no subtítulo, para quem não rola a tela', () => {
    renderFase({ cycle: 1, skip: 0, top: 2, players: { p2: 2, p3: 2 } })
    expect(screen.getByText(/não decidiu nada/i)).toBeInTheDocument()
  })

  it('não inventa aviso na primeira rodada, quando não houve votação', () => {
    renderFase(null, 1)
    expect(screen.queryByText(/deu empate/i)).not.toBeInTheDocument()
    expect(screen.queryByText(/ninguém foi eliminado/i)).not.toBeInTheDocument()
  })

  it('aparece ANTES do quadro de dicas — no celular, embaixo é fora da tela', () => {
    const { container } = renderFase({ cycle: 1, skip: 0, top: 2, players: { p2: 2, p3: 2 } })

    const texto = container.textContent ?? ''
    expect(texto.indexOf('Deu empate')).toBeGreaterThan(-1)
    expect(texto.indexOf('Deu empate')).toBeLessThan(texto.indexOf('Papai'))
  })
})
