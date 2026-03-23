# 重新生成所有分辨率的 Android launcher 图标
# 使用已缩放的 mesh_logo_mark.png 作为源

$sourceImage = "D:\worker\openmesh-cli\openmesh-android\app\src\main\res\drawable\mesh_logo_mark.png"

# 定义所有需要的分辨率
$sizes = @{
    "hdpi" = 72
    "xhdpi" = 96
    "xxhdpi" = 144
    "xxxhdpi" = 192
}

Add-Type -AssemblyName System.Drawing

Write-Host "正在重新生成所有分辨率的 launcher 图标..."
Write-Host ""

# 加载源图片
$originalBitmap = [System.Drawing.Image]::FromFile($sourceImage)

foreach ($sizeEntry in $sizes.GetEnumerator()) {
    $density = $sizeEntry.Key
    $targetSize = $sizeEntry.Value
    
    Write-Host "处理 $density ($targetSize x $targetSize)..."
    
    # 创建目标路径
    $targetDir = "D:\worker\openmesh-cli\openmesh-android\app\src\main\res\mipmap-$density"
    $targetFile = "$targetDir\ic_launcher.png"
    $targetFileRound = "$targetDir\ic_launcher_round.png"
    
    # 备份原文件
    if (Test-Path $targetFile) {
        Copy-Item $targetFile "$targetDir\ic_launcher_backup.png" -Force
    }
    
    # 创建新的位图
    $newBitmap = New-Object System.Drawing.Bitmap($targetSize, $targetSize)
    $graphics = [System.Drawing.Graphics]::FromImage($newBitmap)
    
    # 设置高质量渲染
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.SmoothingMode = [System.Drawing.SmoothingMode]::AntiAlias
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    
    # 绘制缩放的图片（保持居中）
    $graphics.DrawImage($originalBitmap, 0, 0, $targetSize, $targetSize)
    
    # 保存文件
    $newBitmap.Save($targetFile, [System.Drawing.Imaging.ImageFormat]::Png)
    $newBitmap.Save($targetFileRound, [System.Drawing.Imaging.ImageFormat]::Png)
    
    # 清理
    $graphics.Dispose()
    $newBitmap.Dispose()
    
    Write-Host "  ✓ 已生成：$targetFile"
    Write-Host "  ✓ 已生成：$targetFileRound"
}

# 清理
$originalBitmap.Dispose()

Write-Host ""
Write-Host "✓ 所有图标已重新生成完成！"
Write-Host ""
Write-Host "下一步操作："
Write-Host "1. 在 Android Studio 中清理项目：Build → Clean Project"
Write-Host "2. 重新构建项目：Build → Rebuild Project"  
Write-Host "3. 运行应用查看新图标"
