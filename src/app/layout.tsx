import type { Metadata, Viewport } from 'next'
import { Geist, Geist_Mono } from 'next/font/google'
import './globals.css'

const geistSans = Geist({
  variable: '--font-geist-sans',
  subsets: ['latin'],
})

const geistMono = Geist_Mono({
  variable: '--font-geist-mono',
  subsets: ['latin'],
})

export const metadata: Metadata = {
  // `template` para que cada página nova declare só o próprio nome e a marca
  // entre sozinha. Sem ele, toda rota recompõe a marca à mão e um rename vira
  // grep em arquivos de página.
  title: {
    default: 'Jogo do Impostor',
    template: '%s — Jogo do Impostor',
  },
  description:
    'Todos recebem a mesma palavra secreta. Menos um. Descubra o impostor antes que ele engane a mesa.',
}

export const viewport: Viewport = {
  themeColor: '#0a0a0a',
  width: 'device-width',
  initialScale: 1,
  // Zoom por duplo-toque no meio de uma revelação de card atrapalha mais do que
  // ajuda, e o app não tem texto pequeno que justifique pinçar.
  maximumScale: 1,
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode
}>) {
  return (
    // `dark` fixo: jogo de mesa é jogado à noite, e tela clara na cara de todos
    // atrapalha a partida.
    <html
      lang="pt-BR"
      className={`dark ${geistSans.variable} ${geistMono.variable} antialiased`}
    >
      {/*
        `overscroll-none` mata o bounce do iOS, que durante um long-press no card
        secreto parece bug. `select-none` evita a alça de seleção de texto
        aparecer quando o jogador segura o dedo na tela.
      */}
      <body className="bg-background text-foreground min-h-dvh overscroll-none select-none">
        {children}
      </body>
    </html>
  )
}
