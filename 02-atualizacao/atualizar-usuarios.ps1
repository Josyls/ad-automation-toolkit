# 1. Pede credenciais de Administrador de forma segura para a sessão
Write-Host "Insira suas credenciais de Administrador do AD:" -ForegroundColor Cyan
$Credencial = Get-Credential

# 2. Importa o arquivo CSV de alteração
$CaminhoCsv = "$PSScriptRoot\alteracao-de-usuario.csv"
$ListaAtualizacao = Import-Csv -Path $CaminhoCsv -Delimiter ";"

Write-Host "Processando atualizações para $($ListaAtualizacao.Count) usuários..." -ForegroundColor Yellow

foreach ($Linha in $ListaAtualizacao) {
    $SamUser = $Linha.SamAccountName.Trim()
    $NovoSobrenome = $Linha.NovoSobrenome.Trim()
    $NovoDepartamento = $Linha.NovoDepartamento.Trim()

    # Verifica se o usuário existe no AD
    $Usuario = Get-ADUser -Filter "SamAccountName -eq '$SamUser'" -Credential $Credencial -ErrorAction SilentlyContinue

    if ($Usuario) {
        # Atualiza as propriedades no Active Directory
        Set-ADUser -Identity $SamUser -Surname $NovoSobrenome -Department $NovoDepartamento -Credential $Credencial
        Write-Host "Sucesso: Usuário $SamUser atualizado!" -ForegroundColor Green
    } else {
        Write-Host "Aviso: Usuário '$SamUser' não foi encontrado no AD. Ignorando..." -ForegroundColor Yellow
    }
}

Write-Host "Processo de atualização concluído!" -ForegroundColor Cyan