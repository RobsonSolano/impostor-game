'use client'

import { useEffect, useEffectEvent, useState } from 'react'
import { motion } from 'motion/react'
import { cn } from '@/lib/utils'

const TICK_MS = 100

const TONES = {
  primary: { text: 'text-primary', bar: 'bg-primary' },
  violet: { text: 'text-violet', bar: 'bg-violet' },
  destructive: { text: 'text-destructive', bar: 'bg-destructive' },
} as const

type CountdownProps = {
  /** Prazo vindo do banco (`turn_deadline`, `guess_deadline`). */
  deadline: string | null
  /** Duração cheia, para desenhar a barra e limitar relógio adiantado. */
  totalMs: number
  onExpire: () => void
  tone?: keyof typeof TONES
  className?: string
}

/**
 * Contagem regressiva de um prazo do banco.
 *
 * **Monte sempre com `key={deadline}`**: o restante inicial vem do inicializador
 * de `useState`, então um prazo novo precisa de instância nova. Sem a key, o
 * contador do turno seguinte continuaria do valor do anterior.
 *
 * Sobre o relógio do aparelho: o restante é calculado UMA vez e limitado a
 * `totalMs`, depois conta para baixo localmente. Reler `deadline - Date.now()` a
 * cada tick deixaria o contador refém de um celular com a hora errada — e celular
 * com hora errada não é raro. Quem decide de verdade se o prazo venceu é a função
 * SQL, não este componente.
 */
export function Countdown({
  deadline,
  totalMs,
  onExpire,
  tone = 'primary',
  className,
}: CountdownProps) {
  const [remaining, setRemaining] = useState(() => {
    const target = deadline ? new Date(deadline).getTime() : 0
    return Math.min(Math.max(target - Date.now(), 0), totalMs)
  })

  // Cadeia de setTimeout em vez de setInterval: o setState fica no callback (não
  // no corpo do efeito) e a contagem se encerra sozinha ao chegar em zero.
  useEffect(() => {
    if (remaining <= 0) return
    const id = setTimeout(() => setRemaining((prev) => Math.max(prev - TICK_MS, 0)), TICK_MS)
    return () => clearTimeout(id)
  }, [remaining])

  const expire = useEffectEvent(() => onExpire())

  useEffect(() => {
    if (remaining <= 0) expire()
  }, [remaining])

  const seconds = Math.ceil(remaining / 1000)
  const tones = TONES[tone]

  return (
    <div className={cn('flex w-full flex-col items-center gap-2', className)}>
      <motion.span
        key={seconds}
        initial={{ scale: 1.35, opacity: 0.5 }}
        animate={{ scale: 1, opacity: 1 }}
        transition={{ duration: 0.2 }}
        className={cn('tabular text-5xl font-black', tones.text)}
        aria-live="polite"
        aria-label={`${seconds} segundos restantes`}
      >
        {seconds}
      </motion.span>

      <div className="bg-muted h-2 w-full overflow-hidden rounded-full">
        <motion.div
          className={cn('h-full origin-left', tones.bar)}
          style={{ scaleX: remaining / totalMs }}
          transition={{ ease: 'linear' }}
        />
      </div>
    </div>
  )
}
