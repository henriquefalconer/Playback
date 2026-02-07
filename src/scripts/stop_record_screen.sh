#!/bin/zsh

# Encerra qualquer instância em execução de record_screen.py
# (assumindo que é executado a partir da raiz do projeto Playback)

SCRIPT_PATTERN="scripts/record_screen.py"

PIDS=$(pgrep -f "$SCRIPT_PATTERN")

if [ -z "$PIDS" ]; then
  echo "[Playback] Nenhum processo de gravação encontrado."
  exit 0
fi

echo "[Playback] Encerrando processos de gravação: $PIDS"
kill $PIDS

sleep 1

PIDS_RESTANTES=$(pgrep -f "$SCRIPT_PATTERN" || true)

if [ -n "$PIDS_RESTANTES" ]; then
  echo "[Playback] Alguns processos ainda estão vivos, forçando término: $PIDS_RESTANTES"
  kill -9 $PIDS_RESTANTES
else
  echo "[Playback] Todos os processos de gravação foram encerrados."
fi