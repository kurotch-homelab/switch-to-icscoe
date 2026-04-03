# switch-to-icscoe
aptが参照するリポジトリをIPA ICSCoE/Cyberlab Public Mirror Serviceに切り替えるスクリプト

## 使い方

### cURLで使う

```bash
curl -fsSL https://raw.githubusercontent.com/kurotch-homelab/switch-to-icscoe/refs/heads/main/switch-to-icscoe.sh | sudo bash
```

### bashで使う

```bash
wget -qO- https://raw.githubusercontent.com/kurotch-homelab/switch-to-icscoe/refs/heads/main/switch-to-icscoe.sh | sudo bash
```

### dry-runする

```bash
curl -fsSL https://raw.githubusercontent.com/kurotch-homelab/switch-to-icscoe/refs/heads/main/switch-to-icscoe.sh | sudo bash -s -- --dry-run
```
