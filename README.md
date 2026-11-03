# YALOG — Gestão de Faturamento e Resultado

Módulo integrado ao YALOG Ecosystem e ao Supabase `yalog-os`.

- ID do catálogo: `gestodefaturamentoeresultado` (preservado do cadastro existente).
- Interface baseada na v53, incluindo impressão A4 e edição do percentual de deduções.
- Nenhum lançamento financeiro é incorporado neste repositório público.
- A entrada exige um handoff válido do Ecosystem e uma liberação ativa da empresa e do usuário.
- Dados e histórico de versões ficam em tabelas privadas no Supabase.
- Salvamento usa controle de versão para impedir sobrescrita entre usuários.

## Publicação

Habilitar GitHub Pages em Settings → Pages → Deploy from a branch → main → /(root).
URL esperada: https://yalog-sistemas.github.io/yalog-faturamento-resultado/

## Administração

Na plataforma YALOG, liberar o módulo para a empresa e cadastrar o usuário em `module_users`. Um usuário MASTER também precisa da autorização individual, conforme a regra atual da plataforma. O acesso ocorre pelo Ecosystem.

A base inicial da Allas é a versão v53 do arquivo local. Lançamentos feitos exclusivamente no navegador do arquivo antigo não são importados automaticamente.

## Arquivos

`index.html`: interface sem dados financeiros. `cloud.js`: entrada e sincronização. `database/schema.sql`: estrutura do banco sem dados de empresas. `manifest.json`: integração do catálogo.

O navegador mantém apenas a sessão e rascunhos pendentes nesta aba. O botão de backup permite guardar uma cópia dos dados. Em caso de conflito, baixar o backup e reabrir o módulo antes de continuar.

## Configurações de usuários

O MASTER da empresa abre Configurações no próprio módulo. Pode cadastrar um login novo (nome e senha inicial de no mínimo 8 caracteres) ou vincular um usuário já existente. Escolhe Visualizador ou Executor, marca uma ou mais áreas e define se o acesso está ativo.

As áreas são Visão Geral, Armazenagem, Transporte e Custos e Despesas. Visão Geral inclui indicadores consolidados; contas detalhadas exigem Custos e Despesas. O Executor grava apenas nas operações autorizadas. O Visualizador consulta e não grava. O usuário entra pelo Ecosystem com o ID da empresa, login e senha. Alterações de acesso invalidam a sessão anterior do módulo.

Administradores MASTER são mantidos pela plataforma YALOG. O cadastro neste módulo concede somente acesso a Gestão de Faturamento e Resultado, sem liberar outros módulos. Desativação nesta tela afeta somente este módulo.

`database/access.sql` complementa `database/schema.sql` e deve ser aplicada uma única vez na base existente. `database/access-tests.sql` testa as permissões em uma transação desfeita ao final.
