# 🛠️ Active Directory Automation Toolkit

Conjunto de scripts em PowerShell integrados com arquivos CSV para automatizar e padronizar o ciclo de vida de identidades no Active Directory (AD). Desenvolvido para tornar rotinas de administração de redes mais eficientes, seguras e reutilizáveis.

## 📂 Estrutura do Projeto

O repositório é modularizado para separar claramente cada etapa da administração:

- **01-criacao/**: Scripts e modelos para criação em lote de novos usuários via planilha CSV, incluindo verificação de duplicidade por login e atribuição automática de grupos.
- **02-atualizacao/**: Rotinas voltadas para a modificação e atualização de dados cadastrais de usuários já existentes no AD.
- **03-permissoes/**: Módulos focados na gestão de acessos, mapeando usuários a grupos de segurança e políticas específicas.

## 🔒 Segurança e Autenticação

Estes scripts **não contêm credenciais embutidas**. A autenticação é feita de forma totalmente segura através do cmdlet nativo `Get-Credential`, abrindo uma janela interativa para que o administrador insira suas credenciais válidas estritamente durante a sessão de execução.

## 🚀 Como Utilizar

1. Clone ou baixe este repositório para o seu ambiente.
2. Navegue até a pasta da rotina desejada (`01-criacao`, `02-atualizacao` ou `03-permissoes`).
3. Preencha o arquivo `.csv` correspondente com os dados necessários.
4. Abra o **PowerShell como Administrador** (garantindo que o módulo RSAT-AD esteja instalado) e execute o script `.ps1`.

---
Desenvolvido com foco em automação e infraestrutura de TI moderna.

