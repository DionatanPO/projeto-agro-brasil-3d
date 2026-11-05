# Documentação do Forest

Esta pasta divide o contexto do projeto em documentos menores, para consulta rápida por pessoas e assistentes de programação.

## Leia conforme a tarefa

1. **PROJECT_OVERVIEW.md** — o que é o jogo, cenas, sistemas e relações entre arquivos.
2. **MISSIONS_AND_PROGRESSION.md** — campanha, objetivos, sinais, save, XP e recompensas.
3. **PERFORMANCE_AND_STREAMING.md** — streaming, renderização, trabalho por frame e profiling.
4. **KNOWN_ISSUES_AND_ROADMAP.md** — problemas confirmados, riscos a investigar e próximos passos.

## Instruções de manutenção

- O código e os dados atuais são a fonte da verdade. Confirme os arquivos antes de agir.
- Pesquise referências em GDScript, cenas e JSON antes de renomear/remover IDs, sinais, grupos ou recursos.
- Preserve alterações pré-existentes no workspace.
- Prefira mudanças focadas, valide pelo Godot e relate o que foi testado.
- Não estime ganhos de FPS. Registre baseline e comparação sob a mesma plataforma, resolução, preset e cenário.
- Use cópia do save ao validar migrações; não arrisque o save real.
- Marque informações como **confirmado**, **hipótese**, **precisa medir** ou **resolvido**, e atualize o status quando o código mudar.

## Relatório antigo

O arquivo da raiz **RELATORIO_OTIMIZACAO_MOBILE.md** agora é somente um atalho para esta documentação. O conteúdo técnico foi distribuído nos documentos acima.

