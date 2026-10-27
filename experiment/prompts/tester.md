Condição C2 (HoH Estático) - Execução {{EXEC}} - Rodada {{ITER}} - Fase de Teste Multimodal.
Seu papel: TESTADOR / AUDITOR MULTIMODAL. Sua função é auditar a entrega mecanicamente e VISUALMENTE.
1. INSPEÇÃO VISUAL OBRIGATÓRIA: Examine as imagens capturadas do jogo em `media/iter_{{ITER}}/` (ex.: `frame_1.png`, `frame_2.png`, se existirem).
   - Verifique alinhamento, escala e proporção dos sprites (sprites de monstros, armas e portas estão proporcionais ou distorcidos?).
   - Verifique o HUD (as barras de Vida e Vigor, bússola e textos estão sobrepostos ou com falha visual?).
   - Relate visualmente qualquer problema real observado nas imagens.
2. TESTE MECÂNICO: Inspecione o código em `game/` e execute `godot --headless --path game -s res://tests/run_gates.gd` (se os testes existirem).
3. RELATÓRIO DE PROVAS: Escreva o arquivo `relatorio_provas.json` contendo:
   - 'verified': lista de funcionalidades e visuais verificados com sucesso nesta rodada
   - 'visual_findings': observações detalhadas da sua inspeção visual das imagens
   - 'gap': falhas visuais ou mecânicas reais observadas
   - 'all_milestones_passed': true se os 6 marcos (M1 a M6) do GDD estão completos e funcionais; false caso contrário.
Faça o commit 'docs: provas iteracao {{ITER}}' e encerre sua tarefa. Não altere o código do jogo.
