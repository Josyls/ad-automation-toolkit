<#
.SYNOPSIS
    Atualização em lote de dados cadastrais de usuários existentes no Active Directory.

.DESCRIPTION
    Lê um CSV e aplica SOMENTE as colunas preenchidas. Coluna vazia = campo não tocado,
    nunca apagado. Colunas suportadas (todas opcionais, exceto SamAccountName):

        SamAccountName   -> identifica o usuário (obrigatória)
        NovoSobrenome    -> Surname   (sincroniza Name e DisplayName)
        NovoDepartamento -> Department
        NovoCargo        -> Title
        NovoEmail        -> EmailAddress
        NovoTelefone     -> OfficePhone

.NOTES
    O login (SamAccountName / UPN) NÃO é alterado quando o sobrenome muda.
    Trocar login em produção quebra perfil de usuário, mapeamento de drive e
    rastro de auditoria. O correto é manter o login e, se necessário,
    adicionar um UPN secundário.

.EXAMPLE
    .\atualizar-usuarios.ps1 -WhatIf
    Mostra o que seria alterado sem escrever nada no AD.
#>

#Requires -Modules ActiveDirectory

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$CaminhoCsv = "$PSScriptRoot\alteracao-de-usuario.csv",
    [string]$Servidor                                  # ex: dc01.lab.local (opcional)
)

# ----------------------------------------------------------------- mapa ---

# coluna do CSV -> atributo do AD
$Mapa = [ordered]@{
    NovoSobrenome    = 'Surname'
    NovoDepartamento = 'Department'
    NovoCargo        = 'Title'
    NovoEmail        = 'EmailAddress'
    NovoTelefone     = 'OfficePhone'
}

# ------------------------------------------------------------ preparação ---

if (-not (Test-Path -LiteralPath $CaminhoCsv)) {
    throw "CSV não encontrado em: $CaminhoCsv"
}

Write-Host "Insira suas credenciais de Administrador do AD:" -ForegroundColor Cyan
$Credencial = Get-Credential

$AD = @{ Credential = $Credencial; ErrorAction = 'Stop' }
if ($Servidor) { $AD.Server = $Servidor }

try {
    $null = Get-ADDomain @AD
} catch {
    throw "Não foi possível conectar ao domínio. Verifique credenciais/-Server. Detalhe: $($_.Exception.Message)"
}

# -Encoding UTF8 é obrigatório no Windows PowerShell 5.1 para não corromper acentos
$Lista = @(Import-Csv -Path $CaminhoCsv -Delimiter ';' -Encoding UTF8)
Write-Host "Processando atualizações para $($Lista.Count) usuários..." -ForegroundColor Yellow

# propriedades que precisam vir preenchidas do AD para comparação
$PropsLeitura = @($Mapa.Values) + @('GivenName', 'DisplayName')

$Relatorio = [System.Collections.Generic.List[object]]::new()

# ------------------------------------------------------------------ loop ---

foreach ($Linha in $Lista) {

    $SamUser = $Linha.SamAccountName.Trim()
    if (-not $SamUser) {
        Write-Warning "Linha ignorada: SamAccountName vazio."
        continue
    }

    $ColunasPresentes = $Linha.PSObject.Properties.Name
    $Alteracoes  = @{}                                      # params do Set-ADUser
    $Descricao   = [System.Collections.Generic.List[string]]::new()

    try {
        # aspas SIMPLES: o provider do AD resolve a variável com segurança,
        # ao contrário da interpolação "$SamUser", que quebra com apóstrofo
        $Usuario = Get-ADUser -Filter 'SamAccountName -eq $SamUser' -Properties $PropsLeitura @AD

        if (-not $Usuario) {
            Write-Host "Aviso: usuário '$SamUser' não encontrado. Ignorando..." -ForegroundColor Yellow
            $Relatorio.Add([pscustomobject]@{
                Sam = $SamUser; Status = 'Não encontrado'; Alteracoes = ''; Erro = ''
            })
            continue
        }

        # monta apenas o que foi realmente preenchido E é diferente do atual
        foreach ($Coluna in $Mapa.Keys) {

            if ($ColunasPresentes -notcontains $Coluna) { continue }

            $NovoValor = $Linha.$Coluna
            if ([string]::IsNullOrWhiteSpace($NovoValor)) { continue }   # <- não apaga atributo

            $NovoValor  = $NovoValor.Trim()
            $Atributo   = $Mapa[$Coluna]
            $ValorAtual = $Usuario.$Atributo

            if ($ValorAtual -eq $NovoValor) { continue }                 # <- idempotente

            $Alteracoes[$Atributo] = $NovoValor
            $Descricao.Add("$Atributo: '$ValorAtual' -> '$NovoValor'")
        }

        # sobrenome novo obriga a sincronizar o nome de exibição e o CN
        $NomeCompleto = $null
        if ($Alteracoes.ContainsKey('Surname')) {
            $NomeCompleto = "$($Usuario.GivenName) $($Alteracoes.Surname)".Trim()

            if ($Usuario.DisplayName -ne $NomeCompleto) {
                $Alteracoes['DisplayName'] = $NomeCompleto
                $Descricao.Add("DisplayName: '$($Usuario.DisplayName)' -> '$NomeCompleto'")
            }
        }

        if ($Alteracoes.Count -eq 0) {
            Write-Host "Sem alteração: $SamUser já está com os dados do CSV." -ForegroundColor DarkGray
            $Relatorio.Add([pscustomobject]@{
                Sam = $SamUser; Status = 'Sem alteração'; Alteracoes = ''; Erro = ''
            })
            continue
        }

        if ($PSCmdlet.ShouldProcess($SamUser, "Set-ADUser [$($Alteracoes.Keys -join ', ')]")) {

            # Set-ADUser ANTES do rename: o rename muda o DN e invalidaria a referência
            Set-ADUser -Identity $Usuario.DistinguishedName @Alteracoes @AD

            if ($NomeCompleto -and $Usuario.Name -ne $NomeCompleto) {
                Rename-ADObject -Identity $Usuario.DistinguishedName -NewName $NomeCompleto @AD
                $Descricao.Add("Name: '$($Usuario.Name)' -> '$NomeCompleto'")
            }

            Write-Host "Sucesso: $SamUser atualizado." -ForegroundColor Green
            foreach ($d in $Descricao) { Write-Host "  -> $d" -ForegroundColor DarkGreen }

            $Relatorio.Add([pscustomobject]@{
                Sam        = $SamUser
                Status     = 'Atualizado'
                Alteracoes = $Descricao -join ' | '
                Erro       = ''
            })
        }
    }
    catch {
        Write-Host "ERRO em $SamUser -> $($_.Exception.Message)" -ForegroundColor Red
        $Relatorio.Add([pscustomobject]@{
            Sam        = $SamUser
            Status     = 'Falha'
            Alteracoes = $Descricao -join ' | '
            Erro       = $_.Exception.Message
        })
    }
}

# -------------------------------------------------------------- relatório ---

$Log = Join-Path $PSScriptRoot ("log-atualizacao-{0:yyyyMMdd-HHmmss}.csv" -f (Get-Date))
$Relatorio | Export-Csv -Path $Log -Delimiter ';' -NoTypeInformation -Encoding UTF8

Write-Host "`nProcesso de atualização concluído. Relatório: $Log" -ForegroundColor Cyan
