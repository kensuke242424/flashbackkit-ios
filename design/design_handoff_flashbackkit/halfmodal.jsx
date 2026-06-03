/* halfmodal.jsx — 別案：ハーフモーダル ReportView
   Exports to window: HalfModalBoard.
   uses globals: CleanMark, Icon, StatusBar, window.DIRECTIONS */

(function () {
  const Q = window.DIRECTIONS[2]; // Quiet 確定
  const L = Q.light;
  const UI = { ink: '#1c1d24', sub: '#6A6B74', rule: '#ECECEF', faint: '#F7F7F9' };
  const mono = { fontFamily: 'var(--mono)' };

  const H = ({ children }) => <div style={{ fontSize: 19, fontWeight: 700, color: UI.ink, letterSpacing: '-0.01em' }}>{children}</div>;
  const Sub = ({ children }) => <div style={{ fontSize: 12.5, color: '#46474f', lineHeight: 1.5, margin: '4px 0 18px', maxWidth: 880 }}>{children}</div>;
  const Cap = ({ children }) => <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: '0.06em', textTransform: 'uppercase', color: UI.sub, marginBottom: 12 }}>{children}</div>;

  // grayscale filmstrip frames
  const FRAMES = Array.from({ length: 12 }, (_, i) => `oklch(${0.66 + i * 37 % 22 / 100} 0.012 250)`);

  function Filmstrip({ w }) {
    return (
      <div style={{ position: 'relative', height: 40, width: w }}>
        <div style={{ position: 'absolute', inset: '0 12px', borderRadius: 6, overflow: 'hidden', display: 'flex' }}>
          {FRAMES.map((c, i) => <div key={i} style={{ flex: 1, background: c }} />)}
        </div>
        <div style={{ position: 'absolute', left: 6, right: 6, top: 0, bottom: 0, borderRadius: 8, border: `2.5px solid ${L.ctrl}`, boxShadow: '0 0 0 2px #fff' }} />
        {[6, null].map((l, i) =>
        <div key={i} style={{ position: 'absolute', [i === 0 ? 'left' : 'right']: 0, top: 0, bottom: 0, width: 12, background: L.ctrl, borderRadius: i === 0 ? '8px 0 0 8px' : '0 8px 8px 0', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <div style={{ width: 2, height: 14, borderRadius: 2, background: '#fff', opacity: 0.85 }} />
          </div>
        )}
        <div style={{ position: 'absolute', left: '40%', top: -2, bottom: -2, width: 2, background: L.label, borderRadius: 2 }} />
      </div>);

  }

  function VideoPrev({ w, h }) {
    return (
      <div style={{ width: w, height: h, borderRadius: 12, position: 'relative', overflow: 'hidden', background: `repeating-linear-gradient(135deg, ${L.fieldBg}, ${L.fieldBg} 7px, ${L.separator} 7px, ${L.separator} 8px)`, boxShadow: `inset 0 0 0 1px ${L.separator}` }}>
        <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <div style={{ width: 30, height: 30, borderRadius: 15, background: 'rgba(0,0,0,0.35)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <span style={{ color: '#fff', marginLeft: 2 }}><Icon name="play" size={14} /></span>
          </div>
        </div>
      </div>);

  }

  // Phone with a bottom sheet at a given detent: 'medium' | 'large'
  function PhoneSheet({ detent }) {
    const W = 250,Hh = 520;
    const large = detent === 'large';
    const sheetH = large ? Hh * 0.9 : Hh * 0.52;
    const vidW = large ? 120 : 84,vidH = large ? 214 : 150;
    return (
      <div style={{ width: W, height: Hh, position: 'relative' }}>
        {/* device */}
        <div style={{ position: 'absolute', inset: 0, borderRadius: 40, background: '#dcdce0', padding: 5, boxShadow: '0 10px 30px rgba(0,0,0,0.14)' }}>
          <div style={{ width: '100%', height: '100%', borderRadius: 35, overflow: 'hidden', position: 'relative', background: '#0b0b0e' }}>
            {/* dimmed host behind */}
            <div style={{ position: 'absolute', inset: 0, background: '#15151b' }}>
              <div style={{ position: 'absolute', top: 18, left: 16, right: 16, display: 'flex', flexDirection: 'column', gap: 8, opacity: 0.18 }}>
                <div style={{ height: 9, width: '55%', borderRadius: 4, background: '#fff' }} />
                <div style={{ height: 7, width: '90%', borderRadius: 3, background: '#fff' }} />
                <div style={{ height: 7, width: '80%', borderRadius: 3, background: '#fff' }} />
                <div style={{ height: 120, borderRadius: 8, background: '#fff', marginTop: 4 }} />
              </div>
            </div>
            {/* scrim */}
            <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.32)' }} />

            {/* sheet */}
            <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: sheetH, background: L.bg, borderRadius: '18px 18px 0 0', boxShadow: '0 -8px 28px rgba(0,0,0,0.3)', display: 'flex', flexDirection: 'column', transition: 'height .3s' }}>
              {/* grabber */}
              <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 8 }}>
                <div style={{ width: 36, height: 5, borderRadius: 3, background: L.tertiary }} />
              </div>
              {/* nav */}
              <div style={{ height: 38, display: 'flex', alignItems: 'center', padding: '0 14px', position: 'relative' }}>
                <span style={{ color: L.ctrl }}><Icon name="close" size={19} sw={2} /></span>
                <span style={{ position: 'absolute', left: '50%', transform: 'translateX(-50%)', fontSize: 14, fontWeight: 600, color: L.label }}>Flashback</span>
                <span style={{ marginLeft: 'auto', color: L.ctrl }}><Icon name="share" size={18} sw={1.7} /></span>
              </div>

              {/* content */}
              <div style={{ flex: 1, padding: '2px 16px 0', display: 'flex', flexDirection: 'column', alignItems: 'center', overflow: 'hidden' }}>
                <VideoPrev w={vidW} h={vidH} />
                {/* play + range */}
                <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 10, alignSelf: 'stretch' }}>
                  <div style={{ width: 26, height: 26, borderRadius: 13, background: L.ctrl, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                    <span style={{ color: '#fff', marginLeft: 2 }}><Icon name="play" size={11} /></span>
                  </div>
                  <span style={{ fontSize: 11, color: L.secondary, ...mono }}>0:00 ~ 0:12 (0:12)</span>
                </div>
                <div style={{ alignSelf: 'stretch', marginTop: 8 }}><Filmstrip w="100%" /></div>
                {/* クリップカーソル下の操作余白（ハンドルを掴みやすく） */}
                {!large && <div style={{ height: 28, flex: '0 0 auto' }} />}

                {/* revealed only at large detent */}
                {large &&
                <div style={{ alignSelf: 'stretch', marginTop: 16, opacity: 1 }}>
                    <div style={{ fontSize: 12, fontWeight: 600, color: L.label, marginBottom: 6 }}>タイトル</div>
                    <div style={{ height: 34, borderRadius: 9, background: L.fieldBg, border: `1px solid ${L.separator}`, display: 'flex', alignItems: 'center', padding: '0 11px', fontSize: 12, color: L.tertiary }}>タイトルを入力</div>
                    <div style={{ fontSize: 10.5, fontWeight: 600, color: L.tertiary, marginTop: 14, marginBottom: 5 }}>環境情報</div>
                    {[['iphone', 'iPhone 16'], ['gear', 'iOS 18.4'], ['app', 'v1.0 (1)']].map(([ic, tx]) =>
                  <div key={tx} style={{ display: 'flex', alignItems: 'center', gap: 7, marginBottom: 3 }}>
                        <span style={{ display: 'flex', width: 13 }}><Icon name={ic} size={12} sw={1.4} color={L.secondary} /></span>
                        <span style={{ fontSize: 11.5, color: L.secondary, ...mono }}>{tx}</span>
                      </div>
                  )}
                  </div>
                }
              </div>
            </div>

            {/* status bar over everything */}
            <div style={{ position: 'absolute', top: 0, left: 0, right: 0 }}><StatusBar t={{ label: '#fff' }} /></div>
          </div>
        </div>
      </div>);

  }

  // a small drag indicator arrow
  function DragHint({ dir, label }) {
    return (
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, color: L.ctrl }}>
        <svg width="22" height="30" viewBox="0 0 22 30" fill="none" stroke={L.ctrl} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          {dir === 'up' ? <><path d="M11 27V5" /><path d="M4 12l7-7 7 7" /></> : <><path d="M11 3v22" /><path d="M4 18l7 7 7-7" /></>}
        </svg>
        <span style={{ fontSize: 10.5, color: UI.sub, fontWeight: 600, whiteSpace: 'nowrap' }}>{label}</span>
      </div>);

  }

  function Card({ title, color, children }) {
    return (
      <div style={{ flex: 1, background: UI.faint, borderRadius: 12, padding: '14px 16px' }}>
        <div style={{ fontSize: 12, fontWeight: 700, color: color || UI.ink, marginBottom: 6 }}>{title}</div>
        <div style={{ fontSize: 11.5, color: UI.sub, lineHeight: 1.6 }}>{children}</div>
      </div>);

  }

  function HalfModalBoard() {
    return (
      <div style={{ width: '100%', height: '100%', background: '#fff', padding: 30, boxSizing: 'border-box', fontFamily: 'var(--sf)', overflow: 'hidden' }}>
        <H>参考案（不採用）：ハーフモーダル ReportView</H>
        <Sub><b style={{ color: '#C0392B' }}>※ 主案はフルスクリーンに確定。</b>本案は圧迫感を抑える探索として記録に残す。発火直後は<b style={{ color: UI.ink }}>中位（.medium）</b>で「動画＋トリム」だけを操作可能に。<b style={{ color: UI.ink }}>引き上げる（.large）</b>と動画が拡大し、タイトル・環境情報が現れる。<b style={{ color: UI.ink }}>下げる</b>とそのまま閉じる。iOS 16+ の <span style={{ ...mono }}>UISheetPresentationController</span>（detents・グラバー）でネイティブ実装可。</Sub>

        <div style={{ display: 'flex', gap: 26, alignItems: 'center' }}>
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10 }}>
            <PhoneSheet detent="medium" />
            <div style={{ fontSize: 12, fontWeight: 700, color: UI.ink }}>① 中位（初期）</div>
            <div style={{ fontSize: 10.5, color: UI.sub, textAlign: 'center', maxWidth: 220, lineHeight: 1.45 }}>発火直後。動画プレビューとトリム（フィルムストリップ＋ハンドル）だけが見え、すぐ切れる。背景のホスト画面が透けて圧迫感が少ない。</div>
          </div>

          <DragHint dir="up" label="引き上げ" />

          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10 }}>
            <PhoneSheet detent="large" />
            <div style={{ fontSize: 12, fontWeight: 700, color: UI.ink }}>② 拡張（引き上げ後）</div>
            <div style={{ fontSize: 10.5, color: UI.sub, textAlign: 'center', maxWidth: 220, lineHeight: 1.45 }}>動画が一回り拡大して見やすく。タイトル入力欄・環境情報が下に現れる。共有は右上のまま。</div>
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8, paddingLeft: 6 }}>
            <DragHint dir="down" label="下げて閉じる" />
            <div style={{ fontSize: 10.5, color: UI.sub, textAlign: 'center', maxWidth: 130, lineHeight: 1.45, marginTop: 4 }}>下スワイプ／× で離脱。送信や保存は無し。</div>
          </div>
        </div>

        <div style={{ borderTop: `1px solid ${UI.rule}`, marginTop: 24, paddingTop: 18, display: 'flex', gap: 16 }}>
          <Card title="ねらい・利点" color="#1F8A5B">
            視覚的圧迫感を軽減。<b style={{ color: UI.ink }}>“まず触りたい動画＋トリム”を最短距離</b>に置き、詳細（タイトル・環境）は必要な人だけ引き上げて入力。片手・親指で開閉でき、ホスト文脈も透けて残る。
          </Card>
          <Card title="トレードオフ・留意">
            中位では縦の動画が小さくなりがち（拡大は引き上げ前提）。グラバーと×の<b style={{ color: UI.ink }}>役割の重複</b>に注意。トリマーのドラッグとシートのドラッグが<b style={{ color: UI.ink }}>ジェスチャ競合</b>しやすい→トリム領域はシートのドラッグを無効化する設計が必要。
          </Card>
          <Card title="SwiftUI 実装メモ">
            <span style={{ ...mono, fontSize: 11 }}>.presentationDetents([.medium, .large])</span> ／ <span style={{ ...mono, fontSize: 11 }}>.presentationDragIndicator(.visible)</span>。トリム中は <span style={{ ...mono, fontSize: 11 }}>.interactiveDismissDisabled</span> 相当でシート移動を抑止。中位↔大で動画サイズを <span style={{ ...mono, fontSize: 11 }}>matchedGeometryEffect</span> で補間。
          </Card>
        </div>
      </div>);

  }

  Object.assign(window, { HalfModalBoard });
})();