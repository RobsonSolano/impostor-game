import { cn } from '@/lib/utils'
import type { Player } from '@/lib/types'

const SIZES = {
  sm: 'size-8 text-sm',
  md: 'size-12 text-lg',
  lg: 'size-16 text-2xl',
} as const

type PlayerAvatarProps = {
  player: Pick<Player, 'name' | 'avatar_color'>
  size?: keyof typeof SIZES
  className?: string
}

export function PlayerAvatar({ player, size = 'md', className }: PlayerAvatarProps) {
  const initial = player.name.trim().charAt(0).toUpperCase() || '?'

  return (
    <span
      aria-hidden
      className={cn(
        'flex shrink-0 items-center justify-center rounded-full font-bold text-black/80',
        SIZES[size],
        className,
      )}
      style={{ backgroundColor: player.avatar_color }}
    >
      {initial}
    </span>
  )
}
