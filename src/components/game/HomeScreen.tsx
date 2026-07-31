'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { motion } from 'motion/react'
import { Loader2, UserRoundSearch } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { cn } from '@/lib/utils'
import { createRoom, joinRoom } from '@/lib/game/actions'
import { toDisplayError } from '@/lib/game/errors'
import {
  NICKNAME_MAX_LENGTH,
  ROOM_CODE_LENGTH,
  isValidNickname,
  isValidRoomCode,
  normalizeRoomCode,
} from '@/lib/game/room-code'

type Mode = 'criar' | 'entrar'

export function HomeScreen() {
  const router = useRouter()
  const [mode, setMode] = useState<Mode>('criar')
  const [name, setName] = useState('')
  const [code, setCode] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [, startTransition] = useTransition()

  const canSubmit =
    isValidNickname(name) && (mode === 'criar' || isValidRoomCode(code)) && !busy

  async function submit() {
    if (!canSubmit) return
    setBusy(true)
    setError(null)

    try {
      const result =
        mode === 'criar' ? await createRoom(name) : await joinRoom(code, name)

      startTransition(() => {
        router.push(`/sala/${result.code}`)
      })
    } catch (err) {
      setError(toDisplayError(err))
      setBusy(false)
    }
  }

  // Renderizado em dois lugares que nunca coexistem: base da tela no celular,
  // dentro do card do formulário no desktop. Um nó só, por variável, para não
  // duplicar a lógica do botão.
  const cta = (
    <Button
      type="button"
      size="lg"
      disabled={!canSubmit}
      onClick={() => void submit()}
      className="glow-primary h-14 w-full text-base font-bold tracking-wide"
    >
      {busy && <Loader2 className="size-5 animate-spin" aria-hidden />}
      {mode === 'criar' ? 'Criar sala' : 'Entrar na sala'}
    </Button>
  )

  return (
    <div
      className={cn(
        'flex min-h-dvh flex-col',
        // Tablet retrato: coluna centralizada e delimitada.
        'sm:mx-auto sm:max-w-md sm:border-x sm:border-border/60',
        // Tablet e desktop: herói e formulário lado a lado, centralizados na vertical.
        // Um tablet tem largura para as duas colunas; centralizar a coluna do
        // celular ali seria desperdiçar metade da tela.
        'md:max-w-3xl md:border-x-0 md:px-6',
        'lg:mx-auto lg:grid lg:max-w-5xl lg:grid-cols-2 lg:items-center lg:gap-16 lg:px-8',
      )}
    >
      {/*
        No CELULAR, a sobra vertical é repartida em 1 : 4 : 3 entre topo, herói e
        base. O header centraliza o herói na própria caixa, então metade do peso 4
        fica acima do texto e metade abaixo: vão do topo = 1 + 2 partes, vão
        herói→formulário = 2 partes, e 3 partes sobrando acima do CTA.

        Proporção em vez de padding fixo porque a mesma tela roda em aparelho de
        667px e de 932px de altura — número mágico acertaria em um e erraria no
        outro.

        De TABLET para cima os espaçadores saem de cena: lá o layout é de duas colunas
        centralizadas na vertical, e eles só distorceriam a grade.
      */}
      <div className="pt-safe flex-[1] lg:hidden" aria-hidden />

      <header className="hero-radial flex flex-[4] flex-col items-center justify-center px-6 text-center md:px-0 lg:col-start-1 lg:row-start-1 lg:flex-none lg:items-start lg:text-left">
        <motion.div
          initial={{ scale: 0.85, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ type: 'spring', stiffness: 260, damping: 20 }}
          className="bg-card card-wash glow-primary border-primary/40 mb-7 rounded-3xl border-2 p-5"
        >
          <UserRoundSearch className="text-primary size-12" aria-hidden />
        </motion.div>

        <h1 className="text-4xl font-bold tracking-tight md:text-5xl lg:text-6xl">
          Jogo do <span className="text-primary">Impostor</span>
        </h1>
        <p className="text-muted-foreground mt-3 max-w-[30ch] text-pretty md:mt-5 md:max-w-[34ch] lg:text-lg">
          Todos recebem a mesma palavra secreta. Menos um. Conversem, desconfiem e
          votem.
        </p>
      </header>

      {/* De tablet para cima este bloco vira o card do formulário, à direita. */}
      <div className="px-5 md:px-0 lg:col-start-2 lg:row-start-1 lg:bg-card lg:border-border lg:rounded-3xl lg:border lg:p-8">
        {/* Toggle de modo. Dois alvos grandes, lado a lado — nada de dropdown. */}
        <div
          role="tablist"
          aria-label="Criar ou entrar em sala"
          className="bg-muted mb-5 grid grid-cols-2 gap-1 rounded-2xl p-1"
        >
          {(['criar', 'entrar'] as const).map((option) => (
            <button
              key={option}
              role="tab"
              type="button"
              aria-selected={mode === option}
              onClick={() => {
                setMode(option)
                setError(null)
              }}
              className={`touch-target rounded-xl text-sm font-semibold transition-colors ${
                mode === option
                  ? 'bg-card text-foreground border-border border'
                  : 'text-muted-foreground'
              }`}
            >
              {option === 'criar' ? 'Criar sala' : 'Entrar em sala'}
            </button>
          ))}
        </div>

        <form
          className="flex flex-col gap-4"
          onSubmit={(event) => {
            event.preventDefault()
            void submit()
          }}
        >
          <div className="flex flex-col gap-2">
            <Label htmlFor="nickname">Seu nome</Label>
            <Input
              id="nickname"
              value={name}
              onChange={(event) => setName(event.target.value)}
              placeholder="Como a mesa te chama"
              maxLength={NICKNAME_MAX_LENGTH}
              autoComplete="nickname"
              enterKeyHint={mode === 'criar' ? 'go' : 'next'}
              className="h-14 text-base"
            />
          </div>

          {mode === 'entrar' && (
            <div className="flex flex-col gap-2">
              <Label htmlFor="code">Código da sala</Label>
              <Input
                id="code"
                value={code}
                onChange={(event) => setCode(normalizeRoomCode(event.target.value))}
                placeholder="X9K2"
                // `inputMode` + `autoCapitalize` para o teclado do celular abrir
                // já certo: maiúsculas, sem corretor, sem sugestão.
                inputMode="text"
                autoCapitalize="characters"
                autoCorrect="off"
                spellCheck={false}
                maxLength={ROOM_CODE_LENGTH}
                enterKeyHint="go"
                className="tabular h-16 text-center text-3xl font-bold tracking-[0.4em] uppercase"
              />
            </div>
          )}

          {error && (
            <motion.p
              initial={{ opacity: 0, y: -6 }}
              animate={{ opacity: 1, y: 0 }}
              role="alert"
              className="text-destructive text-sm font-medium"
            >
              {error}
            </motion.p>
          )}
        </form>

        {/* Tablet/desktop: o CTA fecha o card, logo abaixo dos campos. */}
        <div className="hidden lg:mt-6 lg:block">{cta}</div>
      </div>

      {/* As 3 partes que sobraram: empurram o CTA para a base sem esticar o herói. */}
      <div className="flex-[3] lg:hidden" aria-hidden />

      {/* Celular: CTA na base, zona do polegar. */}
      <div className="pb-safe px-5 pt-5 md:px-0 lg:hidden">{cta}</div>
    </div>
  )
}
