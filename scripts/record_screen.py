#!/usr/bin/env python3
"""
Proof-of-concept de gravação de tela para o macOS.

Funciona assim:
- Em loop infinito, tira screenshots da tela atual usando o utilitário nativo `screencapture`.
- Salva os arquivos em uma estrutura de pastas do tipo:

  com.playback.Playback/chunks/YYYYMM/DD/<id>

- Cada arquivo é uma imagem PNG, mas sem extensão, imitando o padrão de `com.memoryvault.MemoryVault/chunks`.

Requisitos:
- macOS (já inclui o binário `screencapture`)
- Python 3
- Permissão de "Gravação de Tela" nas Preferências do Sistema para o Terminal/Cursor.
"""

import subprocess
import time
from datetime import datetime
from pathlib import Path
import uuid
import re
from typing import Optional
import ctypes
import ctypes.util


# Diretório base deste projeto (ajustado para o layout atual)
PROJECT_ROOT = Path(__file__).resolve().parents[1]

_CG = None


# Pasta base dos chunks da PoC (agora em temp em vez de chunks)
CHUNKS_ROOT = PROJECT_ROOT / "com.playback.Playback" / "temp"


def _load_coregraphics():
    """Carrega a framework CoreGraphics via ctypes (lazy)."""
    global _CG
    if _CG is not None:
        return _CG
    path = ctypes.util.find_library("CoreGraphics")
    if not path:
        raise RuntimeError("CoreGraphics framework não encontrada")
    _CG = ctypes.CDLL(path)
    return _CG


def _check_display_active() -> Optional[bool]:
    """
    Verifica se há displays ativos usando CoreGraphics.
    Retorna True se há displays ativos, False se não há (display desligado), None se não conseguiu determinar.
    """
    try:
        cg = _load_coregraphics()
    except Exception as e:
        print(f"[Playback] DEBUG: CoreGraphics indisponível: {e}")
        return None

    # Assinatura da função
    CGGetActiveDisplayList = cg.CGGetActiveDisplayList
    CGGetActiveDisplayList.argtypes = [
        ctypes.c_uint32,
        ctypes.POINTER(ctypes.c_uint32),
        ctypes.POINTER(ctypes.c_uint32),
    ]
    CGGetActiveDisplayList.restype = ctypes.c_int32

    # Lista de displays ativos
    max_displays = 16
    active = (ctypes.c_uint32 * max_displays)()
    count = ctypes.c_uint32(0)
    err = CGGetActiveDisplayList(max_displays, active, ctypes.byref(count))
    
    if err != 0:
        print(f"[Playback] DEBUG: CGGetActiveDisplayList erro: {err}")
        return None
    
    if count.value == 0:
        print(f"[Playback] DEBUG: Nenhum display ativo detectado (display desligado)")
        return False
    
    print(f"[Playback] DEBUG: {count.value} display(s) ativo(s) detectado(s)")
    return True


def _get_active_display_index() -> Optional[int]:
    """
    Descobre o índice (1‑based) do monitor que está "em uso" no momento,
    usando apenas CoreGraphics via ctypes (100% Python, sem JS).

    Heurística: pega a posição atual do mouse e encontra qual display ativo
    contém esse ponto. Esse índice é compatível com `screencapture -D`.
    """
    try:
        cg = _load_coregraphics()
    except Exception as e:
        print(f"[Playback] CoreGraphics indisponível: {e}")
        return None

    # Define structs CoreGraphics básicos (CGPoint, CGSize, CGRect)
    class CGPoint(ctypes.Structure):
        _fields_ = [("x", ctypes.c_double), ("y", ctypes.c_double)]

    class CGSize(ctypes.Structure):
        _fields_ = [("width", ctypes.c_double), ("height", ctypes.c_double)]

    class CGRect(ctypes.Structure):
        _fields_ = [("origin", CGPoint), ("size", CGSize)]

    # Assinaturas das funções usadas
    CGGetActiveDisplayList = cg.CGGetActiveDisplayList
    CGGetActiveDisplayList.argtypes = [
        ctypes.c_uint32,
        ctypes.POINTER(ctypes.c_uint32),
        ctypes.POINTER(ctypes.c_uint32),
    ]
    CGGetActiveDisplayList.restype = ctypes.c_int32

    CGEventCreate = cg.CGEventCreate
    CGEventCreate.argtypes = [ctypes.c_void_p]
    CGEventCreate.restype = ctypes.c_void_p

    CGEventGetLocation = cg.CGEventGetLocation
    CGEventGetLocation.argtypes = [ctypes.c_void_p]
    CGEventGetLocation.restype = CGPoint

    CGDisplayBounds = cg.CGDisplayBounds
    CGDisplayBounds.argtypes = [ctypes.c_uint32]
    CGDisplayBounds.restype = CGRect

    # 1) Lista de displays ativos
    max_displays = 16
    active = (ctypes.c_uint32 * max_displays)()
    count = ctypes.c_uint32(0)
    err = CGGetActiveDisplayList(max_displays, active, ctypes.byref(count))
    if err != 0 or count.value == 0:
        # Se não há displays ativos, retorna None (será tratado como display desligado)
        return None

    # 2) Posição atual do mouse
    event_ref = CGEventCreate(None)
    if not event_ref:
        print("[Playback] CGEventCreate retornou NULL")
        return None
    loc = CGEventGetLocation(event_ref)
    px, py = loc.x, loc.y

    # 3) Encontra qual display contém esse ponto
    for i in range(count.value):
        display_id = active[i]
        bounds = CGDisplayBounds(display_id)
        sx = bounds.origin.x
        sy = bounds.origin.y
        sw = bounds.size.width
        sh = bounds.size.height

        if px >= sx and px <= sx + sw and py >= sy and py <= sy + sh:
            idx = i + 1  # screencapture -D é 1‑based
            print(f"[Playback] Mouse em display {idx} (id={display_id}, frame=({sx},{sy},{sw},{sh}))")
            return idx

    # Fallback: primeiro display
    print("[Playback] Nenhum display continha o mouse, usando display 1")
    return 1


def _check_screensaver_via_applescript() -> Optional[bool]:
    """
    Verifica se o protetor de tela está ativo usando AppleScript.
    Retorna True se o protetor de tela está ativo, False se não está, None se não conseguiu determinar.
    """
    try:
        script = 'tell application "System Events" to tell screen saver preferences to get running'
        result = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True,
            text=True,
            check=False,
        )
        
        if result.returncode == 0:
            output = result.stdout.strip().lower()
            print(f"[Playback] DEBUG: AppleScript screen saver running: {output}")
            if "true" in output:
                return True
            if "false" in output:
                return False
        
        return None
    except Exception as e:
        print(f"[Playback] DEBUG: Erro ao executar AppleScript para protetor de tela: {e}")
        return None


def is_screen_unavailable() -> bool:
    """
    Retorna True se a tela NÃO deve ser gravada, por estar:
    - em protetor de tela
    - com o display desligado

    Implementação (macOS):
    - Verifica protetor de tela via AppleScript
    - Verifica se há displays ativos via CoreGraphics (se count=0, display está desligado)
    """
    print("[Playback] DEBUG: Verificando estado da tela...")
    
    # Verifica protetor de tela
    screensaver_active = _check_screensaver_via_applescript()
    if screensaver_active is True:
        print(f"[Playback] Tela indisponível (protetor de tela ativo); pulando captura.")
        print(f"[Playback] DEBUG: is_screen_unavailable() -> True (protetor de tela)")
        return True
    
    # Verifica se há displays ativos (se não há, display está desligado)
    display_active = _check_display_active()
    if display_active is False:
        print(f"[Playback] Tela indisponível (display desligado); pulando captura.")
        print(f"[Playback] DEBUG: is_screen_unavailable() -> True (display desligado)")
        return True
    
    print(f"[Playback] DEBUG: is_screen_unavailable() -> False (tela disponível)")
    return False


def ensure_chunk_dir(now: datetime) -> Path:
    """
    Garante que a pasta chunks/YYYYMM/DD exista.
    Retorna o caminho da pasta do dia.
    """
    year_month = now.strftime("%Y%m")  # ex: 202512
    day = now.strftime("%d")           # ex: 22

    day_dir = CHUNKS_ROOT / year_month / day
    day_dir.mkdir(parents=True, exist_ok=True)
    return day_dir


def capture_screen(output_path: Path) -> None:
    """
    Usa o binário nativo `screencapture` do macOS para tirar screenshot da tela.
    -x: sem som de câmera
    -t png: formato PNG
    """
    # Salvamos em um arquivo temporário com extensão .png,
    # depois renomeamos para remover a extensão (imitando o outro app).
    temp_path = output_path.with_suffix(".png")

    # Tenta descobrir qual monitor está em uso (onde está a janela em foco)
    # para capturar o DISPLAY inteiro com `screencapture -D`.
    display_index = _get_active_display_index()

    cmd = [
        "screencapture",
        "-x",        # sem UI / som
        "-t",
        "png",       # formato
    ]
    if display_index is not None:
        print(f"[Playback] Usando screencapture -D {display_index} (monitor em uso)")
        cmd.extend(["-D", str(display_index)])

    cmd.append(str(temp_path))

    subprocess.run(cmd, check=True)

    # Renomeia removendo a extensão para ficar igual aos chunks existentes
    temp_path.rename(output_path)


def _get_frontmost_app_bundle_id() -> str:
    """
    Usa AppleScript + System Events (Accessibility) para descobrir
    o bundle identifier do app atualmente em foco.
    """
    script = (
        'tell application "System Events" to get '
        'bundle identifier of (first process whose frontmost is true)'
    )
    try:
        out = subprocess.check_output(
            ["osascript", "-e", script],
            text=True,
        ).strip()
        return out or "unknown"
    except Exception as e:
        print(f"[Playback] Não foi possível obter app atual via Accessibility: {e}")
        return "unknown"


def _sanitize_app_id(app_id: str) -> str:
    """
    Normaliza o bundle id para uso em nome de arquivo.
    Mantém letras, dígitos e '.', trocando o resto por '_'.
    """
    if not app_id:
        return "unknown"
    return re.sub(r"[^A-Za-z0-9.]+", "_", app_id)


def generate_chunk_name(now: datetime) -> str:
    """
    Gera um nome de arquivo único, no estilo:

      YYYYMMDD-HHMMSS-<uuid-curto>

    Isso facilita reconstruir o timestamp a partir do nome.
    """
    date_part = now.strftime("%Y%m%d")
    ts = now.strftime("%H%M%S")
    short_uuid = uuid.uuid4().hex[:8]
    app_id = _sanitize_app_id(_get_frontmost_app_bundle_id())
    # Novo formato: YYYYMMDD-HHMMSS-<uuid-curto>-<app_id>
    return f"{date_part}-{ts}-{short_uuid}-{app_id}"


def main(
    interval_seconds: int = 2,
) -> None:
    """
    Loop principal:
    - A cada `interval_seconds`, tira um screenshot e salva no diretório de chunks.
    """
    print(f"[Playback] Iniciando gravação de tela com intervalo de {interval_seconds}s...")
    print(f"[Playback] Salvando em: {CHUNKS_ROOT}")

    while True:
        now = datetime.now()
        print(f"[Playback] DEBUG: Iniciando ciclo de captura às {now.strftime('%H:%M:%S')}")

        # Se a tela estiver em protetor de tela / bloqueada / desligada,
        # não gravamos nada neste ciclo.
        screen_unavailable = is_screen_unavailable()
        print(f"[Playback] DEBUG: screen_unavailable = {screen_unavailable}")
        
        if screen_unavailable:
            print(f"[Playback] DEBUG: Pulando captura (tela indisponível), aguardando {interval_seconds}s...")
            time.sleep(interval_seconds)
            continue

        print(f"[Playback] DEBUG: Tela disponível, prosseguindo com captura...")
        day_dir = ensure_chunk_dir(now)
        chunk_name = generate_chunk_name(now)
        chunk_path = day_dir / chunk_name

        try:
            capture_screen(chunk_path)
            print(f"[Playback] Captura salva em: {chunk_path}")
        except subprocess.CalledProcessError as e:
            print(f"[Playback] ERRO ao capturar tela: {e}")

        time.sleep(interval_seconds)


if __name__ == "__main__":
    # Para PoC, intervalo padrão de 2s.
    # Você pode mudar para 1–5s se quiser algo mais frequente.
    main(interval_seconds=2)


