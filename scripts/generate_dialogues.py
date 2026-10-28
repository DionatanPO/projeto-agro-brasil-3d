#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Gera todos os áudios de diálogo do jogo usando Pocket TTS (Kyutai).
Roda: python scripts/generate_dialogues.py
"""

import json
import subprocess
import sys
from pathlib import Path

# Configuração
LANGUAGE = "portuguese"
VOICE = "rafael"  # Voz em português
OUTPUT_DIR = Path("assets/audio/dialogues")

# Diálogos do jogo (extraídos dos JSONs em data/dialogues/)
DIALOGUES = {
    # Missão 1: Primeira Entrega
    "primeira_entrega_inicio": "Missão iniciada. A encomenda da instituição deve ter chegado. Vá até o ponto central da fazenda.",
    "primeira_entrega_chegou_area": "Cheguei na área da encomenda. Preciso encontrar o pacote.",
    "primeira_entrega_abriu_caixa": "Abri a caixa! Encontrei a encomenda.",
    "primeira_entrega_concluida_agrobot": "Missão concluída! Sou o Agrobot, seu novo companheiro. Vou te acompanhar na fazenda.",

    # Missão 2: Conhecer Solo
    "conhecer_solo_inicio": "Nova missão: Pisando no Solo. Visite a placa sobre o solo e conclua a leitura.",
    "conhecer_solo_placa": "Li a placa sobre o solo. Solo saudável tem matéria orgânica e vida.",

    # Missão 3: Conhecer Água
    "conhecer_agua_inicio": "Nova missão: Água Consciente. Visite a placa sobre o uso da água no campo.",
    "conhecer_agua_placa": "Água é essencial. Irrigação por gotejamento economiza água.",

    # Missão 4: Conhecer Culturas
    "conhecer_culturas_inicio": "Nova missão: Culturas do Brasil. Visite as placas da soja e do milho.",
    "conhecer_culturas_soja": "A soja fixa nitrogênio no solo com ajuda de bactérias.",
    "conhecer_culturas_milho": "O milho é cultivado em duas safras: verão e safrinha.",

    # Intro / Sistema
    "intro_narrador": "Bem-vindo à sua fazenda. A instituição de ensino enviou sua primeira encomenda.",
}

def generate_audio(text: str, output_path: Path) -> bool:
    """Gera áudio via pocket-tts CLI."""
    try:
        result = subprocess.run([
            "pocket-tts", "generate",
            "--text", text,
            "--voice", VOICE,
            "--language", LANGUAGE,
            "--output-path", str(output_path)
        ], capture_output=True, text=True, timeout=120)

        if result.returncode == 0:
            print(f"✓ {output_path.name}")
            return True
        else:
            print(f"✗ {output_path.name}: {result.stderr[:200]}")
            return False
    except subprocess.TimeoutExpired:
        print(f"✗ {output_path.name}: Timeout")
        return False
    except Exception as e:
        print(f"✗ {output_path.name}: {e}")
        return False

def main():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    print(f"Gerando {len(DIALOGUES)} diálogos em {LANGUAGE} (voz: {VOICE})...")
    print(f"Saída: {OUTPUT_DIR.absolute()}\n")

    success = 0
    for dialogue_id, text in DIALOGUES.items():
        output_path = OUTPUT_DIR / f"{dialogue_id}.wav"
        if generate_audio(text, output_path):
            success += 1

    print(f"\n{'='*50}")
    print(f"Concluído: {success}/{len(DIALOGUES)} áudios gerados")
    print(f"Diretório: {OUTPUT_DIR.absolute()}")

if __name__ == "__main__":
    main()