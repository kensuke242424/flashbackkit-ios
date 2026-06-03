# FlashbackKit — Brand Assets（ロゴ / アプリ名セット）

確定ブランド方向 **「Quiet」**（Direction C）のロゴ書き出し。実装・配布で使える形（透過 PNG ＋ 編集可能 SVG、ライト/ダーク）。

## 中身
```
brand_assets/
├─ mark/                        マーク単体「Time Slice」（時計＋直前N秒の扇）
│  ├─ flashbackkit-mark-on-light.svg        ← マスター（ベクター・recolor可）
│  ├─ flashbackkit-mark-on-light-1024/512/256/120/80.png  ← 透過PNG
│  ├─ flashbackkit-mark-on-dark.svg
│  └─ flashbackkit-mark-on-dark-1024/512/256/120/80.png   ← 暗背景用（リング白）
├─ lockup/                      横ロックアップ（マーク＋FlashbackKit）
│  ├─ flashbackkit-lockup-on-light.svg      ← マスター（テキストはシステムフォント参照）
│  ├─ flashbackkit-lockup-on-light-2x.png   ← 1839×379 透過
│  ├─ flashbackkit-lockup-on-light-1x.png   ← 920×190 透過
│  ├─ flashbackkit-lockup-on-dark.svg
│  ├─ flashbackkit-lockup-on-dark-2x.png
│  └─ flashbackkit-lockup-on-dark-1x.png
└─ preview.html                 全アセットをライト/ダークで一覧
```

## 色トークン（Quiet）
| 要素 | On-Light | On-Dark |
|---|---|---|
| リング / ハブ（= label）| `#000000` | `#FFFFFF` |
| 扇 wedge（= Action-Orange）| `#D9821C` | `#E8A23E` |
| 「Flashback」（= label）| `#000000` | `#FFFFFF` |
| 「Kit」（= Action-Orange）| `#D9821C` | `#E8A23E` |

色ルール：扇と「Kit」だけが **Action-Orange**（=録画/操作可能）。それ以外は label 色。背景が明るい→on-light、暗い→on-dark を使用。

## マーク（Time Slice）について
- 構成：**リング（円）＋ 左上の扇形（捉えた直前のN秒）＋ 中心ハブ ＋ 12時を指す針（＝“今”）**。viewBox 64、リング r20 / stroke 3.2、扇は上(12時)から反時計回り66°、針は中心→上(y14)、ハブ r2.6。
- iOS 実装では **カスタム `Shape`** で再現（ring/wedge/hub の色・不透明度をパラメータ化＝FAB の録画ON/OFF等の状態にも流用）。PNG はマーケ/ストア/資料用、アプリ内描画は Shape を推奨。
- **クリアスペース**：マーク高さの 1/4 を四辺に確保。**最小サイズ**：画面表示 20pt 以上（FAB の最小実体に準拠）。

## ロックアップ（マーク＋アプリ名）
- 構成：マーク → 余白(フォントサイズ×0.30) → 「Flashback」(label) +「Kit」(Action-Orange)。マーク高 = フォントサイズ×1.18、上下中央揃え。
- **ワードマークのフォント**：SF Pro Text / システムフォント **Bold(700)**、letter-spacing −0.02em。書き出し PNG は再配布可能な system sans（Helvetica/Arial 系）でラスタライズ済み。Apple プラットフォーム上の SVG/実装では `-apple-system`（SF Pro）に解決される。**SF Pro 自体は再配布不可**なので、確定ロゴが要る場合はデザイナーが SF Pro でアウトライン化した版を別途用意してください。
- 余白・最小サイズはマークに準拠。アプリ名のみ縦に積む場合や、マーク単体運用も可。

## 使い分け
- **アプリ内ナビ/ヘッダ**：ワードマークのみ（テキスト）で十分。マークは FAB / 状態表示に。
- **ストア / 資料 / オンボーディング**：lockup（透過 PNG か SVG）。
- **暗背景**：必ず `on-dark`（白リング）を使用。

## 関連
- 正本トークン・状態定義：`design_handoff_flashbackkit/README.md`（`directions.jsx` の `DIRECTIONS[2]` = Quiet）。
- ※ App アイコン（角丸の本番アイコン）はこの中に含みません。必要なら別途作成します。
