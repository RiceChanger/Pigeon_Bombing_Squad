# ハト爆撃隊 — 3D Webゲーム

Godot 4 / GDScriptで作った、縦画面の3D見下ろしアクションゲームです。PCではマウス、スマートフォンでは指で画面をドラッグしてハトを動かします。攻撃は自動なので、狙い・進化・帰巣の判断に集中できます。

## 含まれるもの

- 低ポリゴンの街を飛ぶ、固定高度・斜め見下ろしの3D画面
- 初期から3方向へ行う自動投下、落下予告、着弾範囲、汚れゲージ
- 中心命中で「連射」、複数命中で「分裂」、コンボで「群れ」へ自動進化
- 進化時のスロー演出、衝撃波、効果音、振動、外見変化、見せ場攻撃
- 命中と時間で増える街の怒りゲージ。最大になる前に巣へ戻れば報酬を確定
- スコア、命中数、最大コンボ、確定／喪失報酬を表示するリザルト
- 最も強かった系統を血統として1つ保存し、次の出撃へ少し継承
- ベストスコア・パンくず・血統のブラウザ内ローカル保存

## Godotで実行

Godot 4.5以降でこのフォルダーの `project.godot` を開き、F5で実行します。

## 自動テスト

```powershell
godot --headless --path . --script res://tests/smoke.gd
```

## Webエクスポート

Webエクスポートテンプレートを導入したGodotで次を実行します。

```powershell
godot --headless --path . --export-release Web build/web/index.html
```

ブラウザのセキュリティ制約により、`index.html` を直接開かずHTTPサーバーで配信してください。

```powershell
python -m http.server 8060 --directory build/web
```

PCでは `http://localhost:8060/`、同じWi-FiのiPhoneでは `http://<PCのLAN内IP>:8060/` をSafariで開きます。iPhoneから接続する場合は、Windowsファイアウォールでポート8060の受信を一時的に許可する必要があります。

## GitHub Pages

`.github/workflows/pages.yml` はGitHub Actions上でGodotのWeb版をビルドし、GitHub Pagesへ公開します。リポジトリの **Settings → Pages → Build and deployment → Source** で **GitHub Actions** を一度選んでください。

公開先: `https://ricechanger.github.io/Pigeon_Bombing_Squad/`

## ライセンス表記

日本語表示のため `assets/fonts/NotoSansCJKjp-Regular.otf` を同梱しています。Noto Sans CJK JP は SIL Open Font License 1.1 で提供され、ライセンス全文は `assets/fonts/OFL.txt` にあります。ゲームコードは別途明示がない限り、このリポジトリ所有者の著作物です。
