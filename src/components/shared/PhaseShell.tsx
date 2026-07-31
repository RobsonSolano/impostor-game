import type { ReactNode } from 'react'
import { cn } from '@/lib/utils'

type PhaseShellProps = {
  /** Rótulo curto da fase, no topo. */
  eyebrow?: ReactNode
  title: ReactNode
  subtitle?: ReactNode
  /** Conteúdo principal — o "palco" da fase. */
  children?: ReactNode
  /**
   * Contexto secundário: mesa, placar, código da sala.
   * Empilhado abaixo do palco até `md`; coluna lateral a partir de `lg`.
   */
  aside?: ReactNode
  /** Ação primária. */
  action?: ReactNode
  className?: string
}

/**
 * Esqueleto de todas as telas de fase.
 *
 * Quatro faixas, um DOM só:
 *
 * - **Celular** (base): coluna única de largura cheia. Título no topo (área que o
 *   polegar não alcança e não precisa alcançar), palco, mesa abaixo, e a ação
 *   primária colada na base — zona do polegar.
 * - **Celular grande** (`sm`, 640px): mesma coluna, centralizada e delimitada.
 * - **Tablet** (`md`, 768px): coluna única larga e empilhada — palco em cima, mesa
 *   embaixo em linha (os jogadores quebram com wrap em vez de virar uma lista de
 *   um por linha), e o botão logo depois. A largura extra vira mais gente por
 *   linha, não uma lateral solta.
 * - **Desktop** (`lg`): aí sim duas colunas, com o contexto secundário na lateral
 *   e o bloco centralizado na vertical.
 *
 * De `md` para cima a ação sai da base e fica logo abaixo do conteúdo: em telas
 * grandes não existe zona do polegar, e botão preso no rodapé fica longe do que a
 * pessoa acabou de ler.
 *
 * A ordem no DOM é header → palco → mesa → sobra → ação, que é exatamente a ordem
 * de leitura no celular e no tablet. No desktop, `col-start`/`row-start` remontam
 * isso em grade sem duplicar nenhum nó — duplicar significaria dois componentes
 * com estado próprio, e o card secreto perderia o hold na troca de layout.
 *
 * `min-h-dvh` e não `min-h-screen`: `vh` no mobile ignora a barra do navegador e
 * empurra o botão para fora da área visível.
 */
export function PhaseShell({
  eyebrow,
  title,
  subtitle,
  children,
  aside,
  action,
  className,
}: PhaseShellProps) {
  return (
    <div
      className={cn(
        'flex min-h-dvh flex-col',
        // 640–767px: coluna única centralizada e delimitada.
        'sm:mx-auto sm:max-w-md sm:border-x sm:border-border/60',
        // 768–1023px: coluna larga, empilhada, sem moldura.
        'md:max-w-3xl md:border-x-0 md:px-6 md:py-16',
        // 1024px+: duas colunas, centralizadas na vertical.
        'lg:mx-auto lg:grid lg:max-w-5xl lg:grid-cols-[minmax(0,1fr)_20rem]',
        'lg:grid-rows-[auto_auto_auto] lg:content-center lg:gap-x-12 lg:px-8 lg:py-20',
        className,
      )}
    >
      {/* `pr-32` reserva espaço para o botão flutuante de sair/encerrar. */}
      <header className="pt-safe px-5 pr-32 pb-3 md:px-0 md:pt-0 lg:col-start-1 lg:row-start-1 lg:pr-0 lg:pb-6">
        {eyebrow && (
          <p className="text-primary text-xs font-bold tracking-[0.2em] uppercase">{eyebrow}</p>
        )}
        <h1 className="mt-1.5 text-2xl leading-tight font-bold tracking-tight text-balance md:text-3xl lg:text-4xl">
          {title}
        </h1>
        {subtitle && (
          <p className="text-muted-foreground mt-2 text-sm text-pretty lg:text-base">{subtitle}</p>
        )}
      </header>

      <main className="px-5 pb-4 md:px-0 md:pb-6 lg:col-start-1 lg:row-start-2 lg:pb-0">
        {children}
      </main>

      {aside && (
        <aside className="px-5 pb-4 md:px-0 md:pb-0 lg:col-start-2 lg:row-start-1 lg:row-span-3 lg:self-center">
          {aside}
        </aside>
      )}

      {/*
        A sobra vertical fica DEPOIS do conteúdo, não dentro dele: esticar o `main`
        abriria um vão entre o palco e a mesa, separando duas coisas que se leem
        juntas. De tablet para cima a ação já vem logo abaixo da mesa, então o
        espaçador sai de cena.
      */}
      <div className="flex-1 md:hidden" aria-hidden />

      {action && (
        // Celular: colado na base, com gradiente para o conteúdo não colidir.
        // Tablet/desktop: estático logo abaixo do conteúdo, sem gradiente.
        <div
          className={cn(
            'from-background via-background pb-safe sticky bottom-0 bg-gradient-to-t to-transparent px-5 pt-4',
            'md:static md:bg-none md:px-0 md:pt-8 md:pb-0',
            'lg:col-start-1 lg:row-start-3',
          )}
        >
          {action}
        </div>
      )}
    </div>
  )
}
