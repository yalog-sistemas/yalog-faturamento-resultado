# Edição das contas e previsão de Comissões

Em Custos e Despesas, cada conta de Transporte e das filiais de Armazenagem usa Editar conta. A janela permite alterar nome/código ou excluir com confirmação. A edição respeita as áreas autorizadas; visualizadores não podem editar.

Comissões do Transporte oferece modo manual ou percentual sobre o faturamento bruto mensal previsto. O percentual é positivo de 0 a 100 e gera despesa negativa, arredondada em centavos. Somente meses a partir do corte de previsão são recalculados; valores realizados permanecem intactos. Alterar a previsão de faturamento atualiza a comissão prevista. Ao voltar ao modo manual, os últimos valores ficam disponíveis para edição.

A configuração fica em forecastRule da própria conta, junto aos custos existentes. Aplicar alterações deixa o rascunho pendente; Salvar e atualizar resultado mantém o fluxo de persistência já utilizado pelo módulo. Não há alteração de dados de clientes durante a publicação.

Deduções preservam a regra de percentual único para todos os meses. Alterar esse percentual exige confirmação sobre o recálculo dos meses realizados; apenas renomear uma dedução não converte lançamentos manuais em percentuais.
