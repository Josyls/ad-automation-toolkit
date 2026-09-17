<#
.SYNOPSIS
    Criação em lote de usuários no Active Directory a partir de um CSV.
.NOTES
    Versão corrigida. Principais mudanças em relação ao original:
    - ToLower() no lugar do inexistente toLowerCase()
    - senha aleatória por usuário (nada hardcoded) + troca obrigatória no 1º logon
    - try/catch real: só imprime "Sucesso" quando o cmdlet realmente funcionou
    - SamAccountName normalizado (sem acento, sem caractere inválido, máx. 20 chars)
    - -Filter com variável (evita quebra/injeção quando o nome tem apóstrofo)
    - suporte a -WhatIf e log em CSV
#>

#Requires -Modules ActiveDirectory

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$CaminhoCsv = "$PSScriptRoot\criacao-de-usuario.csv",
    [string]$Dominio    = "lab.local",
    [string]$OuDestino  = "CN=Users,DC=lab,DC=local",
    [string]$Servidor                                  # ex: dc01.lab.local (opcional)
)

# ---------------------------------------------------------------- funções ---

function ConvertTo-Login {
    # "Gonçalves D'Ávila" -> "goncalvesdavila"
    param([Parameter(Mandatory)][string]$Texto)

    $decomposto = $Texto.Normalize([Text.NormalizationForm]::FormD)
    $semAcento  = -join ($decomposto.ToCharArray() | Where-Object {
        [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne
            [Globalization.UnicodeCategory]::NonSpacingMark
    })
    return ($semAcento -replace '[^a-zA-Z0-9]', '').ToLower()
}

function New-SenhaAleatoria {
    param([int]$Tamanho = 16)

    $maiusc = [char[]]'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $minusc = [char[]]'abcdefghijkmnopqrstuvwxyz'
    $numero = [char[]]'23456789'
    $simbol = [char[]]'!@#$%&*?-_'
    $todos  = $maiusc + $minusc + $numero + $simbol

    # garante pelo menos 1 de cada categoria (complexidade do AD)
    $chars = @(
        $maiusc | Get-Random
        $minusc | Get-Random
        $numero | Get-Random
        $simbol | Get-Random
    )
    $chars += 1..($Tamanho - 4) | ForEach-Object { $todos | Get-Random }

    return (-join ($chars | Sort-Object { Get-Random }))
}

# ------------------------------------------------------------ preparação ---

if (-not (Test-Path -LiteralPath $CaminhoCsv)) {
    throw "CSV não encontrado em: $CaminhoCsv"
}

Write-Host "Insira suas credenciais de Administrador do AD:" -ForegroundColor Cyan
$Credencial = Get-Credential

# parâmetros comuns a todos os cmdlets do AD (evita repetir -Credential/-Server)
$AD = @{ Credential = $Credencial; ErrorAction = 'Stop' }
if ($Servidor) { $AD.Server = $Servidor }

# teste de conectividade ANTES do loop: falha cedo e com mensagem clara
try {
    $null = Get-ADDomain @AD
} catch {
    throw "Não foi possível conectar ao domínio. Verifique credenciais/-Server. Detalhe: $($_.Exception.Message)"
}

# -Encoding UTF8 é obrigatório no Windows PowerShell 5.1 para não corromper acentos
$ListaUsuarios = @(Import-Csv -Path $CaminhoCsv -Delimiter ';' -Encoding UTF8)
Write-Host "Processando $($ListaUsuarios.Count) usuários..." -ForegroundColor Yellow

$Relatorio = [System.Collections.Generic.List[object]]::new()

# ------------------------------------------------------------------ loop ---

foreach ($Linha in $ListaUsuarios) {

    $Nome         = $Linha.Nome.Trim()
    $Sobrenome    = $Linha.Sobrenome.Trim()
    $GrupoDestino = $Linha.Grupo.Trim()

    if (-not $Nome -or -not $Sobrenome) {
        Write-Warning "Linha ignorada: Nome ou Sobrenome vazio."
        continue
    }

    $UltimoSobrenome = ($Sobrenome -split '\s+')[-1]
    $SamUser         = "{0}.{1}" -f (ConvertTo-Login $Nome), (ConvertTo-Login $UltimoSobrenome)

    # SamAccountName no AD tem limite rígido de 20 caracteres
    if ($SamUser.Length -gt 20) {
        $SamUser = $SamUser.Substring(0, 20).TrimEnd('.')
        Write-Warning "Login truncado para caber no limite de 20 chars: $SamUser"
    }

    $Upn          = "$SamUser@$Dominio"
    $NomeExibicao = "$Nome $Sobrenome"
    $Status       = 'Falha'
    $Detalhe      = ''

    try {
        # aspas SIMPLES: o provider do AD resolve a variável com segurança,
        # ao contrário da interpolação "$SamUser", que quebra com apóstrofo
        if (Get-ADUser -Filter 'SamAccountName -eq $SamUser' @AD) {
            Write-Host "Aviso: '$SamUser' já existe. Ignorando..." -ForegroundColor Yellow
            $Relatorio.Add([pscustomobject]@{
                Sam = $SamUser; Nome = $NomeExibicao; Status = 'Já existia'; Grupo = ''; Senha = ''
            })
            continue
        }

        $SenhaPlana  = New-SenhaAleatoria
        $SenhaSegura = ConvertTo-SecureString $SenhaPlana -AsPlainText -Force

        if ($PSCmdlet.ShouldProcess($SamUser, 'New-ADUser')) {
            New-ADUser -Name                  $NomeExibicao `
                       -DisplayName           $NomeExibicao `
                       -GivenName             $Nome `
                       -Surname               $Sobrenome `
                       -SamAccountName        $SamUser `
                       -UserPrincipalName     $Upn `
                       -Path                  $OuDestino `
                       -AccountPassword       $SenhaSegura `
                       -Enabled               $true `
                       -ChangePasswordAtLogon $true `
                       @AD

            Write-Host "Sucesso: usuário $SamUser criado." -ForegroundColor Green
            $Status = 'Criado'
        }
    }
    catch {
        $Detalhe = $_.Exception.Message
        Write-Host "ERRO ao criar $SamUser -> $Detalhe" -ForegroundColor Red
        $Relatorio.Add([pscustomobject]@{
            Sam = $SamUser; Nome = $NomeExibicao; Status = 'Falha'; Grupo = ''; Senha = ''
        })
        continue   # sem usuário criado, não faz sentido tentar o grupo
    }

    # ------------------------------------------------------------ grupo ---

    $StatusGrupo = 'n/a'
    if ($GrupoDestino) {
        try {
            # filtra por SamAccountName do grupo: Name pode se repetir entre OUs
            $ObjGrupo = Get-ADGroup -Filter 'SamAccountName -eq $GrupoDestino' @AD

            if (-not $ObjGrupo) {
                $StatusGrupo = "Grupo [$GrupoDestino] não encontrado"
                Write-Host "  -> $StatusGrupo" -ForegroundColor Red
            }
            elseif ($ObjGrupo.Count -gt 1) {
                $StatusGrupo = "Grupo [$GrupoDestino] ambíguo ($($ObjGrupo.Count) resultados)"
                Write-Host "  -> $StatusGrupo" -ForegroundColor Red
            }
            else {
                Add-ADGroupMember -Identity $ObjGrupo -Members $SamUser @AD
                $StatusGrupo = 'OK'
                Write-Host "  -> adicionado ao grupo [$GrupoDestino]" -ForegroundColor DarkGreen
            }
        }
        catch {
            $StatusGrupo = $_.Exception.Message
            Write-Host "  -> ERRO no grupo: $StatusGrupo" -ForegroundColor Red
        }
    }

    $Relatorio.Add([pscustomobject]@{
        Sam    = $SamUser
        Nome   = $NomeExibicao
        Status = $Status
        Grupo  = $StatusGrupo
        Senha  = $SenhaPlana      # entregue ao usuário; troca obrigatória no 1º logon
    })
}

# --------------------------------------------------------------- relatório ---

$Log = Join-Path $PSScriptRoot ("log-criacao-{0:yyyyMMdd-HHmmss}.csv" -f (Get-Date))
$Relatorio | Export-Csv -Path $Log -Delimiter ';' -NoTypeInformation -Encoding UTF8

Write-Host "`nProcesso concluído. Relatório: $Log" -ForegroundColor Cyan
Write-Warning "O log contém as senhas iniciais em texto plano. Entregue e apague o arquivo."
