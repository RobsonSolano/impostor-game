import { notFound } from 'next/navigation'
import { GameRoom } from '@/components/game/GameRoom'
import { isValidRoomCode, normalizeRoomCode } from '@/lib/game/room-code'

type PageProps = {
  // Next 16: `params` é sempre assíncrono.
  params: Promise<{ code: string }>
}

export default async function Page({ params }: PageProps) {
  const { code } = await params
  const normalized = normalizeRoomCode(decodeURIComponent(code))

  // Código malformado não chega a consultar o banco.
  if (!isValidRoomCode(normalized)) notFound()

  // A resolução do código para o id da sala acontece no cliente, sob a policy
  // "sou jogador desta sala" — que é o que distingue "sala não existe" de "você
  // não entrou nesta sala".
  return <GameRoom code={normalized} />
}
