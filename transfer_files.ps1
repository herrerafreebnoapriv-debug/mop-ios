# 传输 MOP 项目到服务器

$ServerIP = "89.223.95.18"
$ServerPort = "22"
$ServerUser = "root"
$ServerPassword = "uZ8sV4qP3fjH"
$RemotePath = "/opt/mop"
$LocalPath = "C:\Users\robot\Documents\MOP"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  传输 MOP 项目到服务器" -ForegroundColor Cyan
Write-Host "  服务器: ${ServerUser}@${ServerIP}:${ServerPort}" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# 查找私钥文件
$KeyPath = $null
$possibleKeys = @(
    "C:\Users\robot\Documents\jitsi-18-01011\id_rsa_2048",
    "C:\Users\robot\Documents\jitsi-18-01011\id_rsa",
    "C:\Users\robot\.ssh\id_rsa"
)

foreach ($key in $possibleKeys) {
    if (Test-Path $key) {
        $KeyPath = $key
        Write-Host "找到私钥: $key" -ForegroundColor Green
        break
    }
}

# 测试连接
Write-Host "[1/6] 测试 SSH 连接..." -ForegroundColor Yellow
if ($KeyPath) {
    Write-Host "使用密钥连接..." -ForegroundColor Cyan
    $testResult = ssh -i $KeyPath -o ConnectTimeout=10 -o StrictHostKeyChecking=no -p $ServerPort ${ServerUser}@${ServerIP} "echo '连接成功' && whoami" 2>&1
} else {
    Write-Host "使用密码连接（需要手动输入密码: $ServerPassword）..." -ForegroundColor Yellow
    Write-Host "提示: 如果系统支持 sshpass，将自动使用密码" -ForegroundColor Yellow
    $testResult = ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -p $ServerPort ${ServerUser}@${ServerIP} "echo '连接成功' && whoami" 2>&1
}

if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ 连接成功" -ForegroundColor Green
    Write-Host $testResult -ForegroundColor Green
} else {
    Write-Host "✗ 连接失败，错误信息:" -ForegroundColor Red
    Write-Host $testResult -ForegroundColor Red
    Write-Host ""
    Write-Host "请手动执行以下命令测试连接:" -ForegroundColor Yellow
    Write-Host "ssh -p $ServerPort ${ServerUser}@${ServerIP}" -ForegroundColor Cyan
    Write-Host "密码: $ServerPassword" -ForegroundColor Yellow
    exit 1
}
Write-Host ""

# 创建服务器目录
Write-Host "[2/6] 创建服务器目录..." -ForegroundColor Yellow
if ($KeyPath) {
    ssh -i $KeyPath -p $ServerPort ${ServerUser}@${ServerIP} "mkdir -p $RemotePath && chmod 755 $RemotePath"
} else {
    ssh -p $ServerPort ${ServerUser}@${ServerIP} "mkdir -p $RemotePath && chmod 755 $RemotePath"
}
Write-Host "✓ 目录创建完成" -ForegroundColor Green
Write-Host ""

# 传输 app 目录
Write-Host "[3/6] 传输 app/ 目录..." -ForegroundColor Yellow
Write-Host "正在传输，请稍候..." -ForegroundColor Cyan
if ($KeyPath) {
    scp -i $KeyPath -P $ServerPort -r "$LocalPath\app" ${ServerUser}@${ServerIP}:${RemotePath}/
} else {
    scp -P $ServerPort -r "$LocalPath\app" ${ServerUser}@${ServerIP}:${RemotePath}/
}
if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ app/ 目录传输完成" -ForegroundColor Green
} else {
    Write-Host "✗ app/ 目录传输失败" -ForegroundColor Red
    exit 1
}
Write-Host ""

# 传输 scripts 目录
Write-Host "[4/6] 传输 scripts/ 目录..." -ForegroundColor Yellow
if ($KeyPath) {
    scp -i $KeyPath -P $ServerPort -r "$LocalPath\scripts" ${ServerUser}@${ServerIP}:${RemotePath}/
} else {
    scp -P $ServerPort -r "$LocalPath\scripts" ${ServerUser}@${ServerIP}:${RemotePath}/
}
if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ scripts/ 目录传输完成" -ForegroundColor Green
} else {
    Write-Host "✗ scripts/ 目录传输失败" -ForegroundColor Red
    exit 1
}
Write-Host ""

# 传输 alembic 目录
Write-Host "[5/6] 传输 alembic/ 目录..." -ForegroundColor Yellow
if ($KeyPath) {
    scp -i $KeyPath -P $ServerPort -r "$LocalPath\alembic" ${ServerUser}@${ServerIP}:${RemotePath}/
} else {
    scp -P $ServerPort -r "$LocalPath\alembic" ${ServerUser}@${ServerIP}:${RemotePath}/
}
if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ alembic/ 目录传输完成" -ForegroundColor Green
} else {
    Write-Host "✗ alembic/ 目录传输失败" -ForegroundColor Red
    exit 1
}
Write-Host ""

# 传输配置文件
Write-Host "[6/6] 传输配置文件..." -ForegroundColor Yellow
$files = @("requirements.txt", "docker-compose.yml", "alembic.ini", "env.example")
foreach ($file in $files) {
    if (Test-Path "$LocalPath\$file") {
        if ($KeyPath) {
            scp -i $KeyPath -P $ServerPort "$LocalPath\$file" ${ServerUser}@${ServerIP}:${RemotePath}/
        } else {
            scp -P $ServerPort "$LocalPath\$file" ${ServerUser}@${ServerIP}:${RemotePath}/
        }
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ $file 传输完成" -ForegroundColor Green
        }
    }
}

# 传输 static 目录（如果存在）
if (Test-Path "$LocalPath\static") {
    if ($KeyPath) {
        scp -i $KeyPath -P $ServerPort -r "$LocalPath\static" ${ServerUser}@${ServerIP}:${RemotePath}/
    } else {
        scp -P $ServerPort -r "$LocalPath\static" ${ServerUser}@${ServerIP}:${RemotePath}/
    }
    Write-Host "✓ static/ 目录传输完成" -ForegroundColor Green
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  传输完成！" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "下一步操作：" -ForegroundColor Yellow
if ($KeyPath) {
    Write-Host "ssh -i `"$KeyPath`" -p $ServerPort ${ServerUser}@${ServerIP}" -ForegroundColor Cyan
} else {
    Write-Host "ssh -p $ServerPort ${ServerUser}@${ServerIP}" -ForegroundColor Cyan
}
Write-Host "cd $RemotePath" -ForegroundColor Cyan
Write-Host 'chmod +x scripts/deploy_server.sh' -ForegroundColor Cyan
Write-Host 'sudo bash scripts/deploy_server.sh' -ForegroundColor Cyan
Write-Host ""
