# Native vector drawing; no downloaded artwork or icon dependency.
Add-Type -AssemblyName System.Drawing
$directory=Join-Path $PSScriptRoot 'assets'
New-Item -ItemType Directory -Path $directory -Force | Out-Null
foreach($variant in @('screen-off','screen-off-dark')) {
    $images=@()
    foreach($size in @(16,20,24,32,48,64)) {
        $bitmap=New-Object Drawing.Bitmap($size,$size)
        $graphics=[Drawing.Graphics]::FromImage($bitmap)
        $graphics.SmoothingMode=[Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.ScaleTransform($size/64.0,$size/64.0)
        $baseBrush=New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml('#10263A'))
        $accent=if($variant -eq 'screen-off'){'#57E3C5'}else{'#FFD27A'}
        $pen=New-Object Drawing.Pen([Drawing.ColorTranslator]::FromHtml($accent),4)
        $graphics.FillEllipse($baseBrush,1,1,62,62)
        $graphics.DrawRectangle($pen,12,15,40,29)
        $graphics.DrawLine($pen,32,45,32,50)
        $graphics.DrawLine($pen,23,51,41,51)
        $moon=New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml($accent))
        $graphics.FillEllipse($moon,26,21,16,16)
        $graphics.FillEllipse($baseBrush,32,18,15,15)
        $stream=New-Object IO.MemoryStream
        $bitmap.Save($stream,[Drawing.Imaging.ImageFormat]::Png)
        $images+=,@{Size=$size;Bytes=$stream.ToArray()}
        if($size -eq 64){$bitmap.Save((Join-Path $directory ($variant+'.png')),[Drawing.Imaging.ImageFormat]::Png)}
        $stream.Dispose();$graphics.Dispose();$bitmap.Dispose();$pen.Dispose();$moon.Dispose();$baseBrush.Dispose()
    }
    $file=[IO.File]::Create((Join-Path $directory ($variant+'.ico')))
    $writer=New-Object IO.BinaryWriter($file)
    $writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]$images.Count)
    $offset=6+16*$images.Count
    foreach($entry in $images){
        $writer.Write([byte]$entry.Size);$writer.Write([byte]$entry.Size)
        $writer.Write([byte]0);$writer.Write([byte]0);$writer.Write([uint16]1);$writer.Write([uint16]32)
        $writer.Write([uint32]$entry.Bytes.Length);$writer.Write([uint32]$offset)
        $offset+=$entry.Bytes.Length
    }
    foreach($entry in $images){$writer.Write([byte[]]$entry.Bytes)}
    $writer.Dispose();$file.Dispose()
}
