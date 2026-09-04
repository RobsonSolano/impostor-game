import type { Metadata, Viewport } from 'next'
import Link from 'next/link'

/**
 * Política de privacidade.
 *
 * Existe porque a Google Play exige URL pública de política para publicar, e a
 * exigência vira absoluta a partir do momento em que o app exibe anúncio: o SDK
 * do AdMob acessa o identificador de publicidade do aparelho, e isso é
 * compartilhamento com terceiro que precisa estar declarado aqui E no formulário
 * de Segurança dos Dados do Console.
 *
 * O texto tem que bater com o formulário de Segurança dos Dados. Se um dia o app
 * passar a coletar algo novo, os dois mudam juntos — divergência entre a política
 * e o formulário é motivo de reprovação na revisão da Play.
 */

/** Único ponto de contato publicado. Trocar aqui muda a página inteira. */
const EMAIL_CONTATO = 'rsolanoodev@gmail.com'

/** Data da última revisão do texto, mostrada ao usuário e exigida pela Play. */
const ATUALIZADO_EM = '4 de setembro de 2026'

/**
 * O `variant="link"` do Button não serve aqui: ele carrega altura e padding de
 * botão, e estes links são inline no meio de parágrafo.
 */
const CLASSE_LINK = 'text-primary underline underline-offset-4'

/** Tipografia de corpo. Fora de `Secao` só o parágrafo de abertura a usa. */
const CLASSE_CORPO = 'text-foreground/85 leading-relaxed'

/**
 * O layout fixa `maximumScale: 1` porque, no jogo, pinçar durante a revelação do
 * card atrapalha. Aqui é o contrário: são ~190 linhas de texto legal e impedir o
 * zoom é barreira de acessibilidade sem nada em troca. Página sobrescreve; o
 * jogo continua como estava.
 */
export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
}

export const metadata: Metadata = {
  title: 'Política de Privacidade',
  description:
    'Como o jogo Impostor trata os dados de quem joga: sessão anônima, apelido, dicas, votos e anúncios.',
}

/** O e-mail aparece três vezes no texto; o estilo e o `mailto:` vivem num lugar só. */
function LinkContato() {
  return (
    <a href={`mailto:${EMAIL_CONTATO}`} className={CLASSE_LINK}>
      {EMAIL_CONTATO}
    </a>
  )
}

function Secao({ titulo, children }: { titulo: string; children: React.ReactNode }) {
  return (
    <section className="mt-10">
      <h2 className="font-heading text-primary text-xl font-semibold tracking-tight">
        {titulo}
      </h2>
      <div className={`mt-3 space-y-3 ${CLASSE_CORPO}`}>{children}</div>
    </section>
  )
}

export default function PrivacidadePage() {
  // `select-text` porque o <body> é `select-none` (long-press do card secreto):
  // numa política, a ação principal é justamente copiar o e-mail de contato.
  //
  // `max-w-2xl` e não o `APP_COLUMN` do repo: os 448px daquele foram calibrados
  // para botão primário e lista de jogadores, e são estreitos demais para prosa.
  return (
    <main className="pt-safe mx-auto w-full max-w-2xl px-6 py-12 select-text sm:py-16">
      {/*
        `prefetch={false}`: por padrão o Link baixa a rota inteira de `/` (+124 KB
        gzip — a home é client component com `motion`). Esta é uma folha jurídica
        que se chega pela ficha da Play e de onde quase ninguém navega para o
        jogo; não há ganho de SPA que pague esse download.
      */}
      <Link
        href="/"
        prefetch={false}
        className="text-muted-foreground touch-target hover:text-foreground inline-flex items-center text-sm transition-colors"
      >
        ← Voltar ao jogo
      </Link>

      <h1 className="font-heading mt-6 text-3xl font-bold tracking-tight sm:text-4xl">
        Política de Privacidade
      </h1>
      <p className="text-muted-foreground mt-2 text-sm">
        Aplica-se ao jogo <strong>Impostor</strong>, no aplicativo Android e no site.
        Atualizada em {ATUALIZADO_EM}.
      </p>

      <p className={`mt-8 ${CLASSE_CORPO}`}>
        O Impostor é um jogo de mesa. Ele não pede cadastro, e-mail, senha nem login
        social — abre e joga. Ainda assim, alguma coisa precisa trafegar para que
        vários celulares participem da mesma partida, e esta página diz exatamente o
        quê, por quê e com quem.
      </p>

      <Secao titulo="Quem é o responsável">
        <p>
          O aplicativo é mantido por Robson Solano, desenvolvedor independente. Para
          qualquer assunto tratado aqui — inclusive pedido de exclusão de dados — o
          contato é <LinkContato />.
        </p>
      </Secao>

      <Secao titulo="O que o jogo guarda">
        <p>
          Ao abrir o app, é criada uma <strong>sessão anônima</strong> no Supabase, o
          serviço que hospeda o banco de dados do jogo. Essa sessão é um identificador
          gerado pelo servidor e guardado no seu aparelho. Ela não está ligada ao seu
          nome, ao seu e-mail nem à sua conta Google.
        </p>
        <p>Enquanto você participa de uma partida, ficam guardados no banco:</p>
        <ul className="ml-5 list-disc space-y-1.5">
          <li>
            o <strong>apelido</strong> que você digitou (pode ser qualquer coisa — não
            há verificação de identidade);
          </li>
          <li>
            a <strong>cor de avatar</strong> sorteada para você naquela sala;
          </li>
          <li>
            as <strong>dicas</strong> que você escreveu durante a partida;
          </li>
          <li>
            os <strong>votos</strong> que você deu;
          </li>
          <li>
            o <strong>código e o título da sala</strong>, e — se a sala for pública — o
            fato de ela aparecer na lista de salas abertas.
          </li>
        </ul>
        <p>
          O jogo <strong>não</strong> acessa contatos, agenda, fotos, microfone, câmera
          nem localização. Não há analytics próprio, nem rastreamento entre aplicativos.
        </p>
      </Secao>

      <Secao titulo="Anúncios">
        <p>
          O app exibe <strong>um único anúncio por partida criada</strong>, no momento
          em que o anfitrião cria a sala. Não há anúncio durante o jogo: nem no card
          secreto, nem nas dicas, nem na votação, nem no resultado.
        </p>
        <p>
          O anúncio é servido pelo <strong>Google AdMob</strong>. Para escolher e medir
          o anúncio, o SDK do Google acessa dados que <em>não</em> passam por nós, entre
          eles o <strong>identificador de publicidade do aparelho</strong> (Advertising
          ID), o endereço IP e informações do dispositivo, como modelo e versão do
          sistema. Esses dados são coletados e usados pelo Google conforme a política de
          privacidade dele, disponível em{' '}
          <a
            href="https://policies.google.com/privacy"
            target="_blank"
            rel="noopener noreferrer"
            className={CLASSE_LINK}
          >
            policies.google.com/privacy
          </a>
          .
        </p>
        <p>
          Antes da primeira requisição de anúncio, o app usa a ferramenta de
          consentimento do próprio Google (UMP) para pedir sua autorização quando a
          legislação da sua região exigir. Você pode limitar a publicidade personalizada
          a qualquer momento nas configurações do Android, em{' '}
          <em>Google → Anúncios</em>, onde também é possível redefinir ou excluir o
          identificador de publicidade.
        </p>
      </Secao>

      <Secao titulo="Com quem os dados são compartilhados">
        <p>
          Com dois prestadores de serviço, e nenhum outro. Nada é vendido, e não há
          corretor de dados envolvido.
        </p>
        <ul className="ml-5 list-disc space-y-1.5">
          <li>
            <strong>Supabase</strong> — hospeda o banco de dados e a sessão anônima. É
            onde ficam apelido, dicas e votos.
          </li>
          <li>
            <strong>Google AdMob</strong> — serve o anúncio, como descrito acima.
          </li>
        </ul>
      </Secao>

      <Secao titulo="Por quanto tempo">
        <p>
          Os dados de uma partida ficam guardados no banco enquanto o serviço existir.
          Não há remoção automática por prazo hoje. Como nada ali está ligado à sua
          identidade — é um apelido e uma sessão anônima —, o que resta de uma sala
          antiga não permite identificar quem jogou.
        </p>
        <p>
          Se ainda assim você quiser que os registros associados ao seu aparelho sejam
          apagados, escreva para <LinkContato /> informando o código da sala e o apelido
          usado, e a exclusão é feita.
        </p>
      </Secao>

      <Secao titulo="Segurança">
        <p>
          O acesso ao banco é restrito por regras de linha (Row Level Security): cada
          jogador só consegue ler a própria carta secreta, e nem a palavra da rodada nem
          a identidade do impostor trafegam para quem não deveria vê-las antes da hora.
          Todo tráfego entre o app e o servidor é criptografado por HTTPS.
        </p>
      </Secao>

      <Secao titulo="Crianças">
        <p>
          O jogo não é dirigido a crianças e não coleta conscientemente dados de menores
          de 13 anos. O conteúdo é gerado pelos próprios jogadores (as dicas escritas),
          e há filtro de palavras vulgares com remoção do jogador na terceira ocorrência.
        </p>
      </Secao>

      <Secao titulo="Seus direitos">
        <p>
          Pela Lei Geral de Proteção de Dados (LGPD, Lei 13.709/2018), você pode
          solicitar confirmação de tratamento, acesso, correção, anonimização,
          portabilidade ou exclusão dos seus dados, e revogar consentimento. Basta
          escrever para o e-mail de contato — respondemos no prazo legal.
        </p>
      </Secao>

      <Secao titulo="Mudanças nesta política">
        <p>
          Se o jogo passar a coletar algo diferente, este texto muda antes, e a data no
          topo é atualizada junto. Vale a pena reler quando o app for atualizado.
        </p>
      </Secao>

      <hr className="border-border/60 mt-12" />
      <p className="text-muted-foreground mt-6 text-sm">
        Dúvidas sobre esta política: <LinkContato />
      </p>
    </main>
  )
}
