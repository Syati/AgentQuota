# AgentQuota

Codex と Claude Code の利用枠をメニューバーで確認する、小さなネイティブ macOS アプリです。

![AgentQuota](docs/screenshots/agentquota-main.png)

## 機能

- メニューバーに `Cdx 86% · Cl 21%` のような概要を表示
- ホバー時に5時間枠と週次枠を表示
- Codex と Claude Code を表形式・プログレスバーで表示
- 既存の statusline を保持した Claude Code 連携ラッパー
- Claude Code の表示指標（5時間枠・週次枠）を選択
- 設定と About を1つのサイドバー付きウィンドウに集約
- 日本語・英語・システム設定に従う言語切り替え
- ログイン時起動
- 利用率が90%以上のとき警告アイコンを表示

## プライバシーと安全性

- Codex は公式の `codex app-server` の `account/rateLimits/read` だけを使用します。
- Claude Code は公式 statusline コマンドへ渡されるJSONだけを利用します。
- Claude の利用率と復帰時刻だけを `~/Library/Application Support/AgentQuota/` にローカル保存します。
- Keychain、OAuthトークン、非公式のClaude利用量APIにはアクセスしません。
- テレメトリー、ログイン画面、自動通信サービスはありません。

既存の Claude Code statusline が設定されている場合は、元のコマンドを保存し、同じJSONをAgentQuotaと元のコマンドの両方へ渡します。既存の表示を維持したまま連携できます。

## 必要環境

- macOS 14以降
- Xcode または Swiftツールチェーン
- Codex表示には `codex`
- statusline の利用枠入力には Claude Code 2.1.277以降

## ソースから起動

```sh
swift run AgentQuota
```

現在のシェルだけXcodeのツールチェーンを使う場合:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run AgentQuota
```

## Claude Code連携

**設定 → Claude Code連携**を開き、表示したい利用枠を選択します。既存の statusline コマンドがある場合はコマンド欄に残したまま、**既存の statusline と連携**を選びます。AgentQuotaがラッパーを作成し、元のコマンドにも同じJSON入力を渡します。

Claude Code の statusline を公式のデータ連携口として使用します。非公開の利用量エンドポイントや認証情報は使用しません。

## DMGを作成

```sh
./scripts/package_dmg.sh 0.2.0
```

`dist/AgentQuota-0.2.0.dmg` が生成されます。アプリはad-hoc署名で、Appleによる公証はありません。

## ライセンス

現在、別個のライセンスファイルはありません。

English: [README.md](README.md)
