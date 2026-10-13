<#
.SYNOPSIS
    Mini CMDB - coleta hardware e softwares instalados das máquinas da rede.

.DESCRIPTION
    Por padrão, lê a lista de máquinas de maquinas.csv e consulta cada uma remotamente (WinRM),
    em paralelo. Para cada máquina grava dados\maquinas\<ATIVO>.json, registra as mudanças
    (software instalado/removido/atualizado, troca de hardware) em dados\mudancas.csv e o
    resultado de cada tentativa em dados\coletas.csv. No final gera o painel.html.

.EXAMPLE
    .\Coletar-Inventario.ps1
    Coleta todas as máquinas do maquinas.csv (exceto status "Descartado").

.EXAMPLE
    .\Coletar-Inventario.ps1 -ComputerName PC-001, PC-002 -Credential (Get-Credential)
    Coleta só as máquinas informadas, usando outra credencial.

.EXAMPLE
    .\Coletar-Inventario.ps1 -Local
    Coleta a própria máquina onde o script está rodando (útil para máquinas sem WinRM).
#>
[CmdletBinding()]
param(
    [string[]]$ComputerName,
    [System.Management.Automation.PSCredential]$Credential,
    [switch]$Local,
    [int]$ThrottleLimit = 0,
    [switch]$SemPainel,
    [switch]$Gpo
)

$ErrorActionPreference = 'Stop'
$Raiz = $PSScriptRoot

# Modo GPO: cada máquina coleta a si mesma, sem gerar painel (o TI gera depois com Gerar-Painel)
if ($Gpo) {
    $Local = $true; $SemPainel = $true
    # Log local para diagnóstico: C:\ProgramData\MiniCMDB\ultima-coleta.log
    try {
        $pastaLog = Join-Path $env:ProgramData 'MiniCMDB'
        if (-not (Test-Path $pastaLog)) { New-Item -ItemType Directory -Path $pastaLog -Force | Out-Null }
        Start-Transcript -Path (Join-Path $pastaLog 'ultima-coleta.log') -Force | Out-Null
    } catch { }
    Start-Sleep -Seconds (Get-Random -Minimum 0 -Maximum 120)   # espalha as gravações quando muitas máquinas ligam juntas
}
. (Join-Path $Raiz 'lib\Comum.ps1')

$config     = Read-Config $Raiz
$pastaDados = Get-PastaDados $Raiz
$pastaMaq   = Join-Path $pastaDados 'maquinas'
$arqMudanca = Join-Path $pastaDados 'mudancas.csv'
$arqColetas = Join-Path $pastaDados 'coletas.csv'
if ($ThrottleLimit -le 0) { $ThrottleLimit = [int]$config.ThrottleLimit; if ($ThrottleLimit -le 0) { $ThrottleLimit = 16 } }

# ---------------------------------------------------------------------------
# Bloco executado EM CADA MÁQUINA (precisa ser autossuficiente)
# ---------------------------------------------------------------------------
$Coleta = {
    $ErrorActionPreference = 'SilentlyContinue'
    function Fmt($d) { if ($d) { ([datetime]$d).ToString('yyyy-MM-dd HH:mm') } else { $null } }

    $cs   = Get-CimInstance Win32_ComputerSystem
    $os   = Get-CimInstance Win32_OperatingSystem
    $bios = Get-CimInstance Win32_BIOS
    $cpu  = @(Get-CimInstance Win32_Processor)[0]
    $enc  = Get-CimInstance Win32_SystemEnclosure

    $tipo = 'Desktop'
    $chassis = @($enc.ChassisTypes)
    if ($chassis | Where-Object { $_ -in 8,9,10,11,12,14,18,21,30,31,32 }) { $tipo = 'Notebook' }
    elseif ($cs.Model -match 'Virtual|VMware|KVM|HVM') { $tipo = 'Virtual' }

    $discos = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
        [pscustomobject]@{
            Unidade  = $_.DeviceID
            TotalGB  = [math]::Round($_.Size / 1GB, 1)
            LivreGB  = [math]::Round($_.FreeSpace / 1GB, 1)
        }
    })
    $discoFisico = @(Get-CimInstance Win32_DiskDrive | ForEach-Object {
        [pscustomobject]@{ Modelo = $_.Model; TamanhoGB = [math]::Round($_.Size / 1GB, 0) }
    })
    try {
        $tiposMidia = @{ 3 = 'HDD'; 4 = 'SSD'; 5 = 'SCM' }
        $fis = @(Get-PhysicalDisk | ForEach-Object { $tiposMidia[[int]$_.MediaType] } | Where-Object { $_ })
        if ($fis.Count -gt 0) { $tipoDisco = ($fis | Select-Object -Unique) -join '/' } else { $tipoDisco = $null }
    } catch { $tipoDisco = $null }

    $rede = @(Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=True' | ForEach-Object {
        [pscustomobject]@{
            Descricao = $_.Description
            IP        = (@($_.IPAddress) | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' }) -join ', '
            MAC       = $_.MACAddress
        }
    })

    # Softwares: máquina (64 e 32 bits) + usuários com perfil carregado
    $chaves = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    Get-ChildItem 'Registry::HKEY_USERS' | Where-Object { $_.PSChildName -match '^S-1-5-21-[\d-]+$' } | ForEach-Object {
        $chaves += "Registry::HKEY_USERS\$($_.PSChildName)\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    }
    $vistos = @{}
    $softwares = @(foreach ($ch in $chaves) {
        Get-ItemProperty $ch | Where-Object {
            $_.DisplayName -and -not $_.SystemComponent -and -not $_.ParentKeyName -and
            $_.DisplayName -notmatch '^(Security Update|Update for|Hotfix|KB\d+)'
        } | ForEach-Object {
            $nome = ([string]$_.DisplayName).Trim()
            if (-not $vistos.ContainsKey($nome)) {
                $vistos[$nome] = $true
                $data = $null
                $id = [string]$_.InstallDate
                if ($id -match '^\d{8}$') { $data = '{0}-{1}-{2}' -f $id.Substring(0,4), $id.Substring(4,2), $id.Substring(6,2) }
                [pscustomobject]@{
                    Nome       = $nome
                    Versao     = [string]$_.DisplayVersion
                    Fabricante = [string]$_.Publisher
                    Instalado  = $data
                }
            }
        }
    }) | Sort-Object Nome

    $ultimoPatch = Get-CimInstance Win32_QuickFixEngineering | Where-Object { $_.InstalledOn } |
        Sort-Object InstalledOn -Descending | Select-Object -First 1

    $usuario = $cs.UserName
    if (-not $usuario) {
        $explorer = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" | Select-Object -First 1
        if ($explorer) { $o = Invoke-CimMethod -InputObject $explorer -MethodName GetOwner; if ($o.User) { $usuario = "$($o.Domain)\$($o.User)" } }
    }

    [pscustomobject]@{
        Hostname       = $env:COMPUTERNAME
        Dominio        = $cs.Domain
        UsuarioLogado  = $usuario
        Fabricante     = $cs.Manufacturer
        Modelo         = $cs.Model
        Tipo           = $tipo
        NumeroSerie    = $bios.SerialNumber
        BIOS           = $bios.SMBIOSBIOSVersion
        Processador    = ($cpu.Name -replace '\s+', ' ').Trim()
        Nucleos        = $cpu.NumberOfCores
        MemoriaGB      = [math]::Round($cs.TotalPhysicalMemory / 1GB, 0)
        TipoDisco      = $tipoDisco
        Discos         = $discos
        DiscosFisicos  = $discoFisico
        SistemaOp      = $os.Caption
        VersaoSO       = $os.Version
        Build          = $os.BuildNumber
        Arquitetura    = $os.OSArchitecture
        SOInstaladoEm  = Fmt $os.InstallDate
        UltimoBoot     = Fmt $os.LastBootUpTime
        UltimoPatch    = Fmt $ultimoPatch.InstalledOn
        UltimoPatchKB  = $ultimoPatch.HotFixID
        Rede           = $rede
        Softwares      = $softwares
    }
}

# ---------------------------------------------------------------------------
# Comparação com a coleta anterior (gera o histórico de mudanças)
# ---------------------------------------------------------------------------
function Compare-Coleta {
    param($Ativo, $Anterior, $Atual, [string]$Data)
    $mud = New-Object System.Collections.Generic.List[object]
    if (-not $Anterior) {
        $mud.Add([pscustomobject]@{ Data = $Data; Ativo = $Ativo; Tipo = 'Primeira coleta'; Item = "$(@($Atual.Softwares).Count) softwares"; Antes = ''; Depois = '' })
        return $mud
    }
    $antes = @{}; foreach ($s in @($Anterior.Softwares)) { $antes[$s.Nome] = [string]$s.Versao }
    $depois = @{}; foreach ($s in @($Atual.Softwares)) { $depois[$s.Nome] = [string]$s.Versao }
    foreach ($n in $depois.Keys) {
        if (-not $antes.ContainsKey($n)) { $mud.Add([pscustomobject]@{ Data = $Data; Ativo = $Ativo; Tipo = 'Software instalado'; Item = $n; Antes = ''; Depois = $depois[$n] }) }
        elseif ($antes[$n] -ne $depois[$n]) { $mud.Add([pscustomobject]@{ Data = $Data; Ativo = $Ativo; Tipo = 'Software atualizado'; Item = $n; Antes = $antes[$n]; Depois = $depois[$n] }) }
    }
    foreach ($n in $antes.Keys) {
        if (-not $depois.ContainsKey($n)) { $mud.Add([pscustomobject]@{ Data = $Data; Ativo = $Ativo; Tipo = 'Software removido'; Item = $n; Antes = $antes[$n]; Depois = '' }) }
    }
    foreach ($campo in 'NumeroSerie', 'Modelo', 'Processador', 'MemoriaGB', 'SistemaOp', 'Build', 'UsuarioLogado') {
        $a = [string]$Anterior.$campo; $d = [string]$Atual.$campo
        if ($campo -eq 'UsuarioLogado' -and -not $d) { continue }   # ninguém logado não é mudança
        if ($a -ne $d) { $mud.Add([pscustomobject]@{ Data = $Data; Ativo = $Ativo; Tipo = 'Alteração'; Item = $campo; Antes = $a; Depois = $d }) }
    }
    return $mud
}

function Save-Resultado {
    param([string]$Ativo, $Resultado)
    $agora = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    $arq = Join-Path $pastaMaq ("{0}.json" -f $Ativo)
    $anterior = $null
    if (Test-Path $arq) { try { $anterior = Read-TextoAuto $arq | ConvertFrom-Json } catch { $anterior = $null } }

    $obj = $Resultado | Select-Object * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName
    $obj | Add-Member -NotePropertyName Ativo -NotePropertyValue $Ativo -Force
    $obj | Add-Member -NotePropertyName ColetadoEm -NotePropertyValue $agora -Force
    $obj.Softwares = @($obj.Softwares | Select-Object Nome, Versao, Fabricante, Instalado)

    $mud = @(Compare-Coleta -Ativo $Ativo -Anterior $anterior -Atual $obj -Data $agora)
    Add-LinhaCsv -Caminho $arqMudanca -Objetos $mud
    Write-TextoUtf8 -Caminho $arq -Texto ($obj | ConvertTo-Json -Depth 6)
    return $mud.Count
}

# ---------------------------------------------------------------------------
# Execução
# ---------------------------------------------------------------------------
$log = New-Object System.Collections.Generic.List[object]
$inicio = Get-Date

if ($Local) {
    $ativo = $env:COMPUTERNAME.ToUpper()
    Write-Host "Coletando a máquina local ($ativo)..." -ForegroundColor Cyan
    try {
        $r = & $Coleta
        $n = Save-Resultado -Ativo $ativo -Resultado $r
        $log.Add([pscustomobject]@{ Data = $inicio.ToString('yyyy-MM-dd HH:mm'); Ativo = $ativo; Resultado = 'OK'; Mensagem = "$n mudança(s)" + $(if ($Gpo) { ' (GPO)' } else { '' }) })
    } catch {
        $msg = ($_.Exception.Message -split "`n")[0].Trim()
        $log.Add([pscustomobject]@{ Data = $inicio.ToString('yyyy-MM-dd HH:mm'); Ativo = $ativo; Resultado = 'FALHA'; Mensagem = "Coleta local: $msg" })
        Write-Host "  [FALHA] $msg" -ForegroundColor Yellow
    }
}
else {
    if (-not $ComputerName -or $ComputerName.Count -eq 0) {
        $ComputerName = @(Read-Maquinas $Raiz | Where-Object { $_.Status -notmatch 'Descartad|Baixad' } | ForEach-Object { $_.Ativo })
    }
    $alvos = @($ComputerName | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ } | Select-Object -Unique)
    if ($alvos.Count -eq 0) { throw 'Nenhuma máquina para coletar. Copie maquinas.exemplo.csv para maquinas.csv e preencha, ou use -ComputerName.' }

    Write-Host ("Coletando {0} máquina(s) em paralelo (até {1} por vez)..." -f $alvos.Count, $ThrottleLimit) -ForegroundColor Cyan
    $params = @{
        ComputerName  = $alvos
        ScriptBlock   = $Coleta
        ThrottleLimit = $ThrottleLimit
        ErrorAction   = 'SilentlyContinue'
        ErrorVariable = 'errosRemotos'
    }
    if ($Credential) { $params.Credential = $Credential }
    $resultados = @(Invoke-Command @params)

    $porNome = @{}
    foreach ($r in $resultados) { $porNome[([string]$r.PSComputerName).ToUpper()] = $r }

    foreach ($a in $alvos) {
        $data = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        if ($porNome.ContainsKey($a)) {
            $n = Save-Resultado -Ativo $a -Resultado $porNome[$a]
            Write-Host ("  [OK]    {0}  ({1} mudança(s))" -f $a, $n) -ForegroundColor Green
            $log.Add([pscustomobject]@{ Data = $data; Ativo = $a; Resultado = 'OK'; Mensagem = "$n mudança(s)" })
        } else {
            $erro = @($errosRemotos | Where-Object { $_.ToString() -match [regex]::Escape($a) -or [string]$_.TargetObject -eq $a }) | Select-Object -First 1
            $msg = 'Sem resposta'
            if ($erro) {
                $txt = $erro.ToString()
                if     ($txt -match 'cannot find the computer|não é possível localizar|WinRM cannot complete|não pôde concluir') { $msg = 'Offline ou nome não encontrado na rede' }
                elseif ($txt -match 'Access is denied|Acesso negado')                                                       { $msg = 'Acesso negado (credencial sem permissão de admin)' }
                elseif ($txt -match 'WinRM|firewall')                                                                       { $msg = 'WinRM desabilitado ou bloqueado no firewall' }
                else   { $msg = ($txt -split "`n")[0].Trim() }
                if ($msg.Length -gt 200) { $msg = $msg.Substring(0, 200) }
            }
            Write-Host ("  [FALHA] {0}  - {1}" -f $a, $msg) -ForegroundColor Yellow
            $log.Add([pscustomobject]@{ Data = $data; Ativo = $a; Resultado = 'FALHA'; Mensagem = $msg })
        }
    }
}

Add-LinhaCsv -Caminho $arqColetas -Objetos $log.ToArray()
$ok = @($log | Where-Object Resultado -eq 'OK').Count
Write-Host ("Concluído: {0} OK, {1} falha(s) em {2:N0}s." -f $ok, ($log.Count - $ok), ((Get-Date) - $inicio).TotalSeconds) -ForegroundColor Cyan

if (-not $SemPainel) { & (Join-Path $Raiz 'Gerar-Painel.ps1') }
if ($Gpo) { try { Stop-Transcript | Out-Null } catch { } }
