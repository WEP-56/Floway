$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add('http://127.0.0.1:18080/')
$listener.Start()
while ($listener.IsListening) {
  try {
    $ctx = $listener.GetContext()
    Start-Sleep -Seconds 4
    $bytes = [Text.Encoding]::UTF8.GetBytes('ok')
    $ctx.Response.StatusCode = 200
    $ctx.Response.ContentLength64 = $bytes.Length
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $ctx.Response.Close()
  } catch { break }
}
