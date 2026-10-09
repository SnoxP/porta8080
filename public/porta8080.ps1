& {
    $porta = 8080

    Write-Host "`nVerificando quem está usando a porta $porta...`n" -ForegroundColor Cyan

    try {
        $pids = @(
            Get-NetTCPConnection -LocalPort $porta -State Listen -ErrorAction Stop |
            Select-Object -ExpandProperty OwningProcess -Unique
        )
    }
    catch {
        Write-Host "Não consegui consultar a porta. Tente abrir o PowerShell como administrador." -ForegroundColor Red
        Write-Host "Detalhe: $($_.Exception.Message)"
        return
    }

    if ($pids.Count -eq 0) {
        Write-Host "Nenhum programa está escutando na porta $porta. Tente instalar o plugin." -ForegroundColor Green
        return
    }

    $programas = @()

    foreach ($processoId in $pids) {
        $processo = Get-Process -Id $processoId -ErrorAction SilentlyContinue

        if ($processo) {
            $caminho = ""
            try {
                $caminho = $processo.Path
            }
            catch {
                $caminho = "(caminho indisponível)"
            }

            $servicos = @(
                Get-CimInstance Win32_Service -Filter "ProcessId = $processoId" -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty Name
            ) -join ", "

            $programas += [pscustomobject]@{
                PID      = [int]$processoId
                Nome     = $processo.ProcessName
                Caminho  = $caminho
                Servicos = $servicos
            }
        }
        else {
            $programas += [pscustomobject]@{
                PID      = [int]$processoId
                Nome     = "(processo protegido ou indisponível)"
                Caminho  = ""
                Servicos = ""
            }
        }
    }

    Write-Host "Programas encontrados:" -ForegroundColor Yellow

    for ($i = 0; $i -lt $programas.Count; $i++) {
        $programa = $programas[$i]
        Write-Host "`n[$($i + 1)] $($programa.Nome) — PID $($programa.PID)"

        if ($programa.Caminho) {
            Write-Host "    Arquivo: $($programa.Caminho)" -ForegroundColor DarkGray
        }

        if ($programa.Servicos) {
            Write-Host "    Serviço do Windows: $($programa.Servicos)" -ForegroundColor DarkGray
        }
    }

    Write-Host "`nSalve seu trabalho antes de encerrar qualquer programa." -ForegroundColor Yellow
    $escolha = Read-Host "Digite os números que deseja encerrar, separados por vírgula. Digite N para cancelar"

    if ($escolha.Trim() -match '^(?i:n|nao|não|cancelar)$') {
        Write-Host "Cancelado. Nenhum programa foi encerrado."
        return
    }

    $indices = @()

    foreach ($parte in ($escolha -split ",")) {
        $numero = 0

        if (
            -not [int]::TryParse($parte.Trim(), [ref]$numero) -or
            $numero -lt 1 -or
            $numero -gt $programas.Count
        ) {
            Write-Host "Seleção inválida. Nenhum programa foi encerrado." -ForegroundColor Red
            return
        }

        $indice = $numero - 1
        if ($indices -notcontains $indice) {
            $indices += $indice
        }
    }

    $selecionados = @($indices | ForEach-Object { $programas[$_] })

    Write-Host "`nVocê escolheu encerrar:" -ForegroundColor Yellow
    foreach ($programa in $selecionados) {
        Write-Host " - $($programa.Nome) — PID $($programa.PID)"
    }

    $confirmacao = Read-Host "Confirma? Digite S para continuar"

    if ($confirmacao.Trim() -notmatch '^(?i:s|sim)$') {
        Write-Host "Cancelado. Nenhum programa foi encerrado."
        return
    }

    foreach ($programa in $selecionados) {
        if ($programa.PID -eq 0 -or $programa.PID -eq 4 -or $programa.PID -eq $PID) {
            Write-Host "O PID $($programa.PID) foi ignorado por segurança." -ForegroundColor Red
            continue
        }

        try {
            $processo = Get-Process -Id $programa.PID -ErrorAction Stop

            # Confere se o PID ainda pertence ao mesmo programa listado.
            if ($processo.ProcessName -ne $programa.Nome) {
                Write-Host "O processo mudou desde a verificação. Ignorando o PID $($programa.PID)." -ForegroundColor Yellow
                continue
            }

            # Tenta fechar normalmente se o programa tiver uma janela.
            if ($processo.MainWindowHandle -ne 0) {
                [void]$processo.CloseMainWindow()
                Start-Sleep -Seconds 3
                $processo.Refresh()
            }

            if (-not $processo.HasExited) {
                $forcar = Read-Host "$($programa.Nome) continua aberto. Forçar encerramento? Digite S para confirmar"

                if ($forcar.Trim() -match '^(?i:s|sim)$') {
                    Stop-Process -Id $programa.PID -Force -ErrorAction Stop
                    Write-Host "$($programa.Nome) foi encerrado." -ForegroundColor Green
                }
                else {
                    Write-Host "$($programa.Nome) continua aberto." -ForegroundColor DarkYellow
                }
            }
            else {
                Write-Host "$($programa.Nome) foi fechado normalmente." -ForegroundColor Green
            }
        }
        catch {
            Write-Host "Não foi possível encerrar $($programa.Nome). Talvez seja necessário abrir o PowerShell como administrador." -ForegroundColor Red
        }
    }

    Start-Sleep -Seconds 1

    $restantes = @(
        Get-NetTCPConnection -LocalPort $porta -State Listen -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty OwningProcess -Unique
    )

    if ($restantes.Count -eq 0) {
        Write-Host "`nA porta $porta está livre. Tente instalar o plugin novamente." -ForegroundColor Green
    }
    else {
        Write-Host "`nA porta $porta ainda está em uso. Execute o script novamente para verificar." -ForegroundColor Yellow
    }
}
