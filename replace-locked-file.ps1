# 使用文件流方式替换被锁定的文件

$sourcePath = "D:\worker\openmesh-cli\openmesh-android\app\src\main\res\drawable\mesh_logo_mark_resized.png"
$targetPath = "D:\worker\openmesh-cli\openmesh-android\app\src\main\res\drawable\mesh_logo_mark.png"
$backupPath = "D:\worker\openmesh-cli\openmesh-android\app\src\main\res\drawable\mesh_logo_mark_backup.png"

Write-Host "尝试使用文件流方式替换文件..."

try {
    # 读取源文件内容
    $sourceBytes = [System.IO.File]::ReadAllBytes($sourcePath)
    
    # 备份当前文件（如果可以）
    if ([System.IO.File]::Exists($targetPath)) {
        try {
            [System.IO.File]::Copy($targetPath, $backupPath, $true)
            Write-Host "✓ 已备份原文件"
        } catch {
            Write-Host "⚠ 无法备份原文件（已被锁定）: $_"
        }
    }
    
    # 尝试写入目标文件
    try {
        [System.IO.File]::WriteAllBytes($targetPath, $sourceBytes)
        Write-Host "✓ 成功替换 mesh_logo_mark.png"
        Write-Host "  源文件大小：$($sourceBytes.Length) 字节"
    } catch {
        Write-Host "✗ 无法写入目标文件：$_"
        Write-Host ""
        Write-Host "文件被系统进程锁定。请尝试以下方法："
        Write-Host "1. 重启计算机"
        Write-Host "2. 或者使用 Unlocker 等工具释放文件锁定"
        Write-Host "3. 或者在安全模式下操作"
    }
} catch {
    Write-Host "错误：$_"
}
