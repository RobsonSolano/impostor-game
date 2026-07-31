/**
 * Coluna do app.
 *
 * Mobile-first, não mobile-only: no celular ocupa a tela toda, e em tablet e
 * desktop fica uma coluna centralizada em vez de esticar. Sem isto, um botão
 * primário viraria uma faixa de 1400px e a lista de jogadores ficaria com o nome
 * de um lado e o placar do outro extremo da tela — ilegível.
 *
 * `max-w-md` (448px) mantém a mesma proporção de leitura do celular, então o
 * layout não precisa de uma segunda versão para telas grandes.
 *
 * A borda lateral só aparece de `sm` para cima: no celular não há "fora da
 * coluna", e ali ela seria só um risco na tela.
 */
export const APP_COLUMN = 'mx-auto w-full max-w-md'

/** Coluna + delimitação lateral. Para os contêineres de tela cheia. */
export const APP_COLUMN_FRAMED = `${APP_COLUMN} sm:border-x sm:border-border/60`
