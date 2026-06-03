/* phase2.jsx — FlashbackKit Phase 2 spec boards (Quiet 確定)
   Exports: TokenBoard, SwiftTokenBoard, TriggerUIBoard, FlowBoard.
   Reuses window: PhoneReportView, TriggerToast, CleanMark, Icon, DIRECTIONS. */

(function () {
  const Q = window.DIRECTIONS[2]; // Quiet
  const L = Q.light,D = Q.dark;
  const UI = { ink: '#1c1d24', sub: '#6A6B74', rule: '#ECECEF', faint: '#F7F7F9', orange: L.ctrl };

  const mono = { fontFamily: 'var(--mono)' };
  function H({ children }) {return <div style={{ fontSize: 19, fontWeight: 700, color: UI.ink, letterSpacing: '-0.01em', marginBottom: 4 }}>{children}</div>;}
  function Sub({ children }) {return <div style={{ fontSize: 12.5, color: '#46474f', lineHeight: 1.5, marginBottom: 20 }}>{children}</div>;}
  function Cap({ children }) {return <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: '0.06em', textTransform: 'uppercase', color: UI.sub, marginBottom: 12 }}>{children}</div>;}
  function Sw({ c, ring }) {return <span style={{ display: 'inline-block', width: 18, height: 18, borderRadius: 5, background: c, boxShadow: ring ? 'inset 0 0 0 1px rgba(128,128,128,0.25)' : 'none', verticalAlign: 'middle' }} />;}

  // ── Brand + design tokens ──────────────────────────────────────────────
  const COLOR_ROWS = [
  ['Background', '地', L.bg, D.bg],
  ['Surface', '面・グループ背景', L.groupBg, D.groupBg],
  ['Field', '入力フィールド', L.fieldBg, D.fieldBg],
  ['Separator', '罫線', L.separator, D.separator],
  ['Label', '本文・見出し', L.label, D.label],
  ['Secondary', '補足テキスト', L.secondary, D.secondary],
  ['Tertiary', 'プレースホルダ', L.tertiary, D.tertiary],
  ['Brand (Slate)', 'ブランド中立', L.accent, D.accent],
  ['Action (Amber)', '操作・トリガー・扇', L.ctrl, D.ctrl],
  ['Success', '成功', L.success, D.success],
  ['Warning', '注意', L.warning, D.warning],
  ['Danger', 'エラー', L.danger, D.danger]];

  const TYPE_ROWS = [
  ['Nav Title', 'SF Pro Semibold', '17', 'ナビ「Flashback」'],
  ['Section Header', 'SF Pro Bold', '17', '大見出し（汎用）'],
  ['Body', 'SF Pro Regular', '17', 'タイトル入力値'],
  ['Subhead', 'SF Pro Semibold', '13', '「タイトル」ラベル'],
  ['Timecode', 'SF Mono', '13', '0:00 ~ 0:12（等幅数字）'],
  ['Footnote', 'SF Pro Regular', '13', '環境情報・補足'],
  ['Caption', 'SF Pro Regular', '12', '「環境情報」見出し']];


  function TokenBoard() {
    return (
      <div style={{ width: '100%', height: '100%', background: '#fff', padding: 30, boxSizing: 'border-box', fontFamily: 'var(--sf)', color: UI.ink, overflow: 'hidden' }}>
        <H>ブランドシステム & トークン</H>
        <Sub>Quiet 確定。中立のシステム階調＋唯一のアクション色 <b style={{ color: UI.orange }}>Amber</b>。ロゴは Time Slice「Clean」。</Sub>

        <div style={{ display: 'flex', gap: 36 }}>
          {/* logo + clear space */}
          <div style={{ flex: '0 0 auto' }}>
            <Cap>ロゴ・最小サイズ</Cap>
            <div style={{ display: 'flex', alignItems: 'flex-end', gap: 14, marginBottom: 14 }}>
              {[64, 44, 28, 16].map((s) =>
              <div key={s} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 5 }}>
                  <LogoMark d={Q} scheme="light" size={s} />
                  <span style={{ fontSize: 9, ...mono, color: UI.sub }}>{s}</span>
                </div>
              )}
            </div>
            <div style={{ display: 'flex', gap: 10 }}>
              <div style={{ width: 60, height: 60, borderRadius: 14, background: L.accent, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><CleanMark ring="#fff" wedge={L.ctrl} hub="#fff" size={40} /></div>
              <div style={{ width: 60, height: 60, borderRadius: 30, background: L.ctrl, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><CleanMark ring="#fff" wedge="#fff" wedgeOpacity={0.5} hub="#fff" size={34} /></div>
            </div>
            <div style={{ fontSize: 10.5, color: UI.sub, marginTop: 8, maxWidth: 220, lineHeight: 1.5 }}>余白＝マーク径の 1/4 以上を確保。App アイコン＝スレート地＋オレンジ扇。トリガー＝オレンジ地。</div>
          </div>

          {/* color table */}
          <div style={{ flex: 1 }}>
            <Cap>カラートークン（L / D）</Cap>
            <div style={{ display: 'grid', gridTemplateColumns: '1.4fr 1.4fr 1fr 1fr', rowGap: 7, columnGap: 10, fontSize: 11.5, alignItems: 'center' }}>
              <div style={{ fontWeight: 700, color: UI.sub, fontSize: 10 }}>Token</div>
              <div style={{ fontWeight: 700, color: UI.sub, fontSize: 10 }}>用途</div>
              <div style={{ fontWeight: 700, color: UI.sub, fontSize: 10 }}>Light</div>
              <div style={{ fontWeight: 700, color: UI.sub, fontSize: 10 }}>Dark</div>
              {COLOR_ROWS.map(([n, role, lc, dc]) =>
              <React.Fragment key={n}>
                  <div style={{ fontWeight: 600 }}>{n}</div>
                  <div style={{ color: UI.sub }}>{role}</div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}><Sw c={lc} ring /><span style={{ ...mono, fontSize: 10, color: UI.sub }}>{lc}</span></div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}><Sw c={dc} ring /><span style={{ ...mono, fontSize: 10, color: UI.sub }}>{dc}</span></div>
                </React.Fragment>
              )}
            </div>
          </div>
        </div>

        <div style={{ borderTop: `1px solid ${UI.rule}`, marginTop: 22, paddingTop: 18, display: 'flex', gap: 40 }}>
          <div style={{ flex: 1 }}>
            <Cap>タイポスケール（Dynamic Type 準拠）</Cap>
            <div style={{ display: 'grid', gridTemplateColumns: '1.1fr 1.4fr 0.5fr 1.6fr', rowGap: 6, columnGap: 10, fontSize: 11.5, alignItems: 'baseline' }}>
              {['Style', 'Font', 'pt', '用途'].map((h) => <div key={h} style={{ fontWeight: 700, color: UI.sub, fontSize: 10 }}>{h}</div>)}
              {TYPE_ROWS.map(([s, f, sz, u]) =>
              <React.Fragment key={s}>
                  <div style={{ fontWeight: 600 }}>{s}</div>
                  <div style={{ color: UI.sub }}>{f}</div>
                  <div style={{ ...mono, color: UI.sub }}>{sz}</div>
                  <div style={{ color: UI.sub }}>{u}</div>
                </React.Fragment>
              )}
            </div>
          </div>
          <div style={{ flex: '0 0 auto' }}>
            <Cap>スペーシング & 角丸</Cap>
            <div style={{ display: 'flex', gap: 8, marginBottom: 12 }}>
              {[4, 8, 12, 16, 20, 24].map((s) =>
              <div key={s} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4 }}>
                  <div style={{ width: s, height: s, background: UI.orange, borderRadius: 2 }} />
                  <span style={{ fontSize: 9, ...mono, color: UI.sub }}>{s}</span>
                </div>
              )}
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 5, fontSize: 11, color: UI.sub }}>
              {[['Field / Toast 内', '10'], ['Card / Preview', '14'], ['Trim handle', '9'], ['FAB', '25 (円)'], ['Capsule toast', '22'], ['画面マージン', '16']].map(([k, v]) =>
              <div key={k} style={{ display: 'flex', justifyContent: 'space-between', gap: 16, minWidth: 200 }}><span>{k}</span><span style={{ ...mono, color: UI.ink }}>{v}</span></div>
              )}
            </div>
          </div>
        </div>
      </div>);

  }

  // ── SwiftUI token table ────────────────────────────────────────────────
  function SwiftTokenBoard() {
    const code = `// FlashbackKit — Design Tokens (SwiftUI / iOS 16+)
enum FB {
  enum Color {                       // asset catalog: light / dark
    static let action  = Color("FBAction")   // #D9821C / #E8A23E  ← 操作・トリガー・扇
    static let brand   = Color("FBBrand")    // #5B6472 / #8B94A3  ← ブランド中立
    static let label     = Color(.label)            // 本文・見出し
    static let secondary = Color(.secondaryLabel)   // 補足
    static let tertiary  = Color(.tertiaryLabel)    // placeholder
    static let surface   = Color(.systemGroupedBackground)
    static let field     = Color(.secondarySystemGroupedBackground)
    static let separator = Color(.separator)
    static let success = Color("FBSuccess") // systemGreen 相当
    static let danger  = Color(.systemRed)
  }
  enum Space { static let xs=4.0, s=8.0, m=12.0, l=16.0, xl=20.0, xxl=24.0 }
  enum Radius { static let field=10.0, card=14.0, handle=9.0, fab=25.0, toast=22.0 }
  enum Font {
    static let navTitle = Font.system(size: 17, weight: .semibold)
    static let section  = Font.system(size: 17, weight: .bold)
    static let body     = Font.system(size: 17)
    static let timecode = Font.system(size: 13, design: .monospaced)
                              .monospacedDigit()
    static let footnote = Font.footnote
  }
}

// マーク：時計リング(.label) ＋ 扇(FB.Color.action)。長押しリングは反時計回り充填。
// トリガー：通常=action / 長押し中=action+progress / タック中=Color(.systemGray)+扇のみ点灯`;
    return (
      <div style={{ width: '100%', height: '100%', background: '#0E0E13', padding: 28, boxSizing: 'border-box', fontFamily: 'var(--sf)', overflow: 'hidden' }}>
        <div style={{ fontSize: 18, fontWeight: 700, color: '#F2F3F8', marginBottom: 4 }}>SwiftUI トークン表</div>
        <div style={{ fontSize: 12, color: '#9A9CA8', marginBottom: 16 }}>そのまま実装に落とせる形。色は Asset Catalog（L/D）で持つ。</div>
        <pre style={{ margin: 0, ...mono, fontSize: 11.5, lineHeight: 1.55, color: '#D7D9E4', whiteSpace: 'pre-wrap' }}>{code}</pre>
      </div>);

  }

  // ── Toasts + 準備中 HUD ─────────────────────────────────────────────────
  function Capsule({ kind, msg, action }) {
    const sp = <span style={{ width: 11, height: 11, borderRadius: 6, border: '2px solid rgba(255,255,255,0.35)', borderTopColor: UI.orange, display: 'inline-block' }} />;
    const ic = kind === 'ok' ? <Icon name="check" size={13} color={L.success} sw={2.2} /> :
    kind === 'err' ? <span style={{ width: 13, height: 13, borderRadius: 7, background: L.danger, color: '#fff', fontSize: 9, fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>!</span> :
    sp;
    return (
      <div style={{ alignSelf: 'flex-start', display: 'inline-flex', alignItems: 'center', gap: 8, padding: '7px 13px', borderRadius: 20, background: 'rgba(20,20,24,0.9)', color: '#fff', fontSize: 12, fontWeight: 500, boxShadow: '0 4px 14px rgba(0,0,0,0.2)' }}>
        {ic}{msg}
        {action && <span style={{ display: 'inline-flex', alignItems: 'center', gap: 2, marginLeft: 3, paddingLeft: 9, borderLeft: '1px solid rgba(255,255,255,0.2)', color: '#5AA9FF', fontWeight: 600 }}>{action}<svg width="11" height="11" viewBox="0 0 12 12" fill="none" stroke="#5AA9FF" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M4 2l4 4-4 4" /></svg></span>}
      </div>);

  }

  function TriggerUIBoard() {
    return (
      <div style={{ width: '100%', height: '100%', background: '#fff', padding: 30, boxSizing: 'border-box', fontFamily: 'var(--sf)', overflow: 'hidden' }}>
        <H>トリガー & 付随 UI</H>
        <Sub>常駐 FAB（透明・パススルー overlay 上の実体ボタン）＋ 画面下中央のステータストースト。</Sub>
        <div style={{ display: 'flex', gap: 44, flexWrap: 'wrap' }}>
          <div>
            <Cap>FAB の状態</Cap>
            <TriggerToast d={Q} scheme="light" />
          </div>
          <div style={{ flex: 1, minWidth: 280 }}>
            <Cap>トースト一覧</Cap>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 9, alignItems: 'flex-start' }}>
              <Capsule kind="spin" msg="記憶を辿っています…" />
              <Capsule kind="err" msg="記憶の書き出しに失敗しました" action="再試行" />
            </div>
            <div style={{ fontSize: 11, color: UI.sub, marginTop: 12, lineHeight: 1.5, maxWidth: 360 }}>トーストは<b style={{ color: UI.ink }}>2つだけ</b>。進行中＝「記憶を辿っています…」（オレンジのスピナー）、失敗＝「記憶の書き出しに失敗しました」（systemRed・タップで再試行、自動では消えない）。<b style={{ color: UI.ink }}>成功トーストは出さない</b>（ReportView はユーザーが × で離脱）。<br />※「権限オフ」は<b style={{ color: UI.ink }}>トーストを出さず</b>、休止FAB＋ReportView 内の誘導で扱う（→「権限オフ時の UX」）。</div>
          </div>
        </div>
      </div>);

  }

  // ── UX flow ─────────────────────────────────────────────────────────────
  function Phone({ children, dark }) {
    const t = dark ? D : L;
    return (
      <div style={{ width: 150, height: 300, borderRadius: 26, background: dark ? '#000' : '#dcdce0', padding: 4, boxShadow: '0 6px 18px rgba(0,0,0,0.14)', flex: '0 0 auto' }}>
        <div style={{ width: '100%', height: '100%', borderRadius: 22, background: t.bg, overflow: 'hidden', position: 'relative' }}>{children}</div>
      </div>);

  }
  function HostBars({ dark }) {
    const bar = dark ? 'rgba(255,255,255,0.12)' : 'rgba(28,29,36,0.10)';
    return (
      <div style={{ position: 'absolute', top: 18, left: 14, right: 14, display: 'flex', flexDirection: 'column', gap: 8 }}>
        <div style={{ height: 8, width: '60%', borderRadius: 4, background: bar }} />
        <div style={{ height: 6, width: '92%', borderRadius: 3, background: bar }} />
        <div style={{ height: 6, width: '84%', borderRadius: 3, background: bar }} />
        <div style={{ height: 44, width: '100%', borderRadius: 7, background: bar, marginTop: 4 }} />
        <div style={{ height: 6, width: '74%', borderRadius: 3, background: bar }} />
      </div>);

  }
  function MiniToast({ msg, kind, bottom = 16 }) {
    const ic = kind === 'ok' ? '✓' : null;
    return (
      <div style={{ position: 'absolute', bottom, left: '50%', transform: 'translateX(-50%)', display: 'inline-flex', alignItems: 'center', gap: 6, padding: '6px 11px', borderRadius: 16, background: 'rgba(20,20,24,0.9)', color: '#fff', fontSize: 10, fontWeight: 500, whiteSpace: 'nowrap' }}>
        {kind === 'spin' && <span style={{ width: 9, height: 9, borderRadius: 5, border: '1.6px solid rgba(255,255,255,0.35)', borderTopColor: UI.orange, display: 'inline-block' }} />}
        {kind === 'ok' && <span style={{ color: L.success }}>{ic}</span>}
        {msg}
      </div>);

  }
  function MiniFab({ tuck }) {
    return (
      <div style={{ position: 'absolute', bottom: 14, right: tuck ? 0 : 12, width: tuck ? 30 : 38, height: tuck ? 34 : 38, borderRadius: tuck ? '17px 0 0 17px' : 19, background: tuck ? '#9AA0A8' : L.ctrl, opacity: tuck ? 0.85 : 1, display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: '0 3px 9px rgba(0,0,0,0.25)' }}>
        <CleanMark ring="#fff" wedge={tuck ? L.ctrl : '#fff'} wedgeOpacity={tuck ? 1 : 0.5} hub="#fff" size={tuck ? 19 : 24} sw={3} />
      </div>);

  }
  // 共通：環境情報（左寄せ・縦積み・アイコン＋ラベル）
  function MiniEnv({ t, top }) {
    return (
      <>
        <div style={{ position: 'absolute', top, left: 12, fontSize: 7.5, fontWeight: 600, color: t.tertiary, letterSpacing: '0.02em' }}>環境情報</div>
        <div style={{ position: 'absolute', top: top + 12, left: 12, right: 12, display: 'flex', flexDirection: 'column', gap: 3 }}>
          {[['iphone', 'iPhone 16'], ['gear', 'iOS 18.4'], ['app', 'v1.0 (1)']].map(([ic, tx]) =>
          <div key={tx} style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
              <span style={{ display: 'flex', width: 10 }}><Icon name={ic} size={9} sw={1.4} color={t.secondary} /></span>
              <span style={{ fontSize: 8, color: t.secondary, ...mono }}>{tx}</span>
            </div>
          )}
        </div>
      </>);

  }
  // tiny trim scene
  function MiniTrim({ dark, share }) {
    const t = dark ? D : L;
    const frames = Array.from({ length: 10 }, (_, i) => `oklch(${(dark ? 0.32 : 0.68) + i * 31 % 18 / 100} 0.01 250)`);
    return (
      <>
        <div style={{ position: 'absolute', top: 10, left: 12, right: 12, display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <span style={{ color: t.ctrl, fontSize: 13, fontWeight: 700 }}>✕</span>
          <span style={{ color: t.label, fontSize: 11, fontWeight: 600 }}>Flashback</span>
          <span style={{ color: t.ctrl }}><Icon name="share" size={13} color={t.ctrl} sw={1.7} /></span>
        </div>
        <div style={{ position: 'absolute', top: 44, left: '50%', transform: 'translateX(-50%)', width: 52, height: 92, borderRadius: 8, background: `repeating-linear-gradient(135deg, ${t.fieldBg}, ${t.fieldBg} 6px, ${t.separator} 6px, ${t.separator} 7px)`, boxShadow: `inset 0 0 0 1px ${t.separator}` }} />
        <div style={{ position: 'absolute', top: 152, left: 12, right: 12, height: 30, borderRadius: 6, overflow: 'hidden', display: 'flex' }}>
          {frames.map((c, i) => <div key={i} style={{ flex: 1, background: c }} />)}
          <div style={{ position: 'absolute', left: 6, right: 6, top: 0, bottom: 0, borderRadius: 7, border: `2px solid ${t.ctrl}` }} />
          <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: 8, background: t.ctrl, borderRadius: '7px 0 0 7px' }} />
          <div style={{ position: 'absolute', right: 0, top: 0, bottom: 0, width: 8, background: t.ctrl, borderRadius: '0 7px 7px 0' }} />
        </div>
        <div style={{ position: 'absolute', top: 192, left: 12, right: 12, height: 22, borderRadius: 7, background: t.fieldBg, border: `1px solid ${t.separator}`, display: 'flex', alignItems: 'center', padding: '0 8px', fontSize: 9, color: t.tertiary }}>タイトルを入力</div>
        <MiniEnv t={t} top={220} />
        {share &&
        <div style={{ position: 'absolute', left: 8, right: 8, bottom: 8, borderRadius: 12, background: dark ? '#1C1C1E' : '#fff', boxShadow: '0 -2px 16px rgba(0,0,0,0.2)', padding: 10 }}>
            <div style={{ display: 'flex', gap: 10, justifyContent: 'center' }}>
              {['写真', 'ファイル', 'AirDrop'].map((x) => <div key={x} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4 }}><div style={{ width: 28, height: 28, borderRadius: 7, background: dark ? '#2C2C2E' : '#EDEDF2' }} /><span style={{ fontSize: 7.5, color: t.secondary }}>{x}</span></div>)}
            </div>
          </div>
        }
      </>);

  }

  function Step({ n, title, children, note }) {
    return (
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8, width: 150 }}>
        <div style={{ position: 'relative' }}>{children}</div>
        <div style={{ textAlign: 'center' }}>
          <div style={{ fontSize: 11.5, fontWeight: 700, color: UI.ink }}>{n} {title}</div>
          {note && <div style={{ fontSize: 10, color: UI.sub, lineHeight: 1.4, marginTop: 2 }}>{note}</div>}
        </div>
      </div>);

  }
  function Arrow() {return <div style={{ alignSelf: 'flex-start', marginTop: 130, color: UI.sub, fontSize: 18 }}>→</div>;}

  function FlowBoard() {
    return (
      <div style={{ width: '100%', height: '100%', background: '#fff', padding: 30, boxSizing: 'border-box', fontFamily: 'var(--sf)', overflow: 'hidden' }}>
        <H>UX フロー：発火 → 書き出し → トリム → 共有</H>
        <Sub>非干渉な overlay の常駐ボタン／シェイクから発火。出口は「共有」ひとつ。</Sub>
        <div style={{ display: 'flex', gap: 8, alignItems: 'flex-start' }}>
          <Step n="①" title="発火" note="シェイク / 🕘長押し0.35s">
            <Phone><HostBars /><MiniFab /></Phone>
          </Step>
          <Arrow />
          <Step n="②" title="記憶を辿る" note="直前N秒を呼び戻し中">
            <Phone><HostBars /><MiniToast kind="spin" msg="記憶を辿っています…" /></Phone>
          </Step>
          <Arrow />
          <Step n="③" title="トリム" note="両端ハンドル・ループ再生">
            <Phone><MiniTrim /></Phone>
          </Step>
          <Arrow />
          <Step n="④" title="共有" note="OS標準シート">
            <Phone><MiniTrim share /></Phone>
          </Step>
          <Arrow />
          <Step n="⑤" title="閉じる" note="× で離脱・常駐に戻る">
            <Phone><HostBars /><MiniFab /></Phone>
          </Step>
        </div>

        <div style={{ borderTop: `1px solid ${UI.rule}`, marginTop: 22, paddingTop: 18 }}>
          <Cap>例外・空状態</Cap>
          <div style={{ display: 'flex', gap: 26 }}>
            <Step n="" title="クリップ無し（録画不可）" note="権限ONだがクリップを取得できない時：Simulator・画面収録非対応・キャプチャ失敗">
              <Phone><div style={{ position: 'absolute', top: 10, left: 12, right: 12, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}><span style={{ color: L.ctrl, fontSize: 13, fontWeight: 700 }}>✕</span><span style={{ fontSize: 11, fontWeight: 600 }}>Flashback</span><span style={{ color: L.ctrl, display: 'flex' }}><Icon name="gear" size={13} color={L.ctrl} sw={1.6} /></span></div><div style={{ position: 'absolute', top: 44, left: 12, right: 12, height: 96, borderRadius: 12, border: `1px dashed ${L.separator}`, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 5, fontSize: 9, color: L.tertiary }}><Icon name="iphone" size={20} sw={1.4} color={L.tertiary} /><span style={{ ...mono }}>クリップを取得できません</span></div><div style={{ position: 'absolute', top: 148, left: 12, right: 12, fontSize: 8, color: L.tertiary, lineHeight: 1.4 }}>このビルドでは録画を保存できません。</div><MiniEnv t={L} top={178} /></Phone>
            </Step>
            <Step n="" title="権限オフ（おやすみ）" note="エラーにせずやさしく誘導">
              <Phone><OffInner /></Phone>
            </Step>
            <Step n="" title="書き出し失敗" note="タップで再試行">
              <Phone><HostBars /><MiniToast kind="err" msg="失敗・再試行" /></Phone>
            </Step>
            <div style={{ flex: 1, background: UI.faint, borderRadius: 12, padding: '14px 16px', alignSelf: 'stretch', maxWidth: 300 }}>
              <div style={{ fontSize: 12, fontWeight: 700, color: UI.ink, marginBottom: 6 }}>原則</div>
              <div style={{ fontSize: 11, color: UI.sub, lineHeight: 1.6 }}>最初から許可していない人に<b>権限エラーを出さない</b>。発火時は書き出しをバイパスして ReportView を開き、中でやさしく許可を促す。失敗・想定外のみトーストで非破壊的に通知。左上 ✕ はいつでもキャンセル。</div>
            </div>
          </div>
        </div>
      </div>);

  }

  // ── 権限オフ（おやすみ）時の UX ──────────────────────────────────────────
  function DormFab({ on }) {
    return (
      <div style={{ position: 'absolute', bottom: 14, right: 12, width: 38, height: 38 }}>
        <div style={{ width: 38, height: 38, borderRadius: 19, background: on ? L.ctrl : '#9AA0A8', opacity: on ? 1 : 0.92, display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: '0 3px 9px rgba(0,0,0,0.25)' }}>
          <CleanMark ring="#fff" wedge="#fff" wedgeOpacity={on ? 0.5 : 0.6} hub="#fff" size={24} sw={3} />
        </div>
      </div>);

  }
  function OffInner() {
    const t = L;
    return (
      <>
        <div style={{ position: 'absolute', top: 10, left: 12, right: 12, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <span style={{ color: t.ctrl, fontSize: 13, fontWeight: 700 }}>✕</span>
          <span style={{ fontSize: 11, fontWeight: 600 }}>Flashback</span>
          <span style={{ color: t.ctrl, display: 'flex' }}><Icon name="gear" size={13} color={t.ctrl} sw={1.6} /></span>
        </div>
        <div style={{ position: 'absolute', top: 40, left: 12, right: 12, height: 78, borderRadius: 10, border: `1px dashed ${t.separator}`, background: t.fieldBg, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 6 }}>
          <div style={{ position: 'relative', width: 24, height: 24 }}>
            <CleanMark ring={t.tertiary} wedge={t.secondary} wedgeOpacity={0.55} hub={t.tertiary} size={24} sw={3.4} />
          </div>
          <span style={{ fontSize: 9.5, fontWeight: 600, color: t.secondary }}>録画はオフです</span>
        </div>
        <div style={{ position: 'absolute', top: 126, left: 12, right: 12, display: 'flex', alignItems: 'center', gap: 4, color: t.ctrl }}>
          <CleanMark ring={t.ctrl} wedge={t.ctrl} wedgeOpacity={0.5} hub={t.ctrl} size={11} sw={3.4} />
          <span style={{ fontSize: 9.5, fontWeight: 700 }}>録画をオンにする</span>
        </div>
        <div style={{ position: 'absolute', top: 148, left: 12, right: 12, fontSize: 8, color: t.tertiary, lineHeight: 1.4 }}>オンにすると、次回から直前の画面録画を自動で保持します。</div>
        <MiniEnv t={t} top={180} />
      </>);

  }
  function OffSettings() {
    const t = L;
    const Tog = ({ on }) => <div style={{ width: 28, height: 16, borderRadius: 8, background: on ? t.success : '#C7C7CC', position: 'relative', flex: '0 0 auto' }}><div style={{ position: 'absolute', top: 1.5, left: on ? 13.5 : 1.5, width: 13, height: 13, borderRadius: 7, background: '#fff', boxShadow: '0 1px 2px rgba(0,0,0,0.3)' }} /></div>;
    const Row = ({ label, val, tog, on, top }) =>
    <div style={{ display: 'flex', alignItems: 'center', padding: '8px 10px', gap: 8, borderTop: top ? `0.5px solid ${t.separator}` : 'none' }}>
        <span style={{ fontSize: 10.5, color: t.label, flex: 1 }}>{label}</span>
        {tog ? <Tog on={on} /> : <span style={{ fontSize: 10, color: t.secondary }}>{val}</span>}
      </div>;
    return (
      <>
        {/* iOS「設定」アプリ：FlashbackKit の権限ページ（直接 deep link） */}
        <div style={{ position: 'absolute', top: 12, left: 12, right: 12, display: 'flex', alignItems: 'center' }}>
          <span style={{ color: '#007AFF', fontSize: 11, fontWeight: 400, display: 'flex', alignItems: 'center', gap: 1 }}>
            <svg width="6" height="11" viewBox="0 0 6 11" fill="none" stroke="#007AFF" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M5 1L1 5.5 5 10" /></svg>設定
          </span>
          <span style={{ position: 'absolute', left: '50%', transform: 'translateX(-50%)', fontSize: 11, fontWeight: 600, color: t.label }}>FlashbackKit</span>
        </div>
        <div style={{ position: 'absolute', top: 40, left: 0, right: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 5 }}>
          <div style={{ width: 32, height: 32, borderRadius: 8, background: t.ctrl, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><CleanMark ring="#fff" wedge="#fff" wedgeOpacity={0.5} hub="#fff" size={21} sw={3} /></div>
        </div>
        <div style={{ position: 'absolute', top: 84, left: 12, fontSize: 8.5, color: t.secondary }}>FLASHBACKKIT に許可</div>
        <div style={{ position: 'absolute', top: 96, left: 12, right: 12, background: '#fff', borderRadius: 9, overflow: 'hidden', boxShadow: `inset 0 0 0 1px ${t.separator}` }}>
          <Row label="写真" val="フルアクセス" top={false} />
          <Row label="画面収録" tog on top />
        </div>
        <div style={{ position: 'absolute', top: 156, left: 12, right: 12, fontSize: 8, color: t.tertiary, lineHeight: 1.4 }}>アプリ内設定を挟まず、OS の許可ページへ直接ジャンプ。</div>
      </>);

  }

  function DormantBoard() {
    const FabState = ({ on, label, sub }) =>
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 9, width: 116 }}>
        <div style={{ position: 'relative', width: 56, height: 56 }}>
          <div style={{ width: 56, height: 56, borderRadius: 28, background: on ? L.ctrl : '#9AA0A8', opacity: on ? 1 : 0.92, display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: '0 4px 12px rgba(0,0,0,0.2)' }}>
            <CleanMark ring="#fff" wedge="#fff" wedgeOpacity={on ? 0.5 : 0.6} hub="#fff" size={36} sw={3} />
          </div>
        </div>
        <div style={{ textAlign: 'center' }}>
          <div style={{ fontSize: 12, fontWeight: 700, color: UI.ink }}>{label}</div>
          <div style={{ fontSize: 10, color: UI.sub, lineHeight: 1.4, marginTop: 2 }}>{sub}</div>
        </div>
      </div>;

    return (
      <div style={{ width: '100%', height: '100%', background: '#fff', padding: 30, boxSizing: 'border-box', fontFamily: 'var(--sf)', overflow: 'hidden' }}>
        <H>権限オフ（おやすみ）時の UX</H>
        <Sub>録画を許可しなかった人を<b style={{ color: UI.ink }}>エラーで責めない</b>。FAB は休止表現にし、発火時は書き出しを<b style={{ color: UI.ink }}>バイパスして即 ReportView</b>へ。許可は設定で任意に。</Sub>

        <div style={{ display: 'flex', gap: 40, alignItems: 'flex-start' }}>
          {/* FAB 状態の対比 */}
          <div>
            <Cap>FAB：録画ON / OFF</Cap>
            <div style={{ display: 'flex', gap: 16 }}>
              <FabState on label="通常（ON）" sub="オレンジ地＝録画中・直前を保持" />
              <FabState label="休止（OFF）" sub="グレー地＝録画オフ・扇は白で控えめに" />
            </div>
            <div style={{ fontSize: 11, color: UI.sub, marginTop: 14, lineHeight: 1.55, maxWidth: 260 }}>
              <b style={{ color: UI.ink }}>ボタンの地色</b>で状態を表現（<b style={{ color: UI.ink }}>オレンジ＝録画中／グレー＝録画オフ</b>）。休止の扇は<b style={{ color: UI.ink }}>ニュートラル</b>（地に応じて白↔グレーに振る）で控えめにし、オレンジは「録画中」専用。端タック中は半円型で端に吸着＝退避（録画中ならオレンジのまま）。
            </div>
          </div>

          {/* バイパスフロー */}
          <div style={{ flex: 1 }}>
            <Cap>発火時のフロー（録画OFF）</Cap>
            <div style={{ display: 'flex', gap: 6, alignItems: 'flex-start' }}>
              <Step n="①" title="休止FAB" note="常駐・グレー">
                <Phone><HostBars /><DormFab /></Phone>
              </Step>
              <Arrow />
              <Step n="②" title="発火" note="書き出しをスキップ">
                <Phone><HostBars /><DormFab /></Phone>
              </Step>
              <Arrow />
              <Step n="③" title="ReportView" note="やさしい誘導・非エラー">
                <Phone><OffInner /></Phone>
              </Step>
              <Arrow />
              <Step n="④" title="iOS設定（直接）" note="アプリ内設定を挟まず deep link">
                <Phone><OffSettings /></Phone>
              </Step>
              <Arrow />
              <Step n="⑤" title="以降は通常" note="次回から直前を保持">
                <Phone><HostBars /><DormFab on /></Phone>
              </Step>
            </div>
          </div>
        </div>

        {/* 「録画をオンにする」挙動の注記 */}
        <div style={{ marginTop: 16, background: UI.faint, borderRadius: 12, padding: '12px 16px' }}>
          <div style={{ fontSize: 12, fontWeight: 700, color: UI.ink, marginBottom: 5 }}>「録画をオンにする」を押すと？</div>
          <div style={{ fontSize: 11, color: UI.sub, lineHeight: 1.6 }}>
            <b style={{ color: UI.ink }}>初回（未決定）</b>＝OS の画面収録の許可ダイアログを表示（ReplayKit）。許可すれば以降 ⑤ の通常運用へ。<br />
            <b style={{ color: UI.ink }}>一度拒否済み</b>＝OS は再度ダイアログを出さないため、<b style={{ color: UI.ink }}>アプリ内設定を挟まず iOS の許可ページへ直接 deep link</b>（＝④）。アプリ内で承認ダイアログを偽装したり、勝手に設定を変えることはしない。
          </div>
        </div>

        {/* トースト方針 */}
        <div style={{ borderTop: `1px solid ${UI.rule}`, marginTop: 22, paddingTop: 18, display: 'flex', gap: 18 }}>
          <div style={{ flex: 1, background: UI.faint, borderRadius: 12, padding: '14px 16px' }}>
            <div style={{ fontSize: 12, fontWeight: 700, color: '#1F8A5B', marginBottom: 6 }}>トーストを出す</div>
            <div style={{ fontSize: 11, color: UI.sub, lineHeight: 1.6 }}>
              <b style={{ color: UI.ink }}>進行中</b>：「過去を思い出しています…」「記憶を書き出しています…」（成功トーストは出さない＝ユーザーが × で離脱）。<br />
              <b style={{ color: UI.ink }}>想定外の失敗</b>（systemRed・操作付き）：許可済みなのに録画開始に失敗／記憶の書き出しに失敗（タップで再試行）。<br />
              ＝<b style={{ color: UI.ink }}>一度は録画ONにした人に起きた失敗</b>を知らせる用途。
            </div>
          </div>
          <div style={{ flex: 1, background: UI.faint, borderRadius: 12, padding: '14px 16px' }}>
            <div style={{ fontSize: 12, fontWeight: 700, color: UI.sub, marginBottom: 6 }}>トーストを出さない</div>
            <div style={{ fontSize: 11, color: UI.sub, lineHeight: 1.6 }}>最初から<b style={{ color: UI.ink }}>許可していない</b>人への権限エラー。これは<b style={{ color: UI.ink }}>休止FAB＋バイパス</b>で静かに表現し、ReportView 内でやさしく許可を促す。</div>
          </div>
        </div>
      </div>);

  }

  // ── FAB とマークの比率の比較 ──────────────────────────────────────────
  function FabSizeBoard() {
    const Opt = ({ fab, mark, label, rec = true, star }) =>
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10, width: 132 }}>
        <div style={{ height: 64, display: 'flex', alignItems: 'center' }}>
          <div style={{ width: fab, height: fab, borderRadius: fab / 2, background: rec ? L.ctrl : '#9AA0A8', display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: '0 4px 12px rgba(0,0,0,0.2)' }}>
            <CleanMark ring="#fff" wedge={rec ? '#fff' : L.ctrl} wedgeOpacity={rec ? 0.5 : 1} hub="#fff" size={mark} sw={3} />
          </div>
        </div>
        <div style={{ textAlign: 'center' }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 4 }}>
            <span style={{ fontSize: 12, fontWeight: 700, color: UI.ink }}>{label}</span>
            {star && <span style={{ color: L.ctrl, fontSize: 11 }}>★</span>}
          </div>
          <div style={{ fontSize: 10, color: UI.sub, marginTop: 2, ...mono }}>FAB {fab} / mark {mark}</div>
          <div style={{ fontSize: 9.5, color: UI.sub, marginTop: 1, ...mono }}>比 {(mark / fab).toFixed(2)}</div>
        </div>
      </div>;
    return (
      <div style={{ width: '100%', height: '100%', background: '#fff', padding: 30, boxSizing: 'border-box', fontFamily: 'var(--sf)', overflow: 'hidden' }}>
        <H>FAB とマークの比率</H>
        <Sub>現状はマークが小さめ。マークを大きく／FAB を小さくした案を実寸で比較（タップ領域は <b style={{ color: UI.ink }}>44pt 以上</b>を確保）。</Sub>
        <div style={{ display: 'flex', gap: 24, alignItems: 'flex-end', marginTop: 4 }}>
          <Opt fab={56} mark={28} label="現状" />
          <Opt fab={56} mark={36} label="マーク大（確定）" star />
          <Opt fab={56} mark={42} label="マーク特大" />
          <div style={{ width: 1, alignSelf: 'stretch', background: UI.rule, margin: '0 4px' }} />
          <Opt fab={48} mark={30} label="FAB小" />
          <Opt fab={44} mark={28} label="FAB特小" />
        </div>
        <div style={{ borderTop: `1px solid ${UI.rule}`, marginTop: 24, paddingTop: 16, fontSize: 11.5, color: UI.sub, lineHeight: 1.6, maxWidth: 760 }}>
          <b style={{ color: UI.ink }}>確定：マーク大（56 / 36・比0.64）</b>。FAB は <b style={{ color: UI.ink }}>44pt 以上</b>のタップ領域を保ちつつ、マークを一回り大きくして視認性を確保。全 FAB（通常・長押し・端タック・休止）にこの比率を適用済み。
        </div>
      </div>);

  }

  // ── 休止FABの扇カラー比較（実画面・2文脈） ───────────────────────────────
  function DormWedgeBoard() {
    const Fab = ({ w, o }) =>
    <div style={{ width: 56, height: 56, borderRadius: 28, background: '#9AA0A8', display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: '0 4px 12px rgba(0,0,0,0.2)' }}>
        <CleanMark ring="#fff" wedge={w} wedgeOpacity={o} hub="#fff" size={36} sw={3} />
      </div>;
    const ClockBox = ({ w, o }) =>
    <div style={{ width: 124, height: 82, borderRadius: 12, border: `1px dashed ${L.separator}`, background: L.fieldBg, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 6 }}>
        <CleanMark ring={L.tertiary} wedge={w} wedgeOpacity={o} hub={L.tertiary} size={30} sw={3.2} />
        <span style={{ fontSize: 9, fontWeight: 600, color: L.secondary }}>録画はオフです</span>
      </div>;
    const opts = [
    { label: 'オレンジ', fab: [L.ctrl, 1], clk: [L.ctrl, 1], note: '“動作中”に見えがち' },
    { label: 'ニュートラル', fab: ['#fff', 0.6], clk: [L.secondary, 0.55], note: '地に応じ白/グレー・穏やか', star: true },
    { label: 'うっすら', fab: ['#fff', 0.35], clk: [L.tertiary, 0.9], note: 'ほぼ気配だけ・最も静か' },
    { label: '扇なし', fab: ['#fff', 0], clk: [L.tertiary, 0], note: 'リングのみ＝完全に静' }];

    return (
      <div style={{ width: '100%', height: '100%', background: '#fff', padding: 30, boxSizing: 'border-box', fontFamily: 'var(--sf)', overflow: 'hidden' }}>
        <H>休止FABの扇カラー（実画面で比較）</H>
        <Sub>同じ色でも<b style={{ color: UI.ink }}>FAB（グレー地）</b>と<b style={{ color: UI.ink }}>ReportView の時計（淡い地）</b>で見え方が変わる。両文脈で確認（白系は淡い地では消えるため、地に応じて白↔グレーに振る運用）。</Sub>
        <div style={{ display: 'flex', gap: 18, alignItems: 'flex-start', marginTop: 4 }}>
          {opts.map((o, i) =>
          <React.Fragment key={o.label}>
              {i > 0 && <div style={{ width: 1, alignSelf: 'stretch', background: UI.rule }} />}
              <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 14, width: 150 }}>
                <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6 }}>
                  <Fab w={o.fab[0]} o={o.fab[1]} />
                  <span style={{ fontSize: 9, color: UI.sub }}>常駐 FAB</span>
                </div>
                <ClockBox w={o.clk[0]} o={o.clk[1]} />
                <div style={{ textAlign: 'center' }}>
                  <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 4 }}>
                    <span style={{ fontSize: 12, fontWeight: 700, color: UI.ink }}>{o.label}</span>
                    {o.star && <span style={{ color: L.ctrl, fontSize: 11 }}>★</span>}
                  </div>
                  <div style={{ fontSize: 10, color: UI.sub, marginTop: 2, lineHeight: 1.35 }}>{o.note}</div>
                </div>
              </div>
            </React.Fragment>
          )}
        </div>
        <div style={{ borderTop: `1px solid ${UI.rule}`, marginTop: 22, paddingTop: 16, fontSize: 11.5, color: UI.sub, lineHeight: 1.6, maxWidth: 820 }}>
          <b style={{ color: UI.ink }}>確定：ニュートラル（適用済み）</b>。FAB（グレー地）＝白0.6、ReportView の時計（淡い地）＝グレー0.55 と、<b style={{ color: UI.ink }}>地に応じて白↔グレー</b>へ振る。オレンジは「録画中」専用にして、ON/OFF の区別を明快に。
        </div>
      </div>);

  }

  Object.assign(window, { TokenBoard, SwiftTokenBoard, TriggerUIBoard, FlowBoard, DormantBoard, FabSizeBoard, DormWedgeBoard });
})();