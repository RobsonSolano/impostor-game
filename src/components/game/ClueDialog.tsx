'use client'

import { useState } from 'react'
import { motion } from 'motion/react'
import { Loader2, TriangleAlert } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Countdown } from '@/components/shared/Countdown'
import { submitClue } from '@/lib/game/actions'
import { clueProblem, isValidClue, normalizeClue } from '@/lib/game/clue'
import { toDisplayError } from '@/lib/game/errors'
import { CLUE_MAX_LENGTH } from '@/lib/game/clue'

type ClueDialogProps = {
  roomId: string
  deadline: string | null
  totalMs: number
  onExpire: () => void
  /** Fechado pelo jogador para consultar as dicas anteriores. */
  onDismiss: () => void
  open: boolean
}

/**
 * Popup de escrever a dica. (IMP-31 a IMP-34)
 *
 * **Monte com `key` no turno**: input, erro e faltas são estado local, e um turno
 * novo precisa começar limpo. Sem a key, a mensagem de palavrão do turno anterior
 * apareceria no seguinte.
 *
 * É dispensável de propósito: para escolher uma boa dica a pessoa precisa poder
 * olhar as dicas que já estão na mesa. Fechar não desiste do turno — o prazo
 * continua correndo e o botão de reabrir fica na ação da tela.
 */
export function ClueDialog({
  roomId,
  deadline,
  totalMs,
  onExpire,
  onDismiss,
  open,
}: ClueDialogProps) {
  const [word, setWord] = useState('')
  const [busy, setBusy] = useState(false)
  const [profanity, setProfanity] = useState<{ strikes: number } | null>(null)
  const [error, setError] = useState<string | null>(null)

  const problem = word.length > 0 ? clueProblem(word) : null
  const canSubmit = isValidClue(word) && !busy

  async function send() {
    if (!canSubmit) return
    setBusy(true)
    setError(null)
    setProfanity(null)

    try {
      const result = await submitClue(roomId, normalizeClue(word))

      if (!result.ok && result.reason === 'PROFANITY') {
        // A falta já está gravada no banco. Se o jogador foi expulso, o Realtime
        // traz o novo estado e esta tela sai de cena por conta própria.
        setProfanity({ strikes: result.strikes ?? 1 })
        setWord('')
        setBusy(false)
        return
      }

      // Sucesso: o turno já passou no banco, e o Realtime fecha este popup.
    } catch (err) {
      setError(toDisplayError(err))
      setBusy(false)
    }
  }

  return (
    <Dialog open={open} onOpenChange={(next) => !next && onDismiss()}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle className="text-xl leading-snug text-balance">
            Escreva <strong className="text-primary">uma</strong> palavra
            relacionada a palavra secreta
          </DialogTitle>
          <DialogDescription asChild>
            <p className="text-warn flex items-start gap-1.5 text-xs">
              <TriangleAlert className="mt-0.5 size-3.5 shrink-0" aria-hidden />
              Cuidado para não entregar a palavra secreta
            </p>
          </DialogDescription>
        </DialogHeader>

        <div className="py-2">
          <Countdown
            key={deadline ?? 'sem-prazo'}
            deadline={deadline}
            totalMs={totalMs}
            onExpire={onExpire}
            tone="primary"
          />
        </div>

        <form
          className="flex flex-col gap-3"
          onSubmit={(event) => {
            event.preventDefault()
            void send()
          }}
        >
          <Input
            autoFocus
            value={word}
            onChange={(event) => setWord(event.target.value)}
            placeholder="ex.: tromba"
            maxLength={CLUE_MAX_LENGTH}
            autoComplete="off"
            autoCorrect="off"
            spellCheck={false}
            enterKeyHint="send"
            aria-invalid={Boolean(problem)}
            className="h-14 text-center text-xl font-semibold"
          />

          {profanity && (
            <motion.p
              initial={{ opacity: 0, y: -4 }}
              animate={{ opacity: 1, y: 0 }}
              role="alert"
              className="text-destructive text-sm font-semibold text-pretty"
            >
              Proibido utilizar palavras vulgares. Se continuar, será expulso da sala.
              <span className="mt-1 block text-xs font-normal opacity-80">
                {profanity.strikes === 1
                  ? 'Primeira ocorrência. Na terceira você é expulso.'
                  : 'Segunda ocorrência. Na próxima você é expulso.'}
              </span>
            </motion.p>
          )}

          {problem && !profanity && (
            <p className="text-muted-foreground text-sm">{problem}</p>
          )}

          {error && (
            <p role="alert" className="text-destructive text-sm font-medium">
              {error}
            </p>
          )}

          <Button
            type="submit"
            size="lg"
            disabled={!canSubmit}
            className="glow-primary h-14 w-full text-base font-bold tracking-wide"
          >
            {busy && <Loader2 className="size-5 animate-spin" aria-hidden />}
            Pronto
          </Button>

          <button
            type="button"
            onClick={onDismiss}
            className="text-muted-foreground touch-target text-sm underline-offset-4 hover:underline"
          >
            Ver as dicas da mesa
          </button>
        </form>
      </DialogContent>
    </Dialog>
  )
}
