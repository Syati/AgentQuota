# AgentQuota

Codex と Claude Code の利用量をメニューバーで確認する、小さなネイティブ macOS アプリです。

## この初期版の安全設計

- Codex は `codex app-server` の `account/rateLimits/read` だけを使用します。
- Claude Code は `~/.claude/rate_limits_cache.json` がある場合だけ読みます。
- Claude の Keychain、OAuth トークン、非公式の Claude usage API は使用しません。
- 自動更新・テレメトリー・ログイン画面はありません。

そのため Claude の表示は空、または最新でないことがあります。正確なClaudeの残量を得るために認証トークンや非公式APIを使う実装は、意図して含めていません。

## 起動

```sh
swift run
```

Command Line Tools ではなくXcodeを使用したい場合、現在のシェルだけで切り替えるには次を実行します。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run
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
