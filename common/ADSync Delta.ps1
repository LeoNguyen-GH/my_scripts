write-host "Invoking ADSync type Delta" -foregroundcolor Cyan
Invoke-Command -ComputerName ADC_01 -ScriptBlock {
    Start-ADSyncSyncCycle -PolicyType Delta
}
start-sleep 1