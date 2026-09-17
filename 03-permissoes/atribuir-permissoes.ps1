<#
.SYNOPSIS
    Atribuição e revogação em lote de usuários em grupos de segurança do Active Directory.

.DESCRIPTION
    Colunas do CSV:

        SamAccountName -> login do usuário (obrigatória)
        GrupoDestino   -> SamAccountName do grupo (obrigatória)
        Acao           -> Adicionar | Remover (opcional; ausente = Adicionar)

    O script verifica o estado ANTES de agir, então distingue quatro resultados
    distintos em vez de imprimir "sucesso" para tudo:
        Adicionado | Já era membro | Removido | Não era membro

.NOTES
    Remoção pede confirmação individual. Use -Force para lote não interativo,
    ou -WhatIf para simular sem escrever nada.

.EXAMPLE
    .\atribuir-permissoes.ps1 -WhatIf
#>

#Requires -Modules ActiveDirectory

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$CaminhoCsv = "$PSScriptRoot\atribuicao-de-politicas.csv",
    [string]$Servidor,                                 # ex: dc01.lab.local (opcional)
    [switch]$Force                                     # remove sem confirmar uma a uma
)

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

$Lista = @(Import-Csv -Path $CaminhoCsv -Delimiter ';' -Encoding UTF8)
Write-Host "Processando $($Lista.Count) registros..." -ForegroundColor Yellow

$Relatorio = [System.Collections.Generic.List[object]]::new()

function Add-Registro {
    param($Sam, $Grupo, $Acao, $Status, $Erro = '')
    $script:Relatorio.Add([pscustomobject]@{
        Sam = $Sam; Grupo = $Grupo; Acao = $Acao; Status = $Status; Erro = $Erro
    })
}

# ------------------------------------------------------------------ loop ---

foreach ($Linha in $Lista) {

    $SamUser = $Linha.SamAccountName.Trim()
    $Grupo   = $Linha.GrupoDestino.Trim()

    # coluna Acao é opcional: CSV antigo sem ela continua funcionando
    $Acao = 'Adicionar'
    if ($Linha.PSObject.Properties.Name -contains 'Acao' -and $Linha.Acao.Trim()) {
        $Acao = $Linha.Acao.Trim()
    }

    if (-not $SamUser -or -not $Grupo) {
        Write-Warning "Linha ignorada: SamAccountName ou GrupoDestino vazio."
        continue
    }

    if ($Acao -notin @('Adicionar', 'Remover')) {
        Write-Host "Aviso: ação inválida '$Acao' para [$SamUser]. Use Adicionar ou Remover." -ForegroundColor Red
        Add-Registro $SamUser $Grupo $Acao 'Ação inválida'
        continue
    }

    try {
        # MemberOf traz os DNs dos grupos do usuário: evita Get-ADGroupMember,
        # que fica caro em grupo grande
        $Usuario = Get-ADUser -Filter 'SamAccountName -eq $SamUser' -Properties MemberOf @AD

        if (-not $Usuario) {
            Write-Host "Aviso: usuário '$SamUser' não encontrado." -ForegroundColor Red
            Add-Registro $SamUser $Grupo $Acao 'Usuário não encontrado'
            continue
        }

        # filtra pelo SamAccountName do grupo: Name pode se repetir entre OUs
        $ObjGrupo = @(Get-ADGroup -Filter 'SamAccountName -eq $Grupo' @AD)

        if ($ObjGrupo.Count -eq 0) {
            Write-Host "Aviso: grupo '$Grupo' não encontrado." -ForegroundColor Red
            Add-Registro $SamUser $Grupo $Acao 'Grupo não encontrado'
            continue
        }
        if ($ObjGrupo.Count -gt 1) {
            Write-Host "Aviso: grupo '$Grupo' ambíguo ($($ObjGrupo.Count) resultados)." -ForegroundColor Red
            Add-Registro $SamUser $Grupo $Acao 'Grupo ambíguo'
            continue
        }
        $ObjGrupo = $ObjGrupo[0]

        # nota: MemberOf não reflete o grupo primário (normalmente Domain Users).
        # Grupo primário não se remove por aqui — troca-se o primaryGroupID.
        $JaMembro = $Usuario.MemberOf -contains $ObjGrupo.DistinguishedName

        switch ($Acao) {

            'Adicionar' {
                if ($JaMembro) {
                    Write-Host "Já era membro: [$SamUser] em [$Grupo]. Nada a fazer." -ForegroundColor DarkGray
                    Add-Registro $SamUser $Grupo $Acao 'Já era membro'
                    break
                }
                if ($PSCmdlet.ShouldProcess("$SamUser -> $Grupo", 'Add-ADGroupMember')) {
                    Add-ADGroupMember -Identity $ObjGrupo -Members $Usuario.DistinguishedName @AD
                    Write-Host "Adicionado: [$SamUser] em [$Grupo]." -ForegroundColor Green
                    Add-Registro $SamUser $Grupo $Acao 'Adicionado'
                }
            }

            'Remover' {
                if (-not $JaMembro) {
                    Write-Host "Não era membro: [$SamUser] em [$Grupo]. Nada a fazer." -ForegroundColor DarkGray
                    Add-Registro $SamUser $Grupo $Acao 'Não era membro'
                    break
                }
                if ($PSCmdlet.ShouldProcess("$SamUser -> $Grupo", 'Remove-ADGroupMember')) {
                    # -Confirm do próprio cmdlet fica ativo, a menos que -Force
                    Remove-ADGroupMember -Identity $ObjGrupo `
                                         -Members  $Usuario.DistinguishedName `
                                         -Confirm:(-not $Force) @AD
                    Write-Host "Removido: [$SamUser] de [$Grupo]." -ForegroundColor Magenta
                    Add-Registro $SamUser $Grupo $Acao 'Removido'
                }
            }
        }
    }
    catch {
        Write-Host "ERRO em [$SamUser] / [$Grupo] -> $($_.Exception.Message)" -ForegroundColor Red
        Add-Registro $SamUser $Grupo $Acao 'Falha' $_.Exception.Message
    }
}

# -------------------------------------------------------------- relatório ---

$Log = Join-Path $PSScriptRoot ("log-permissoes-{0:yyyyMMdd-HHmmss}.csv" -f (Get-Date))
$Relatorio | Export-Csv -Path $Log -Delimiter ';' -NoTypeInformation -Encoding UTF8

Write-Host "`nResumo:" -ForegroundColor Cyan
$Relatorio | Group-Object Status | Sort-Object Count -Descending |
    ForEach-Object { Write-Host ("  {0,-22} {1}" -f $_.Name, $_.Count) }

Write-Host "`nProcesso concluído. Relatório: $Log" -ForegroundColor Cyan
