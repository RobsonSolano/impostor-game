'use client'

import { useEffect, useState, type ReactNode } from 'react'
import { motion } from 'motion/react'
import { Eye, EyeOff } from 'lucide-react'
import { cn } from '@/lib/utils'

/** Passo do progresso. Valor fixo (e não Date.now) para o teste controlar o tempo. */
const TICK_MS = 40

type HoldToRevealProps = {
  children: ReactNode
  holdMs?: number
  hint?: string
  className?: string
}

/**
 * Modo Anti-Bisbilhoteiro (IMP-07).
 *
 * O conteúdo só existe no DOM enquanto o dedo está pressionado — e some ao
 * soltar. Não é blur nem `visibility: hidden`: se o segredo estivesse renderizado
 * e apenas escondido por CSS, ele estaria a um inspetor de distância.
 *
 * Cuidados de celular embutidos aqui:
 * - `touch-none` impede que o long-press vire scroll da página.
 * - `onContextMenu` bloqueia o menu que o iOS abre em toque longo.
 * - `onPointerLeave`/`onPointerCancel` cobrem o dedo escorregando para fora e a
 *   chamada entrando no meio da partida — ambos precisam ocultar a palavra.
 */
export function HoldToReveal({
  children,
  holdMs = 2000,
  hint = 'Segure para ver',
  className,
}: HoldToRevealProps) {
  const [holding, setHolding] = useState(false)
  const [elapsed, setElapsed] = useState(0)

  const progress = Math.min(elapsed / holdMs, 1)
  const revealed = elapsed >= holdMs

  useEffect(() => {
    if (!holding || revealed) return

    const id = setInterval(() => {
      setElapsed((prev) => Math.min(prev + TICK_MS, holdMs))
    }, TICK_MS)

    return () => clearInterval(id)
  }, [holding, revealed, holdMs])

  function press() {
    setHolding(true)
  }

  function release() {
    setHolding(false)
    setElapsed(0)
  }

  return (
    <div
      role="button"
      tabIndex={0}
      aria-pressed={revealed}
      aria-label={revealed ? 'Palavra revelada. Solte para ocultar.' : hint}
      data-testid="hold-to-reveal"
      className={cn(
        'relative flex w-full flex-col items-center justify-center overflow-hidden',
        'min-h-64 touch-none rounded-3xl border-2 p-6 text-center',
        'transition-colors duration-200',
        revealed
          ? 'border-primary/60 bg-card card-wash glow-primary'
          : 'border-border border-dashed bg-card/40 active:border-primary/40',
        className,
      )}
      onPointerDown={press}
      onPointerUp={release}
      onPointerLeave={release}
      onPointerCancel={release}
      onContextMenu={(event) => event.preventDefault()}
      onKeyDown={(event) => {
        // `repeat` importa: teclado dispara keydown continuamente enquanto a
        // tecla está apertada, e sem o guarda o estado reiniciaria a cada evento.
        if ((event.key === ' ' || event.key === 'Enter') && !event.repeat) {
          event.preventDefault()
          press()
        }
      }}
      onKeyUp={release}
      onBlur={release}
    >
      {revealed ? (
        <motion.div
          initial={{ opacity: 0, scale: 0.92, filter: 'blur(8px)' }}
          animate={{ opacity: 1, scale: 1, filter: 'blur(0px)' }}
          transition={{ duration: 0.22, ease: 'easeOut' }}
          className="flex flex-col items-center gap-3"
        >
          {children}
        </motion.div>
      ) : (
        <div className="text-muted-foreground flex flex-col items-center gap-4">
          <motion.div
            animate={holding ? { scale: [1, 1.12, 1] } : { scale: 1 }}
            transition={
              holding ? { duration: 0.9, repeat: Infinity } : { duration: 0.2 }
            }
          >
            {holding ? (
              <Eye className="text-primary size-10" aria-hidden />
            ) : (
              <EyeOff className="size-10" aria-hidden />
            )}
          </motion.div>

          <p className="text-lg font-medium">{hint}</p>
          <p className="max-w-[22ch] text-sm opacity-70">
            Ninguém mais pode olhar. Solte o dedo para esconder na hora.
          </p>
        </div>
      )}

      {/* Barra de progresso do hold. Só aparece durante a pressão. */}
      <div className="absolute inset-x-0 bottom-0 h-1.5 bg-transparent">
        <motion.div
          className="bg-primary h-full origin-left"
          data-testid="hold-progress"
          style={{ scaleX: progress }}
          animate={{ opacity: holding && !revealed ? 1 : 0 }}
          transition={{ duration: 0.15 }}
        />
      </div>
    </div>
  )
}
