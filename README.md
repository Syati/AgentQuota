# AgentQuota

Codex と Claude Code の利用量をメニューバーで確認する、小さなネイティブ macOS アプリです。

## この初期版の安全設計

- Codex は `codex app-server` の `account/rateLimits/read` だけを使用します。
- Claude Code は statusline が渡す利用枠情報だけを、`~/Library/Application Support/AgentQuota/` に保存して読みます。
- Claude の Keychain、OAuth トークン、非公式の Claude usage API は使用しません。
- 自動更新・テレメトリー・ログイン画面はありません。

設定画面で既存の statusline コマンドを指定して「既存の statusline と連携」を押すと、AgentQuota のラッパーが同じJSONを元のコマンドとAgentQuotaの両方へ渡します。既存の表示を維持したまま、5時間枠・週次枠から選んだ指標を AgentQuota に保存できます。設定後は Claude Code を一度操作すると利用量が表示されます。

正確なClaudeの残量を得るために認証トークンや非公式APIを使う実装は、意図して含めていません。

## 起動

```sh
swift run AgentQuota
```

Command Line Tools ではなくXcodeを使用したい場合、現在のシェルだけで切り替えるには次を実行します。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run AgentQuota
```

Mac全体でXcodeを標準の開発ツールにするには、ターミナルで次を実行し、macOSのパスワードを入力します。

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

終了はメニューバーのアプリを終了するか、起動したターミナルで `Control-C` を押します。

## DMGの作成

XcodeをインストールしたMacで、リリース番号を渡して実行します。

```sh
./scripts/package_dmg.sh 0.1.0
```

`dist/AgentQuota-0.1.0.dmg` が生成されます。このDMG内のアプリはad-hoc署名であり、Appleによる公証はされていません。

## 今後の候補

- Claude Code の公式で安定した読み取り専用usageコマンドが提供されたら、その経路を追加する。
- App Bundle とログイン時起動を追加する。
- 5時間枠と週次枠を同時に表示する。
