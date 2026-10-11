# ハト爆撃隊 — Webモック

Godot 4 / GDScriptで作った、縦画面の2.5D見下ろしアクション・モックです。PCではマウス、スマートフォンでは指で画面をドラッグしてハトを動かします。指を離すと停止し、フンは自動で投下されます。

## 含まれるもの

- 公園・商店街・駅前の3ステージ（各2分）
- 自動投下、落下予告、着弾範囲、敵の汚れゲージ
- 経験値とレベルアップ時の8種からランダム3択
- 体力、スコア、星1〜3、パンくず報酬
- 3種類×3段階の永続強化とブラウザ内ローカル保存
- カラス、投擲物、傘、鳥よけドローンなどの妨害
- リザルト、リトライ、生成効果音、軽量なプリミティブ描画

## Godotで実行

Godot 4.5以降でこのフォルダーの `project.godot` を開き、F6/F5で実行します。

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
