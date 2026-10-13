<#
.SYNOPSIS
    Mini CMDB - gera o painel.html a partir de maquinas.csv + dados coletados.
.DESCRIPTION
    Junta o cadastro manual (maquinas.csv) com as coletas (dados\maquinas\*.json),
    o histórico de mudanças e o log de coletas, e gera um painel.html autônomo
    (abre em qualquer navegador, não precisa de internet nem de servidor).
#>
[CmdletBinding()]
param([string]$Saida)

$ErrorActionPreference = 'Stop'
$Raiz = $PSScriptRoot
. (Join-Path $Raiz 'lib\Comum.ps1')

$config     = Read-Config $Raiz
$pastaDados = Get-PastaDados $Raiz
$pastaMaq   = Join-Path $pastaDados 'maquinas'
if (-not $Saida) { $Saida = Join-Path $Raiz 'painel.html' }

function Read-CsvDados([string]$Arq) {
    if (-not (Test-Path $Arq)) { return @() }
    return @(Read-TextoAuto $Arq | ConvertFrom-Csv -Delimiter ';')
}

# Coletas (último snapshot de cada máquina)
$coletas = @{}
Get-ChildItem -Path $pastaMaq -Filter '*.json' -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        $j = Read-TextoAuto $_.FullName | ConvertFrom-Json
        $chave = ([string]$j.Ativo).ToUpper(); if (-not $chave) { $chave = $_.BaseName.ToUpper() }
        $coletas[$chave] = $j
    } catch { Write-Warning "Arquivo inválido ignorado: $($_.Name)" }
}

# Última tentativa de coleta de cada máquina
$tentativas = @{}
foreach ($l in (Read-CsvDados (Join-Path $pastaDados 'coletas.csv'))) { $tentativas[([string]$l.Ativo).ToUpper()] = $l }

# Cadastro manual + máquinas coletadas que não estão no cadastro
$cadastro = @(Read-Maquinas $Raiz)
$lista = New-Object System.Collections.Generic.List[object]
$noCadastro = @{}
foreach ($m in $cadastro) {
    $noCadastro[$m.Ativo] = $true
    $lista.Add([pscustomobject]@{
        Ativo = $m.Ativo; Responsavel = $m.Responsavel; Departamento = $m.Departamento
        Status = $m.Status; Local = $m.Local; Observacoes = $m.Observacoes
        NoCadastro = $true; Coleta = $coletas[$m.Ativo]; Tentativa = $tentativas[$m.Ativo]
    })
}
foreach ($k in $coletas.Keys) {
    if (-not $noCadastro.ContainsKey($k)) {
        $lista.Add([pscustomobject]@{
            Ativo = $k; Responsavel = ''; Departamento = ''; Status = 'Não cadastrado'; Local = ''; Observacoes = ''
            NoCadastro = $false; Coleta = $coletas[$k]; Tentativa = $tentativas[$k]
        })
    }
}

# Histórico de mudanças (últimas 5000 linhas)
$mudancas = @(Read-CsvDados (Join-Path $pastaDados 'mudancas.csv') | Select-Object -Last 5000)

$dados = [pscustomobject]@{
    GeradoEm           = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    Empresa            = $config.NomeEmpresa
    DiasDesatualizado  = [int]$config.DiasParaConsiderarDesatualizado
    SoftwaresPadrao    = @($config.SoftwaresPadrao)
    SoftwaresProibidos = @($config.SoftwaresProibidos)
    Maquinas           = $lista.ToArray()
    Mudancas           = $mudancas
}

$json = $dados | ConvertTo-Json -Depth 10 -Compress
$json = $json.Replace('</', '<\/')

$template = Read-TextoAuto (Join-Path $Raiz 'lib\painel_template.html')
$html = $template.Replace('__DADOS_CMDB__', $json)
Write-TextoUtf8 -Caminho $Saida -Texto $html -ComBom
Write-Host "Painel gerado: $Saida" -ForegroundColor Green
