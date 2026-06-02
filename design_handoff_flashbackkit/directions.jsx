/* directions.jsx — FlashbackKit Phase 1: three brand directions
   Exports to window: DIRECTIONS, DirectionCard, IntroCard. */

const DIRECTIONS = [
  {
    key: 'A',
    name: 'Instruments',
    jp: '計器系（プロ開発者ツール）',
    concept: '計測器のような、静かな正確さ。',
    persona: ['信頼できる相棒', '精密', '冷静'],
    displayFont: 'var(--sf)',
    typeNote: 'SF Pro（UI）＋ SF Mono（タイムコード・端末情報・バージョン）。数値は等幅で「計器」の信頼感。',
    logoNote: '統一マーク「Time Slice」。時計＝時間、左上の扇形＝直前のN秒。インディゴの扇が計器的な精度を示す。',
    rationale: 'QA の隣には Xcode・Instruments・Sentry がいる。計器のような精密さは「このツールは嘘をつかない」という信頼を最短で伝える。等幅の技術データがエンジニアリング品質を裏打ちする。',
    tradeoff: '冷たく無機質に振れやすい。インディゴは規律を持って一箇所に絞らないと「ただの濃い青アプリ」に見える。',
    light: {
      bg: '#FFFFFF', groupBg: '#F1F2F6', fieldBg: '#F4F5F9', label: '#15161C',
      secondary: '#6E707C', tertiary: '#A8AAB6', separator: '#E2E3EB',
      accent: '#4B53C9', onAccent: '#FFFFFF', ctrl: '#4B53C9', onCtrl: '#FFFFFF', success: '#1F9E6A', warning: '#C9871F', danger: '#D6453B',
    },
    dark: {
      bg: '#0E0E13', groupBg: '#16161D', fieldBg: '#1B1C24', label: '#F2F3F8',
      secondary: '#9A9CA8', tertiary: '#5E606C', separator: '#2A2B35',
      accent: '#838CF0', onAccent: '#0E0E13', ctrl: '#838CF0', onCtrl: '#0E0E13', success: '#46C08A', warning: '#E5A24A', danger: '#F0655B',
    },
  },
  {
    key: 'B',
    name: 'Rewind',
    jp: '時間系（“直前の一瞬”が主役）',
    concept: '時間を巻き戻して、その一瞬を掴む。',
    persona: ['機敏', '逃さない', 'ひと匙の心地よさ'],
    displayFont: 'var(--round)',
    typeNote: 'SF Pro Rounded（見出し）＋ SF Mono（タイムコード）。丸みで親しみ、巻き戻る時間が主人公。',
    logoNote: '統一マーク「Time Slice」。扇形＝巻き戻して掴んだ“直前”。アンバーの扇で時間の温度を添える。',
    rationale: 'ブランドの核「時間を巻き戻す」をそのまま主役に。トリム＝この製品の魂であり、捕まえた“一瞬”を温かいアンバーで示すことで、量産的な開発者ツールと差別化できる。',
    tradeoff: '温かさは「消費者向け」に寄りやすく、QA の信頼を損なうリスク。アンバーは白地で線が薄くなるため、ティント用は一段深い色で運用する必要がある。',
    light: {
      bg: '#FBFAF7', groupBg: '#F4F1EA', fieldBg: '#F5F2EB', label: '#1E1A16',
      secondary: '#756E63', tertiary: '#ABA496', separator: '#E7E2D8',
      accent: '#BE7A1E', onAccent: '#FFFFFF', ctrl: '#BE7A1E', onCtrl: '#FFFFFF', success: '#2E9E69', warning: '#BE7A1E', danger: '#CE4A38',
    },
    dark: {
      bg: '#131011', groupBg: '#1E1A18', fieldBg: '#221D1A', label: '#F6F2EC',
      secondary: '#A99F92', tertiary: '#6A6157', separator: '#322B27',
      accent: '#E5A23B', onAccent: '#1E1410', ctrl: '#E5A23B', onCtrl: '#1E1410', success: '#46C08A', warning: '#E5A23B', danger: '#EC6552',
    },
  },
  {
    key: 'C',
    name: 'Quiet',
    jp: '中立系（ミニマル・システム準拠）',
    concept: '見えないほど自然に。邪魔をしない。',
    persona: ['透明', '非干渉', 'システム純正'],
    displayFont: 'var(--sf)',
    typeNote: 'SF Pro 単独・Dynamic Type 準拠。タイムコードも等幅数字で、独自フォントを足さない。',
    logoNote: '統一マーク「Time Slice」。時計＋扇のみ。スレートで主張せず、システムに溶ける。操作系の差し色は Rewind 由来の温かいアンバー＝静止した時間に一点の体温。',
    rationale: 'SDK はホストアプリの上に薄く乗る。iOS そのものの一部に見えるほど中立であれば摩擦が最小で、どんなホストの世界観にも溶ける。最も安全で「純正」な選択。',
    tradeoff: 'ブランドの記憶残存性・固有性は最も低い。🐞ボタンやトーストの個性も控えめになり、製品の“顔”が立ちにくい。',
    light: {
      bg: '#FFFFFF', groupBg: '#F2F2F7', fieldBg: '#F2F2F7', label: '#000000',
      secondary: '#8E8E93', tertiary: '#B8B8BE', separator: '#E3E3E8',
      accent: '#5B6472', onAccent: '#FFFFFF', ctrl: '#D9821C', onCtrl: '#FFFFFF', success: '#34C759', warning: '#FF9F0A', danger: '#FF3B30',
    },
    dark: {
      bg: '#000000', groupBg: '#1C1C1E', fieldBg: '#1C1C1E', label: '#FFFFFF',
      secondary: '#98989F', tertiary: '#5A5A5F', separator: '#2C2C2E',
      accent: '#8B94A3', onAccent: '#111316', ctrl: '#E8A23E', onCtrl: '#2A1B08', success: '#30D158', warning: '#FF9F0A', danger: '#FF453A',
    },
  },
];

// card chrome colors (the canvas card itself, neutral)
const CARD = { ink: '#23242B', sub: '#6A6B74', rule: '#ECECEF', faint: '#F7F7F9' };

function Pill({ children, c = CARD.sub }) {
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', padding: '4px 10px', borderRadius: 13,
      background: CARD.faint, border: `1px solid ${CARD.rule}`, fontSize: 11.5, fontWeight: 600,
      color: c, fontFamily: 'var(--sf)',
    }}>{children}</span>
  );
}

function Block({ label, children, top = true }) {
  return (
    <div style={{ borderTop: top ? `1px solid ${CARD.rule}` : 'none', paddingTop: top ? 22 : 0, marginTop: top ? 22 : 0 }}>
      {label && <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: '0.08em', textTransform: 'uppercase', color: CARD.sub, marginBottom: 14, fontFamily: 'var(--sf)' }}>{label}</div>}
      {children}
    </div>
  );
}

function LogoCell({ d, scheme }) {
  const t = d[scheme];
  return (
    <div style={{ flex: 1, borderRadius: 14, background: t.bg, border: `1px solid ${scheme === 'light' ? CARD.rule : '#000'}`, padding: '20px 22px', display: 'flex', alignItems: 'center', gap: 14 }}>
      <LogoMark d={d} scheme={scheme} size={42} />
      <div style={{ display: 'flex', flexDirection: 'column', gap: 5 }}>
        <Wordmark d={d} scheme={scheme} size={21} />
        <span style={{ fontSize: 10.5, fontFamily: 'var(--mono)', color: t.secondary }}>Recall the moment before the bug.</span>
      </div>
    </div>
  );
}

function swatches(t, key) {
  const base = [
    { name: 'Accent', c: t.accent },
    { name: 'Background', c: t.bg },
    { name: 'Surface', c: t.groupBg },
    { name: 'Label', c: t.label },
    { name: 'Success', c: t.success },
    { name: 'Warning', c: t.warning },
    { name: 'Danger', c: t.danger },
  ];
  if (t.ctrl && t.ctrl !== t.accent) base.splice(1, 0, { name: 'Control', c: t.ctrl });
  return base;
}

function DirectionCard({ d }) {
  return (
    <div style={{ width: '100%', height: '100%', background: '#fff', padding: 28, boxSizing: 'border-box', fontFamily: 'var(--sf)', color: CARD.ink, overflow: 'hidden' }}>
      {/* header */}
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 16 }}>
        <div style={{ width: 44, height: 44, borderRadius: 12, background: d.light.accent, color: d.light.onAccent, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 22, fontWeight: 700, flex: '0 0 auto', fontFamily: d.displayFont }}>{d.key}</div>
        <div style={{ flex: 1 }}>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, flexWrap: 'wrap' }}>
            <span style={{ fontSize: 26, fontWeight: 700, letterSpacing: '-0.02em', color: CARD.ink, fontFamily: d.displayFont }}>{d.name}</span>
            <span style={{ fontSize: 13, color: CARD.sub }}>{d.jp}</span>
          </div>
          <div style={{ fontSize: 17, color: CARD.ink, marginTop: 6, fontWeight: 500 }}>「{d.concept}」</div>
          <div style={{ display: 'flex', gap: 7, marginTop: 12, flexWrap: 'wrap' }}>
            {d.persona.map((p) => <Pill key={p}>{p}</Pill>)}
          </div>
        </div>
      </div>

      {/* logo */}
      <Block label="ロゴ / Logo">
        <div style={{ display: 'flex', gap: 14 }}>
          <LogoCell d={d} scheme="light" />
          <LogoCell d={d} scheme="dark" />
        </div>
        <div style={{ fontSize: 12.5, color: CARD.sub, marginTop: 12, lineHeight: 1.5 }}>{d.logoNote}</div>
      </Block>

      {/* palette */}
      <Block label="カラーパレット / Color">
        <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          <div>
            <div style={{ fontSize: 11, fontWeight: 600, color: CARD.sub, marginBottom: 8 }}>Light</div>
            <SwatchStrip items={swatches(d.light, 'light')} labelColor={CARD.ink} />
          </div>
          <div>
            <div style={{ fontSize: 11, fontWeight: 600, color: CARD.sub, marginBottom: 8 }}>Dark</div>
            <SwatchStrip items={swatches(d.dark, 'dark')} labelColor={CARD.ink} />
          </div>
        </div>
      </Block>

      {/* type */}
      <Block label="タイポグラフィ / Type">
        <div style={{ display: 'flex', alignItems: 'center', gap: 20 }}>
          <div style={{ fontFamily: d.displayFont, fontSize: 40, fontWeight: 700, color: CARD.ink, lineHeight: 1, letterSpacing: '-0.02em' }}>Aa</div>
          <div style={{ height: 44, width: 1, background: CARD.rule }} />
          <div style={{ fontFamily: 'var(--mono)', fontSize: 17, color: CARD.ink, fontVariantNumeric: 'tabular-nums' }}>0:00&nbsp;~&nbsp;0:12<div style={{ fontSize: 12, color: CARD.sub, marginTop: 4 }}>iOS&nbsp;18.4&nbsp;·&nbsp;v1.0&nbsp;(1)</div></div>
        </div>
        <div style={{ fontSize: 12.5, color: CARD.sub, marginTop: 14, lineHeight: 1.5 }}>{d.typeNote}</div>
      </Block>

      {/* reportview */}
      <Block label="ReportView プレビュー（ライト / ダーク）">
        <div style={{ display: 'flex', gap: 20, justifyContent: 'center' }}>
          <PhoneReportView d={d} scheme="light" />
          <PhoneReportView d={d} scheme="dark" />
        </div>
      </Block>

      {/* trigger + toast */}
      <Block label="トリガー & トースト">
        <TriggerToast d={d} scheme="light" />
      </Block>

      {/* rationale */}
      <Block label="根拠 / トレードオフ">
        <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
          <div>
            <div style={{ fontSize: 12.5, fontWeight: 700, color: d.light.accent, marginBottom: 5 }}>なぜ FlashbackKit に合うか</div>
            <div style={{ fontSize: 13, color: CARD.ink, lineHeight: 1.6 }}>{d.rationale}</div>
          </div>
          <div>
            <div style={{ fontSize: 12.5, fontWeight: 700, color: CARD.sub, marginBottom: 5 }}>トレードオフ</div>
            <div style={{ fontSize: 13, color: CARD.sub, lineHeight: 1.6 }}>{d.tradeoff}</div>
          </div>
        </div>
      </Block>
    </div>
  );
}

function IntroCard() {
  const Item = ({ children }) => (
    <li style={{ fontSize: 13.5, color: '#3a3b42', lineHeight: 1.6, marginBottom: 7, paddingLeft: 18, position: 'relative' }}>
      <span style={{ position: 'absolute', left: 0, top: 9, width: 5, height: 5, borderRadius: 3, background: '#BE7A1E' }} />{children}
    </li>
  );
  return (
    <div style={{ width: '100%', height: '100%', background: '#fff', padding: 36, boxSizing: 'border-box', fontFamily: 'var(--sf)', color: CARD.ink, overflow: 'hidden' }}>
      <div style={{ fontSize: 12, fontWeight: 700, letterSpacing: '0.1em', color: '#BE7A1E', marginBottom: 10 }}>PHASE 1 · 方向性の比較</div>
      <div style={{ fontSize: 30, fontWeight: 700, letterSpacing: '-0.02em', lineHeight: 1.15 }}>FlashbackKit<br />ブランド & UI 3 方向</div>
      <div style={{ fontSize: 14, color: CARD.sub, marginTop: 12, lineHeight: 1.6 }}>
        “Recall the moment before the bug.” — 既存の確定 UX を壊さず、QA が思わず使いたくなる方向を 3 案で比較。右の 3 枚を見比べて、1 案を選ぶ／要素を取捨選択してください。各カードは右上 ⤢ で全画面比較できます。
      </div>

      <div style={{ borderTop: `1px solid ${CARD.rule}`, marginTop: 22, paddingTop: 18 }}>
        <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: '0.08em', textTransform: 'uppercase', color: CARD.sub, marginBottom: 12 }}>守る前提（確定事項）</div>
        <ul style={{ margin: 0, padding: 0, listStyle: 'none' }}>
          <Item>出口は「共有」ひとつ。左上は × でキャンセル（送信・自動保存・完了ボタンは無し）。</Item>
          <Item>入力は汎用「タイトル」1 行のみ。端末情報は枠なしのグレー補足。</Item>
          <Item>トリミング＝実アスペクト比プレビュー＋フィルムストリップ＋両端ハンドル＋ループ。</Item>
          <Item>常駐 🐞 フローティングボタン（長押し / ドラッグ / 端タック）＋シェイク＋下中央トースト。</Item>
          <Item>SwiftUI / iOS16+ / ライト&ダーク / SF Symbols / Dynamic Type / VoiceOver 前提。</Item>
        </ul>
      </div>

      <div style={{ borderTop: `1px solid ${CARD.rule}`, marginTop: 20, paddingTop: 18 }}>
        <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: '0.08em', textTransform: 'uppercase', color: CARD.sub, marginBottom: 12 }}>各カードの中身</div>
        <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
          {['ロゴ（L/D）', 'カラートークン', 'タイポ', 'ReportView L/D', '🐞 + トースト', '根拠'].map((x) => <Pill key={x}>{x}</Pill>)}
        </div>
      </div>

      <div style={{ borderTop: `1px solid ${CARD.rule}`, marginTop: 20, paddingTop: 18 }}>
        <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: '0.08em', textTransform: 'uppercase', color: CARD.sub, marginBottom: 10 }}>決めていただきたいこと</div>
        <div style={{ fontSize: 13, color: '#3a3b42', lineHeight: 1.65 }}>
          ① 3 案のどれを軸にするか（混ぜてもOK）。<br />
          ② アクセントは <b>1 色</b>に絞るか、セマンティック色を別途持つか。<br />
          ③ 🐞 アイコンを残すか、抽象マーク（A の括弧 / B の巻き戻し）に寄せるか。<br />
          ④ フォントは純正 SF のみ（C）か、Rounded / Mono を足す（A・B）か。
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { DIRECTIONS, DirectionCard, IntroCard });
