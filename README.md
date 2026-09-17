# 🛠️ Active Directory Automation Toolkit

Conjunto de scripts em PowerShell integrados com arquivos CSV para automatizar e padronizar o ciclo de vida de identidades no Active Directory (AD). Desenvolvido para tornar rotinas de administração de redes mais eficientes, seguras e reutilizáveis.

## 📂 Estrutura do Projeto

O repositório é modularizado para separar claramente cada etapa da administração:

- **01-criacao/** — criação em lote de usuários via CSV, com verificação de duplicidade por login, normalização do `SamAccountName` e atribuição automática de grupo.
- **02-atualizacao/** — atualização de dados cadastrais de usuários existentes, com aplicação parcial (coluna vazia não sobrescreve atributo).
- **03-permissoes/** — atribuição **e revogação** de grupos de segurança, com verificação prévia de estado.

## 🔒 Segurança e Autenticação

- **Nenhuma credencial embutida no código.** A autenticação usa o cmdlet nativo `Get-Credential`, válido estritamente durante a sessão de execução.
- **Senhas iniciais geradas aleatoriamente** por usuário (16 caracteres, com as quatro categorias de complexidade), com troca obrigatória no primeiro logon.
- O relatório de criação contém as senhas iniciais em texto plano para entrega ao usuário. **Esse arquivo está no `.gitignore` e deve ser apagado após a distribuição.**

## ⚙️ Comportamento dos scripts

Os três seguem o mesmo padrão:

| Recurso | Descrição |
|---|---|
| `-WhatIf` | Simula a execução inteira sem escrever nada no AD |
| `try/catch` | O status impresso reflete o resultado real do cmdlet, sem falso positivo |
| Idempotência | Reexecutar o mesmo CSV não duplica nem reescreve o que já está correto |
| Log em CSV | Cada execução gera `log-*.csv` com o resultado linha a linha |
| `-Server` | Permite apontar um controlador de domínio específico |
| `-Encoding UTF8` | Leitura de CSV sem corromper acentos no Windows PowerShell 5.1 |

## 🚀 Como Utilizar

**Pré-requisitos:** PowerShell 5.1+ e o módulo RSAT-AD instalado (`Get-Module -ListAvailable ActiveDirectory`).

1. Clone ou baixe este repositório.
2. Navegue até a pasta da rotina desejada.
3. Preencha o `.csv` correspondente (delimitador `;`, codificação UTF-8).
4. Abra o **PowerShell como Administrador** e simule primeiro:

```powershell
.\criar-usuarios.ps1 -WhatIf
```

5. Confirmada a simulação, execute sem o `-WhatIf`:

```powershell
.\criar-usuarios.ps1
.\criar-usuarios.ps1 -Servidor dc01.lab.local     # DC específico
```

### Colunas dos CSVs

**01-criacao/criacao-de-usuario.csv**
`Nome;Sobrenome;Grupo`

**02-atualizacao/alteracao-de-usuario.csv**
`SamAccountName;NovoSobrenome;NovoDepartamento;NovoCargo;NovoEmail;NovoTelefone`
Apenas `SamAccountName` é obrigatória — colunas vazias são ignoradas, nunca apagam o atributo.

**03-permissoes/atribuicao-de-politicas.csv**
`SamAccountName;GrupoDestino;Acao`
`Acao` aceita `Adicionar` ou `Remover`; se omitida, o padrão é `Adicionar`. Remoções pedem confirmação individual — use `-Force` para lote não interativo.

## ⚠️ Observações de projeto

- O login (`SamAccountName` / UPN) **não muda** quando o sobrenome é alterado. Trocar login em produção quebra perfil de usuário, mapeamento de drive e rastro de auditoria; o correto é manter o login e adicionar um UPN secundário se necessário.
- `SamAccountName` é truncado em 20 caracteres (limite do AD) e normalizado sem acentos ou caracteres inválidos.
- Os grupos referenciados nos CSVs precisam existir previamente no domínio — o toolkit não cria grupos nem OUs.
- Ambiente de referência: domínio de laboratório `lab.local`.

---

Desenvolvido com foco em automação e infraestrutura de TI moderna.
