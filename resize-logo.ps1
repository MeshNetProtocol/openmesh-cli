# Resize the mesh_logo_mark.png to add proper padding for Android adaptive icons
# The dove should occupy about 72% of the canvas to allow for proper scaling

$sourceImagePath = "D:\worker\openmesh-cli\openmesh-android\app\src\main\res\drawable\mesh_logo_mark.png"
$outputImagePath = "D:\worker\openmesh-cli\openmesh-android\app\src\main\res\drawable\mesh_logo_mark_resized.png"

# Load the original image
Add-Type -AssemblyName System.Drawing
$originalImage = [System.Drawing.Image]::FromFile($sourceImagePath)

# Define the scale factor (72% to add ~14% padding on each side)
$scaleFactor = 0.72

# Calculate new size for the scaled content
$newWidth = [int]($originalImage.Width * $scaleFactor)
$newHeight = [int]($originalImage.Height * $scaleFactor)

# Create a new bitmap with the same dimensions as the original
$resizedBitmap = New-Object System.Drawing.Bitmap($originalImage.Width, $originalImage.Height)

# Create a graphics object for high-quality resizing
$graphics = [System.Drawing.Graphics]::FromImage($resizedBitmap)
$graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$graphics.SmoothingMode = [System.Drawing.SmoothingMode]::HighQuality
$graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

# Calculate the position to center the scaled image
$x = [int](($originalImage.Width - $newWidth) / 2)
$y = [int](($originalImage.Height - $newHeight) / 2)

# Draw the scaled image centered on the new bitmap
$graphics.DrawImage($originalImage, $x, $y, $newWidth, $newHeight)

# Save the resized image
$resizedBitmap.Save($outputImagePath, [System.Drawing.Imaging.ImageFormat]::Png)

# Clean up
$graphics.Dispose()
$resizedBitmap.Dispose()
$originalImage.Dispose()

Write-Host "✓ Successfully resized mesh_logo_mark.png"
Write-Host "  Original size: $($originalImage.Width)x$($originalImage.Height)"
Write-Host "  Dove scaled to: ${scaleFactor}% ($newWidth x $newHeight)"
Write-Host "  Padding added: ~$([int]((1 - $scaleFactor) * 100 / 2))% on each side"
Write-Host "  Output saved to: $outputImagePath"
Write-Host ""
Write-Host "Next steps:"
Write-Host "1. Replace the original mesh_logo_mark.png with the resized version"
Write-Host "2. Rebuild your Android app to see the updated icon"
