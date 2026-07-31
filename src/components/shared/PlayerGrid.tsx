import { Crown, Check } from 'lucide-react'
import { PlayerAvatar } from '@/components/shared/PlayerAvatar'
import { cn } from '@/lib/utils'
import type { Player } from '@/lib/types'

type PlayerGridProps = {
  players: Player[]
  hostPlayerId?: string | null
  myPlayerId?: string | null
  /** Ids com marca de "pronto" (viu o card, já votou...). */
  readyIds?: Set<string>
  readyLabel?: string
  showScore?: boolean
}

/**
 * Roster da mesa.
 *
 * Uma coluna no celular (nome inteiro sempre legível) e no desktop (onde a mesa
 * fica numa lateral estreita). No tablet vira linha com wrap: ali existe largura
 * de sobra, e um jogador por linha desperdiçaria a tela inteira à direita.
 */
export function PlayerGrid({
  players,
  hostPlayerId,
  myPlayerId,
  readyIds,
  readyLabel = 'pronto',
  showScore = false,
}: PlayerGridProps) {
  return (
    <ul className="flex flex-col gap-2 md:flex-row md:flex-wrap lg:flex-col">
      {players.map((player) => {
        const isReady = readyIds?.has(player.id) ?? false

        return (
          <li
            key={player.id}
            className={cn(
              'bg-card flex items-center gap-3 rounded-2xl border p-3',
              // Na linha com wrap do tablet: piso de largura para todos ficarem do
              // mesmo tamanho, e `shrink-0` para nome grande empurrar o item para a
              // linha de baixo em vez de comprimir os vizinhos. O padrão do flex é
              // `shrink: 1`, que era o que estava encurtando os nomes.
              'md:min-w-52 md:shrink-0 lg:min-w-0',
              player.id === myPlayerId && 'border-primary/50',
              !player.is_alive && 'opacity-40',
            )}
          >
            <PlayerAvatar player={player} size="md" />

            {/* `flex-1` empurra coroa e selos para a borda direita do item, o que
                mantém o alinhamento igual em todos os cards da linha. */}
            <div className="min-w-0 flex-1">
              <p className="truncate font-semibold">
                {player.name}
                {player.id === myPlayerId && (
                  <span className="text-muted-foreground ml-2 text-sm font-normal">(você)</span>
                )}
              </p>
              {showScore && (
                <p className="text-muted-foreground tabular text-sm">
                  {player.score} {player.score === 1 ? 'ponto' : 'pontos'}
                </p>
              )}
            </div>

            {player.id === hostPlayerId && (
              <Crown className="text-warn size-4 shrink-0" aria-label="Host" />
            )}

            {isReady && (
              <span className="text-primary flex shrink-0 items-center gap-1 text-sm font-semibold">
                <Check className="size-4" aria-hidden />
                {readyLabel}
              </span>
            )}
          </li>
        )
      })}
    </ul>
  )
}
