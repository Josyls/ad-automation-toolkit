# 1. Pede credenciais de Administrador de forma segura para a sessão
Write-Host "Insira suas credenciais de Administrador do AD:" -ForegroundColor Cyan
$Credencial = Get-Credential

# 2. Importa o arquivo CSV de atribuição de políticas/permissões
$CaminhoCsv = "$PSScriptRoot\atribuicao-de-politicas.csv"
$ListaPermissoes = Import-Csv -Path $CaminhoCsv -Delimiter ";"

Write-Host "Processando atribuições para $($ListaPermissoes.Count) registros..." -ForegroundColor Yellow

foreach ($Linha in $ListaPermissoes) {
    $SamUser = $Linha.SamAccountName.Trim()
    $GrupoDestino = $Linha.GrupoDestino.Trim()

    # Verifica se o usuário e o grupo existem no Active Directory
    $ObjUsuario = Get-ADUser -Filter "SamAccountName -eq '$SamUser'" -Credential $Credencial -ErrorAction SilentlyContinue
    $ObjGrupo = Get-ADGroup -Filter "Name -eq '$GrupoDestino'" -Credential $Credencial -ErrorAction SilentlyContinue

    if ($ObjUsuario -and $ObjGrupo) {
        # Adiciona o usuário ao grupo de segurança de forma segura
        Add-ADGroupMember -Identity $ObjGrupo -Members $ObjUsuario -Credential $Credencial -ErrorAction SilentlyContinue
        Write-Host "Sucesso: Usuário [$SamUser] adicionado ao grupo [$GrupoDestino]." -ForegroundColor Green
    } else {
        Write-Host "Aviso: Falha ao processar. Verifique se o usuário '$SamUser' ou o grupo '$GrupoDestino' existem no AD." -ForegroundColor Red
    }
}

Write-Host "Processo de atribuição de permissões concluído!" -ForegroundColor Cyan
